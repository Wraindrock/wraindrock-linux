# Architecture

Wraindrock Linux is a **bootc system image**: an OCI container whose root
filesystem is the operating system. This document covers how the image is
produced, what is invariant about it, how releases are identified and signed,
and what the project deliberately does not do.

## Feeding from Bluefin DX

The base feedstock is Universal Blue's Bluefin DX:

```
ghcr.io/ublue-os/bluefin-dx:stable
```

Bluefin DX is itself a bootc image: a GNOME desktop with developer tooling,
uBlue's update and application plumbing, and (in `-nvidia` variants) prebuilt
kernel modules. We consume it as an OCI base layer, pin the resolved digest at
build time, and record it in the image. The identity contract the build requires
is `ID=bluefin` with `VARIANT_ID=bluefin-dx*` — the host this was developed on is
`bluefin-dx-nvidia-open`.

Wraindrock does not own the desktop, kernel, firmware or driver stack. Those
belong to Fedora and Universal Blue, and that is the point: the project is a
small, declared, tested set of personal defaults on top of a distribution that
already ships, signs and updates that stack. Maintaining a parallel OS is
explicitly not the goal.

### Why bootc and not `rpm-ostree compose`

Upstream already made this choice: Bluefin DX is a bootc image, and Fedora is
moving Atomic Desktops to container-native builds (the "Build Atomic Desktops
with Konflux" change targets Fedora 46). Building with bootc today:

- consumes exactly the artifact upstream publishes and tests;
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
                              (assert base identity, brand, write delta)
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

Everything is driven by `image.env`, so "which Bluefin stream is this?" is a
one-line, reviewable change.

### The delta invariant (v0.2+)

v0.1–v0.3 enforced "identical to Fedora Silverblue". v0.4 moves the baseline to
Bluefin DX and keeps the falsifiable part machine-checkable:

> The image's RPM set is identical to the base's. `/usr/lib/os-release` differs
> only in the identity keys listed in `/usr/share/wraindrock/delta.json`, and
> every added file is declared there.

The parity test diffs `rpm -qa`. For os-release it parses both files and allows
only the changed keys `NAME`, `PRETTY_NAME`, `LOGO`, `DEFAULT_HOSTNAME` and the
four URLs. A removed, added or changed key outside that set fails the build;
each declared value is then cross-checked against the actual file, so the
manifest cannot drift into a polite fiction. The test also proves the GDM
override is compiled into `gschemas.compiled` and that `rpm -V --nomtime` on the
package owning `/usr/lib/os-release` (looked up dynamically — Bluefin owns it,
not a Fedora identity package) reports exactly one modified file,
`/usr/lib/os-release`. (`--nomtime` is required: image layers store mtime 0 for
ostree hardlinks while rpm headers record build time, so the timestamp check
would flag every file and hide the real diff.)

Adding a customization therefore means adding it to the manifest **and**
teaching the test about it — never relaxing the diff.

The manifest also covers the files the build itself adds: the branding,
boot-splash, hostname-seeding and GRUB-helper files sit next to the three
`/usr/share/wraindrock/` provenance files in `files.added`, and parity requires
that set to match exactly. RPM is queried
from a throwaway copy of the database, so the image's rpmdb and sqlite's
`-wal`/`-shm`/`.rpm.lock` sidecars stay byte-identical to the base (the build
checks this before and after the query, and parity compares the sidecar
checksums). The build passes `--no-hostname` to `podman build`, so the image
ships no `/etc/hostname` at all (buildah's empty placeholder would otherwise
count as a configured, empty hostname).

`DEFAULT_HOSTNAME` alone is not enough on an installed system:
`bootc-image-builder`'s install path inherits the base deployment's `/etc`, so a
fresh install came up as `fedora` in the v0.3 VM test. The image therefore ships
`wraindrock-hostname-seed.service` (wired into `sysinit.target.wants`), which runs
once before login. It reads `DEFAULT_HOSTNAME` from `/usr/lib/os-release` and
replaces only an unconfigured value — empty, or the base default `bluefin` (or
`fedora`) — then writes `/var/lib/wraindrock/hostname-seeded`. A hostname chosen by the user or
installer is never overwritten, and the marker makes later boots no-ops. The
unit is exercised in parity against a fixture with a temporary root.

### Branding

The delta is identity and presentation only on purpose (identity in v0.2,
wallpaper and boot splash in v0.3):

| Change | Mechanism |
| --- | --- |
| display name, pretty name, logo, default hostname | `sed` on `/usr/lib/os-release` |
| `ID`, `ID_LIKE`, `CPE_NAME`, version fields | left at upstream values — uBlue tooling keys off `ID=bluefin`, and the CPE keeps naming Universal Blue |
| logo icon (`Settings` → `About`) | `/usr/share/icons/hicolor/scalable/apps/wraindrock-logo-icon.svg` |
| GDM login logo | `/usr/share/pixmaps/wraindrock-gdm-logo.{svg,png}` + `zzzz-wraindrock.gschema.override` |
| default desktop + GDM wallpaper | `/usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png` + `[org.gnome.desktop.background]` in `zzzz-wraindrock.gschema.override` |
| Plymouth boot splash | `/usr/share/plymouth/themes/wraindrock/` (two-step theme) + `Theme=wraindrock` in `/etc/plymouth/plymouthd.conf` |
| GRUB boot menu theme | `/usr/share/grub/themes/wraindrock/` assets + `/usr/bin/wraindrock-grub-theme`, which copies them to `/boot/grub2/themes/wraindrock/` and writes a marked `/boot/grub2/custom.cfg` (opt-in) |
| default hostname | `DEFAULT_HOSTNAME` (no `/etc/hostname` is shipped; an installer or user file still wins) |

The logo assets are generated outlines, not `<text>`: rendering does not depend
on Cantarell or any other font being present. GDM merges gschema overrides in
name order, so a `zz-` file wins over Fedora's own; Fedora's file is left
untouched. The wallpaper works the same way: Fedora's
`10_org.gnome.desktop.background.fedora.gschema.override` points at its own
day/night images, and our later-sorted `zz-` file replaces both `picture-uri` and
`picture-uri-dark` with the Wraindrock PNG. GDM's login screen reads the same
`org.gnome.desktop.background` defaults, so the greeter background follows
without a separate mechanism. Known caveat: the wordmark is black, so it has
low contrast on the dark login wallpaper; a light login-screen variant is a
follow-up, not part of this step.

The boot splash uses Plymouth's `two-step` plugin, which the base image already
ships; there is no `script.so`, so a script theme would mean a package change
and is deliberately not done. The theme is
`/usr/share/plymouth/themes/wraindrock/`: a 1920x1080 gradient background, 30
animation frames (256x256 PNGs, thin outlined `W` plus a rotating blue arc) and
`wraindrock.plymouth`. `/etc/plymouth/plymouthd.conf` selects it. When a
deployment regenerates its initramfs, plymouth's
`/usr/lib/plymouth/plymouth-populate-initrd` reads that config and copies the
theme and its plugin into the initrd. CI asserts the files, the config and that
`plymouth-set-default-theme -l` lists the theme; it cannot assert the rendered
splash or the initrd contents — verify those by rebooting after `bootc switch`.

GRUB is different: on bootc systems `/boot/grub2/grub.cfg` is a static config
that bootupd writes at install time, and image updates do not regenerate it, so
the image cannot theme an existing boot menu by itself. It ships the theme
assets plus a helper that acts only when the user runs it.
`wraindrock-grub-theme enable` copies the theme to
`/boot/grub2/themes/wraindrock/` (the boot filesystem is readable even with an
encrypted root) and writes `/boot/grub2/custom.cfg`, which bootupd's
`configs.d/41_custom.cfg` sources. The helper refuses to overwrite a
`custom.cfg` it did not write, refuses systems whose GRUB config has no
`custom.cfg` hook, and does nothing on systemd-boot hosts. The delta records the
shipped assets; the `/boot` copy is user state, not image state, and is not
listed in `delta.json`.

`gtk-update-icon-cache` is deliberately not run: the hicolor theme resolves
scalable SVGs without a cache, and skipping it avoids a generated
`icon-theme.cache` that would be one more unowned delta. `glib-compile-schemas`
*is* run, because GSettings only reads compiled schemas; that rewrites
`/usr/share/glib-2.0/schemas/gschemas.compiled`, which the delta lists under
`files.modified`.

### Provenance

`build_files/build.sh` writes three files:

- `/usr/share/wraindrock/build-info.json` — schema, image/version, build
  number, git SHA, build date, base image + digest, Bluefin version, identity
  marker, RPM count, RPM-set SHA-256.
- `/usr/share/wraindrock/delta.json` — every intended difference from the base:
  changed/added os-release keys with their actual values, modified files and
  added files. This is the manifest the parity test enforces.
- `/usr/share/wraindrock/base-os-release` — pristine copy of the base's
  `/usr/lib/os-release`, so "what was this built from?" survives even though
  the live file is now branded.

The build fails if the base is not `ID=bluefin`, `VERSION_ID=44`,
`VARIANT_ID=bluefin-dx*`, or if `/usr/bin/bootc` / `/usr/lib/bootc` are missing.
That is a single-match assertion on the base, not a comment.

## Tags and release identity

| Tag | Example | Mutability | Purpose |
| --- | --- | --- | --- |
| immutable | `44.20261017T061500Z.42` | never overwritten | artifact of record |
| channel | `44` | moves per build | what users follow |
| alias | `latest` | moves per build | newest channel |
| rollback aid | `previous` | moves per build | outgoing channel image |

Rules, enforced in CI:

1. Every build first computes the immutable tag from the Bluefin stream
   (`44`), the UTC build timestamp and the workflow run number.
2. Before pushing, CI checks the registry for that tag and **fails if it already
   exists**. Published artifacts are never replaced.
3. Only `main` publishes. Pull requests build and test but cannot touch the
   registry, so a PR cannot become someone's next `bootc update`.
4. Before moving `44`, CI tags the current `44` digest as `previous` and pushes
   it. This gives a second, registry-side rollback target in addition to the
   local `bootc rollback` deployment.
5. Channel tags are pushed only after the immutable artifact exists, so a
   broken channel push can be retried without reusing an artifact tag.

Nightly rebuilds keep the channel current with upstream security updates even when
Wraindrock's own source doesn't change. A rebuild of the same base digest and
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

- **Base:** Universal Blue's Bluefin DX image (`ghcr.io/ublue-os/bluefin-dx`),
  pulled by digest at build time and recorded in `build-info.json`. uBlue's own
  build and signing chain is trusted transitively.
- **Build:** public GitHub Actions workflow; no self-hosted runner, no long-lived
  registry credential. The only secrets are the ephemeral `GITHUB_TOKEN` and the
  OIDC token used by cosign.
- **Publish:** `ghcr.io`, immutable tags, keyless Sigstore signature whose
  certificate identity is bound to this repository's workflow.
- **Verify:** `cosign verify` with
  `--certificate-identity-regexp '^https://github.com/Wraindrock/wraindrock-linux/'`
  and issuer `https://token.actions.githubusercontent.com`.

What this does **not** protect against: a compromised Bluefin DX or Fedora base
image, a compromised GitHub Actions runner, a compromised cosign/Sigstore
dependency, or a malicious commit that a maintainer merges. See [SECURITY.md](../SECURITY.md)
for the boundary and the reporting process.

## Deliberate non-goals

These are design decisions, not backlog items:

1. **A custom installer UX before v0.3.** `bootc switch` on an existing Fedora
   Atomic system remains the upgrade path. v0.3 adds bootc-image-builder's stock
   unattended Anaconda ISO (it clears the first disk); a custom installer UX,
   partitioning UI and encryption flow stay out of scope.
2. **A package manager that mutates the live root.** `rpm-ostree install` layers
   are a user escape hatch on the installed system, not a Wraindrock feature. The
   image is the unit of change.
3. **Forking Fedora/Bluefin packages or the kernel through v0.7.** There is
   nothing Wraindrock can meaningfully test about a forked glibc or kernel yet.
   Build-time patches, when they arrive, must assert a single match and be
   recorded in `PATCHES.md`.
4. **KDE/XFCE/other spins.** One variant until one variant is reliable.
5. **TLS / disk encryption / installer UX.** Handled by Fedora/Anaconda/bootc;
   reimplementing it is how distributions die.
6. **Automatic updates by default.** See above.
7. **Rootless container security as a tenant boundary.** bootc images run
   system-level services; rootless podman is a convenience, not a security
   boundary. Documented in SECURITY.md rather than pretended otherwise.
8. **Rebranding upstream identity.** `ID`, `IMAGE_ID`, `VARIANT_ID` and
   `CPE_NAME` stay upstream's. uBlue tooling, `ujust`, update services and
   support tooling match on them; we change what a user sees, not what the
   system claims to be.
9. **A physical A/B partition layout.** ostree deployments *are* the A/B slots.
   The C/D partitions are data for development and testing, not second operating
   systems.

## Failure modes that are not automatically recoverable

- **Registry outage during `bootc update`:** the running system is unaffected;
  retry later. Rollback remains available offline.
- **Disk full during staging:** `bootc` fails the update and leaves the current
  deployment; free space and retry. There is no auto-cleanup that deletes
  deployments behind the user's back.
- **Corrupted base image or interrupted push:** an interrupted push can leave a
  partially uploaded tag in some registries. The immutable tag is only trusted
  after `cosign verify` succeeds; if verification fails, do not boot it.
- **Bad kernel/firmware in the Bluefin/Fedora base:** `bootc rollback` to `previous` or to
  the prior deployment. If the system cannot boot at all, use the Fedora
  Atomic rollback entry in the bootloader.
