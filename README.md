# Wraindrock

A personal, out-of-the-box remix of **Universal Blue's Bluefin DX**, delivered as
a **bootc container image**.

[![build](https://github.com/Wraindrock/wraindrock-linux/actions/workflows/build.yml/badge.svg)](https://github.com/Wraindrock/wraindrock-linux/actions/workflows/build.yml)

Wraindrock is not an independent distribution and not a fork of Fedora. It is
Bluefin DX with my branding and my defaults: the GNOME desktop, the uBlue
tooling (`ujust`, Homebrew, Flatpak setup, update services), the akmods
integration and the security cadence are inherited from upstream; this
repository owns the identity, the presentation and, over time, a short list of
personal preferences.

The whole OS is an OCI image: updated with `bootc update`, rolled back with
`bootc rollback`, and either installed from the unattended ISO or switched onto
an existing Bluefin DX system. There is no package-manager mutation of the
running root and no "partially upgraded" state.

> **Status: v0.4 — rebased onto Bluefin DX.** The base feedstock is now
> `ghcr.io/ublue-os/bluefin-dx:stable` (digest-pinned at build time). The RPM set
> is still **identical to upstream**, package for package; what differs is the
> identity and presentation delta recorded in `/usr/share/wraindrock/delta.json`.
> `tests/parity.sh` fails the build if the image differs from Bluefin DX in any
> way that is not in that manifest. Personal preferences (Flatpak preinstalls,
> KVM, NVIDIA, data partitions) are the next milestones — see
> [docs/roadmap.md](docs/roadmap.md).

## What is inherited, what changes

Inherited from Bluefin DX, unchanged and always upstream: the GNOME desktop,
the kernel and firmware, drivers, the uBlue tooling, Flatpak/Brew application
management, update and rollback plumbing, and the signed upstream image digest
the build starts from.

Changed by this repository (all recorded in `delta.json`):

| Field | Bluefin DX | Wraindrock |
| --- | --- | --- |
| `NAME` | `Bluefin` | `Wraindrock Linux` |
| `PRETTY_NAME` | `Bluefin (Version: 44.YYYYMMDD)` | `Wraindrock (Version: 44.YYYYMMDD)` |
| `ID` / `ID_LIKE` | `bluefin` / `fedora` | unchanged — uBlue tooling keys off `ID=bluefin` |
| `LOGO` | `fedora-logo-icon` | `wraindrock-logo-icon` |
| `DEFAULT_HOSTNAME` | `bluefin` | `wraindrock` |
| URLs / `CPE_NAME` | upstream Bluefin | this repository / Bluefin CPE (lineage kept honest) |
| GDM logo | Fedora logo | Wraindrock wordmark |
| Wallpaper (light + dark) | Bluefin default | `wraindrock-wallpaper.png` (4K, dark blue + outlined W) |
| Boot splash | Bluefin/upstream | `wraindrock` two-step Plymouth theme |
| Boot menu (GRUB) | upstream menu | opt-in `/usr/bin/wraindrock-grub-theme` |
| Hostname on fresh installs | base default | seeded once to `wraindrock` |

`VERSION`, `VERSION_ID`, `OSTREE_VERSION` and `SUPPORT_END` stay upstream's:
the update cadence and support window are not ours to rewrite.

## Install

Two supported paths:

1. **From the ISO** — the unattended Anaconda ISO built by
   `.github/workflows/disk.yml`. It installs to the first disk without asking;
   use a scratch machine or detach data disks. See
   [docs/install.md](docs/install.md).
2. **Onto an existing Bluefin DX system** (same major release):

```bash
sudo bootc switch ghcr.io/wraindrock/wraindrock-linux:44
sudo systemctl reboot
```

Full preflight checks, verification and the way back are in
[docs/install.md](docs/install.md). Read [docs/rollback.md](docs/rollback.md)
*before* you switch — knowing the escape hatch in advance is the point.

## Images and tags

| Tag | Meaning | Mutable |
| --- | --- | --- |
| `44` | Bluefin 44 channel; what `bootc switch ...:44` follows | yes |
| `latest` | Alias of the newest channel | yes |
| `previous` | The channel image that `44` pointed at before the last release | yes |
| `44.<UTC timestamp>.<run>` | Artifact of record for one build | **never** |

The workflow refuses to overwrite an existing immutable tag. Install the channel
tag; quote the immutable tag when you need to say exactly what you ran.

## Disk images

Disk artifacts are derived from a published image and built on demand:

```bash
# Build (CI; also boots the ISO under KVM before publishing)
gh workflow run disk.yml -f image_ref=ghcr.io/wraindrock/wraindrock-linux:44

# Consume the immutable artifact set for that image version
oras pull ghcr.io/wraindrock/wraindrock-linux-disk:<version>
sha256sum -c SHA256SUMS
```

Verified artifacts are published as an immutable OCI artifact set on GHCR
(`disk.qcow2`, `install.iso`, `SHA256SUMS`). GitHub Release assets cap at 2 GiB,
so GHCR is the distribution channel. Both the ISO install test and the qcow2
boot test run under KVM in CI before the run turns green.

## Verify what you booted

```bash
bootc status
cat /usr/lib/os-release          # NAME/PRETTY_NAME are Wraindrock; ID stays bluefin
cat /usr/share/wraindrock/build-info.json
cat /usr/share/wraindrock/delta.json     # every difference from Bluefin DX
hostnamectl                             # static hostname: wraindrock
gsettings get org.gnome.desktop.background picture-uri
plymouth-set-default-theme              # wraindrock
sudo wraindrock-grub-theme status       # opt-in
```

```bash
cosign verify \
  --certificate-identity-regexp '^https://github.com/Wraindrock/wraindrock-linux/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/wraindrock/wraindrock-linux:44
```

`build-info.json` records the base image **digest**, the Bluefin version, git
SHA, build date, RPM count and RPM-set hash. `delta.json` is the machine-readable
contract the parity test enforces: os-release keys that changed, files the build
modified, and files it added.

## How the build works

```
feedstock:  ghcr.io/ublue-os/bluefin-dx:stable  (digest-pinned)
                    │
                    ▼
        Containerfile  ── build_files/build.sh ──> identity + delta.json
                    │
                    ▼
        bootc container lint
                    │
                    ▼
        tests/lint.sh → tests/parity.sh → tests/smoke.sh
                    │
                    ▼
   ghcr.io/wraindrock/wraindrock-linux:44.<date>.<run>  (immutable, signed)
                    │
                    ├── :44       (moving channel)
                    ├── :latest
                    └── :previous (outgoing channel image)
```

- **Pull request:** lint, build, parity and smoke tests run; nothing is pushed.
- **Push to `main`:** the same gates, then publish immutable + channel tags and
  sign the published digest keyless with cosign.
- **Nightly:** rebuilds against the freshest Bluefin DX base so upstream
  security updates arrive without waiting for a Wraindrock commit.

No personal access token is stored anywhere: the workflow uses the short-lived
`GITHUB_TOKEN`, and signing uses the workflow's OIDC identity.

## What CI actually asserts

| Gate | Assertion |
| --- | --- |
| `tests/lint.sh` | Shell syntax, executable bits, `image.env` consistency, required docs, workflow permissions, no credential-shaped strings |
| `tests/parity.sh` | RPM set **identical to Bluefin DX**; os-release differs only in the branded keys, with exactly the values in `delta.json`; added files match the manifest; GDM logo + wallpaper overrides compiled and resolving; Plymouth theme, config and all 30 frames present; dynamic rpm-owner check shows exactly one modified file; bootc labels and `CMD /sbin/init` intact |
| `tests/smoke.sh` | The image boots under systemd, journald is alive |
| `disk.yml` | qcow2/ISO structural checks and SHA256SUMS; ISO install and qcow2 boot under KVM |

A green build means "this is the Bluefin DX package set with exactly the
recorded delta, and it boots to a login screen" — not "a human liked it".

## Roadmap in one line

v0.4 (this rebase) → v0.5 out-of-the-box preferences → v0.6 KVM/NVIDIA from
uBlue's recipes/akmods → v0.7 dev/test data partitions → v1.0 stable remix.
Details and non-goals in [docs/roadmap.md](docs/roadmap.md).

## Repository layout

```
Containerfile              image definition (FROM Bluefin DX, provenance, bootc lint)
image.env                  single source of truth: name, base, channel
build_files/build.sh       base checks, branding, delta + build manifests
build_files/branding/      logo, GDM wordmark, wallpaper, Plymouth + GRUB themes
build_files/grub-theme/    wraindrock-grub-theme (opt-in boot-menu helper)
tests/lint.sh              static repository checks
tests/parity.sh            "still Bluefin DX, plus only the delta?" test
tests/smoke.sh             "does it boot?" test
.github/workflows/build.yml  build, test, publish, sign
.github/workflows/disk.yml   qcow2 + unattended Anaconda ISO (on demand)
disk_config/disk.toml      qcow2 root filesystem size
docs/architecture.md       design, invariants, tag policy, non-goals
docs/install.md            switch/ISO install, preflight, verification, troubleshooting
docs/rollback.md           escape hatches, step by step
docs/roadmap.md            v0.1 → v1.0, with explicit non-goals
SECURITY.md                trust model and how to report a vulnerability
```

## License and upstream

MIT for this repository's own files. Bluefin, Universal Blue, Fedora, GNOME and
every inherited component remain their upstream projects' work under their own
licenses; Wraindrock claims no ownership over them and redistributes them
unmodified except for the recorded delta.
