# Architecture

Wrainrock Linux is a **bootc system image**: an OCI container whose root
filesystem is the operating system. This document covers how the image is
produced, what is invariant about it, how releases are identified and signed,
and what the project deliberately does not do.

## Feeding from Fedora Silverblue

The base feedstock is the official Fedora Atomic Desktop image:

```
quay.io/fedora/fedora-silverblue:44
```

These are not "container-ish" images. Since Fedora 38 they carry the bootc
contract directly (`containers.bootc=1`, `ostree.bootable=true`) and can be
installed or switched to as an OS. We consume them as an OCI base layer, pin the
resolved digest at build time, and record it in the image.

The choice of Silverblue over `fedora-bootc` is deliberate: `fedora-bootc` is a
minimal image with no desktop. Wrainrock v0.1 wants exactly the GNOME desktop
that Fedora ships and maintains, with Fedora's kernel, firmware, driver and
update cadence. Owning that stack ourselves is a v0.4+ decision, not a bootstrap
one.

### Why bootc and not `rpm-ostree compose`

Fedora is moving Atomic Desktops to container-native builds (the "Build Atomic
Desktops with Konflux" change targets Fedora 46). Building with bootc today:

- uses the same artifact format the next Fedora generation ships;
- makes local reproduction a `podman build` rather than a Koji compose;
- gives OCI-native distribution, signing and mirroring for free;
- keeps `rpm-ostree` out of the *build* path (it remains the update backend on
  the installed system, which is fine).

## Build pipeline

```
image.env ──► workflow (lint) ──► pull base, resolve digest
                                        │
                                        ▼
                              Containerfile (FROM digest-pinned base)
                                        │
                              build_files/build.sh
                              (assert base identity, write provenance)
                                        │
                              bootc container lint
                                        │
                    ┌───────────────────┼───────────────────┐
                    ▼                   ▼                   ▼
             parity test           smoke test           (PRs stop here)
                    │                   │
                    └─────────┬─────────┘
                              ▼
                 push immutable tag ──► cosign sign ──► push channel tags
```

Everything is driven by `image.env`, so "which Fedora release is this?" is a
one-line, reviewable change.

### The parity invariant (v0.1)

For v0.1 the repository enforces a single strong invariant:

> The image's RPM set and `/usr/lib/os-release` are identical to the base
> image's. The only added files are under `/usr/share/wrainrock/`.

The parity test diffs `rpm -qa` between the base and the built image and diffs
`/usr/lib/os-release`. This is what makes v0.1 falsifiable: a green build is
proof that the pipeline is a faithful reproducer, not that we "customized
something and hope".

Once v0.2 starts changing the system, this invariant is deliberately relaxed:
the test moves from "identical" to "superset, with recorded deltas". The
mechanism itself (compare against base, fail on unexpected drift) stays.

### Provenance

`build_files/build.sh` writes two files:

- `/usr/share/wrainrock/build-info.json` — schema, image/version, build
  number, git SHA, build date, base image + digest, Fedora version, parity
  marker, RPM count, RPM-set SHA-256.
- `/usr/share/wrainrock/base-os-release` — pristine copy of the base's
  `/usr/lib/os-release`, so "what was this built from?" survives even after
  `/usr/lib/os-release` is customized in later versions.

The build fails if the base is not `ID=fedora`, `VERSION_ID=44`,
`VARIANT_ID=silverblue`, or if `/usr/bin/bootc` / `/usr/lib/bootc` are missing.
That is a single-match assertion on the base, not a comment.

## Tags and release identity

| Tag | Example | Mutability | Purpose |
| --- | --- | --- | --- |
| immutable | `44.20261017T061500Z.42` | never overwritten | artifact of record |
| channel | `44` | moves per build | what users follow |
| alias | `latest` | moves per build | newest channel |
| rollback aid | `previous` | moves per build | outgoing channel image |

Rules, enforced in CI:

1. Every build first computes the immutable tag from the Fedora version, the
   UTC build timestamp and the workflow run number.
2. Before pushing, CI checks the registry for that tag and **fails if it already
   exists**. Published artifacts are never replaced.
3. Only `main` publishes. Pull requests build and test but cannot touch the
   registry, so a PR cannot become someone's next `bootc update`.
4. Before moving `44`, CI tags the current `44` digest as `previous` and pushes
   it. This gives a second, registry-side rollback target in addition to the
   local `bootc rollback` deployment.
5. Channel tags are pushed only after the immutable artifact exists, so a
   broken channel push can be retried without reusing an artifact tag.

Nightly rebuilds keep the channel current with Fedora security updates even when
Wrainrock's own source doesn't change. A rebuild of the same base digest and
same commit yields the same RPM set; the `build-info.json` RPM hash is the cheap
way to spot drift.

## Update lifecycle on an installed system

```
bootc update        fetch :44, pull new image, stage deployment
systemctl reboot    boot into the new deployment
bootc rollback      select the previous deployment
systemctl reboot    boot into it
```

`bootc` stages a new deployment; the old one stays on disk. Rollback is a local,
offline operation — it does not depend on the network or on the registry, which
is why it works when a release is bad or the network is down.

Automatic updates are intentionally **not** enabled by this image. A
distribution that updates its own kernel and desktop without an operator in the
loop is a support problem; the default is manual `bootc update`, with an opt-in
timer documented in [docs/install.md](install.md).

## Trust and supply chain

- **Base:** official Fedora image from `quay.io`, pulled by digest at build time
  and recorded in `build-info.json`.
- **Build:** public GitHub Actions workflow; no self-hosted runner, no long-lived
  registry credential. The only secrets are the ephemeral `GITHUB_TOKEN` and the
  OIDC token used by cosign.
- **Publish:** `ghcr.io`, immutable tags, keyless Sigstore signature whose
  certificate identity is bound to this repository's workflow.
- **Verify:** `cosign verify` with
  `--certificate-identity-regexp '^https://github.com/Wraindrock/wrainrock-linux/'`
  and issuer `https://token.actions.githubusercontent.com`.

What this does **not** protect against: a compromised Fedora base image, a
compromised GitHub Actions runner, a compromised cosign/Sigstore dependency, or
a malicious commit that a maintainer merges. See [SECURITY.md](../SECURITY.md)
for the boundary and the reporting process.

## Deliberate non-goals

These are design decisions, not backlog items:

1. **A custom installer ISO in v0.1–v0.2.** `bootc switch` on an existing Fedora
   Atomic system is the supported install path. `bootc-image-builder`-produced
   ISOs are v0.3, because an ISO pipeline doubles the test surface before the
   image pipeline is boring.
2. **A package manager that mutates the live root.** `rpm-ostree install` layers
   are a user escape hatch on the installed system, not a Wrainrock feature. The
   image is the unit of change.
3. **Forking Fedora packages or the kernel in v0.1.** There is nothing Wrainrock
   can meaningfully test about a forked glibc or kernel yet. Build-time patches,
   when they arrive, must assert a single match and be recorded in `PATCHES.md`.
4. **KDE/XFCE/other spins.** One variant until one variant is reliable.
5. **TLS / disk encryption / installer UX.** Handled by Fedora/Anaconda/bootc;
   reimplementing it is how distributions die.
6. **Automatic updates by default.** See above.
7. **Rootless container security as a tenant boundary.** bootc images run
   system-level services; rootless podman is a convenience, not a security
   boundary. Documented in SECURITY.md rather than pretended otherwise.

## Failure modes that are not automatically recoverable

- **Registry outage during `bootc update`:** the running system is unaffected;
  retry later. Rollback remains available offline.
- **Disk full during staging:** `bootc` fails the update and leaves the current
  deployment; free space and retry. There is no auto-cleanup that deletes
  deployments behind the user's back.
- **Corrupted base image or interrupted push:** an interrupted push can leave a
  partially uploaded tag in some registries. The immutable tag is only trusted
  after `cosign verify` succeeds; if verification fails, do not boot it.
- **Bad kernel/firmware in a Fedora base:** `bootc rollback` to `previous` or to
  the prior deployment. If the system cannot boot at all, use the Fedora
  Atomic rollback entry in the bootloader.
