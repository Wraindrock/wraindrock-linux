# Wrainrock Linux

An atomic desktop Linux distribution built on **Fedora Silverblue** and delivered as a
**bootc container image**.

[![build](https://github.com/Wraindrock/wrainrock-linux/actions/workflows/build.yml/badge.svg)](https://github.com/Wraindrock/wrainrock-linux/actions/workflows/build.yml)

Wrainrock Linux is a bootable operating system image: the whole OS is an OCI
image, updated with `bootc update`, rolled back with `bootc rollback`, and
installed on top of an existing Fedora Atomic system with `bootc switch`. There
is no package manager mutation of the running root and no "partially upgraded"
state: an update either becomes the next boot entry or it does not happen.

> **Status: v0.1 — parity bootstrap.** This release is intentionally *Fedora
> Silverblue 44, unmodified*. It exists to prove the build, signing, publishing
> and test pipeline. The only difference from upstream is provenance in
> `/usr/share/wrainrock/`. Customizations arrive one reviewed step at a time
> (see [docs/roadmap.md](docs/roadmap.md)); calling this a "distribution" while
> it is still byte-for-byte upstream would be dishonest, so the version number
> says exactly what it is.

## Why

- **Atomic by construction.** Updates are image swaps. A failed update leaves
  the previous deployment bootable. There is no half-upgraded system to repair.
- **Reproducible.** Every image is built from a pinned Fedora base digest by a
  public GitHub Actions workflow, tagged immutably, and signed with Sigstore.
- **Boring to operate.** The desktop, drivers, GNOME stack and update cadence
  are Fedora's. Wrainrock only owns what it can test.
- **No surprise state.** The image ships no custom system services in v0.1. If
  the pipeline is wrong, the parity test fails before anything is published.

## Install

On a Fedora Atomic Desktop (Silverblue/Kinoite/Bluefin/Aurora, Fedora 44+):

```bash
sudo bootc switch ghcr.io/wraindrock/wrainrock-linux:44
sudo systemctl reboot
```

Full preflight checks, verification and the way back are in
[docs/install.md](docs/install.md). Read [docs/rollback.md](docs/rollback.md)
*before* you switch — knowing the escape hatch in advance is the point.

## Images and tags

| Tag | Meaning | Mutable |
| --- | --- | --- |
| `44` | Fedora 44 channel; what `bootc switch ...:44` follows | yes, moves with each release |
| `latest` | Alias of the newest channel | yes |
| `previous` | The channel image that `44` pointed at before the last release | yes |
| `44.<UTC timestamp>.<run>` | Artifact of record for one build, e.g. `44.20261017T061500Z.42` | **never** |
| `44.20261017` | Not used; the immutable tag always includes the time and run number | — |

The workflow refuses to overwrite an existing immutable tag. Install the channel
tag; quote the immutable tag when you need to say exactly what you ran.

## Verify what you booted

```bash
bootc status
cat /usr/share/wrainrock/build-info.json
```

```bash
# Keyless Sigstore signature, made by this repository's workflow.
cosign verify \
  --certificate-identity-regexp '^https://github.com/Wraindrock/wrainrock-linux/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/wraindrock/wrainrock-linux:44
```

`build-info.json` records the base image **digest**, base Fedora version, git
SHA, build date, RPM count and RPM-set hash. Two builds from the same commit and
base digest produce the same RPM set.

## How the build works

```
feedstock:  quay.io/fedora/fedora-silverblue:44  (digest-pinned)
                    │
                    ▼
        Containerfile  ── build_files/build.sh ──> provenance only
                    │
                    ▼
        bootc container lint  (the image's own contract)
                    │
                    ▼
        tests/lint.sh → tests/parity.sh → tests/smoke.sh
                    │
                    ▼
   ghcr.io/wraindrock/wrainrock-linux:44.<date>.<run>  (immutable, signed)
                    │
                    ├── :44       (moving channel)
                    ├── :latest
                    └── :previous (outgoing channel image)
```

- **Pull request:** lint, build, parity and smoke tests run; nothing is pushed.
- **Push to `main`:** the same gates, then publish immutable + channel tags and
  sign the published digest keyless with cosign.
- **Nightly:** rebuilds against the freshest Fedora base so security updates
  arrive without waiting for a Wrainrock commit.

No personal access token is stored anywhere: the workflow uses the short-lived
`GITHUB_TOKEN`, and signing uses the workflow's OIDC identity.

## What CI actually asserts

| Gate | Assertion |
| --- | --- |
| `tests/lint.sh` | Shell syntax, executable bits, `image.env` consistency, required docs, workflow permissions, no credential-shaped strings |
| `tests/parity.sh` | RPM set **diff-clean** against the base; `/usr/lib/os-release` identical; bootc labels and `CMD /sbin/init` intact; `build-info.json` complete |
| `tests/smoke.sh` | The image boots under systemd (`systemctl is-system-running` = running/degraded), journald is alive |

A green build means "this is Silverblue 44 plus provenance, and it boots", not
"a human liked it".

## Develop locally

Building needs a real host with working rootless podman — a nested,
capability-less container cannot build images. On Silverblue/Bluefin:

```bash
git clone https://github.com/Wraindrock/wrainrock-linux.git
cd wrainrock-linux

just check           # fast, no container needed
just build           # podman build, tags localhost/wrainrock-linux:dev
just parity          # compare local image against the pinned base
just smoke           # boot it with systemd
```

Without `just`, use `bash tests/lint.sh` and read the `Justfile` recipes — they
are plain podman commands.

## Repository layout

```
Containerfile              image definition (FROM Silverblue, provenance, bootc lint)
image.env                  single source of truth: name, base, channel
build_files/build.sh       build-time checks and provenance
tests/lint.sh              static repository checks
tests/parity.sh            "is this still Silverblue?" diff test
tests/smoke.sh             "does it boot?" test
.github/workflows/build.yml  build, test, publish, sign
docs/architecture.md       design, invariants, tag policy, non-goals
docs/install.md            switch, preflight, verification, troubleshooting
docs/rollback.md           escape hatches, step by step
docs/roadmap.md            v0.1 → v1.0, with explicit non-goals
SECURITY.md                trust model and how to report a vulnerability
```

## Documentation

- [Architecture and invariants](docs/architecture.md)
- [Installing, verifying, troubleshooting](docs/install.md)
- [Rolling back](docs/rollback.md)
- [Roadmap](docs/roadmap.md)
- [Security model](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

## License

MIT. Fedora, Silverblue and GNOME are upstream projects with their own licenses;
Wrainrock claims no ownership over them.
