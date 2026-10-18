# Changelog

All notable changes to Wraindrock are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
image versions are the upstream channel plus an immutable build tag, see
[docs/architecture.md](docs/architecture.md).

## [0.8.3] - 2026-10-18

### Fixed

- The default interactive ISO entry could not actually install: without a
  kickstart Anaconda never learns where the bootc payload is and reports
  "Error setting up repositories". `tests/iso-menu.sh` now remasters the ISO
  with `/interactive.ks` (payload location plus the registry `bootc switch`),
  replaces the two visible GRUB menus, replays the El Torito/GPT boot images
  and byte-patches the menu copies embedded in the EFI images. Anaconda's hub
  now opens with the payload ready and asks for disk, partitioning and users.
- The disk workflow captures the interactive path with
  `tests/iso-interactive-shots.sh` and uploads those screenshots with the VM
  evidence.

### Changed

- Docs describe the interactive entry as a partial kickstart; language is
  picked at first boot.
- README screenshots now come from CI runs and show the interactive path: the
  boot menu, Anaconda's summary, the disk layout dialog and manual partitioning.

## [0.8.2] - 2026-10-18

### Fixed

- The installer no longer force-installs. bootc-image-builder bakes an
  unattended kickstart into the ISO, so the ISO gets a two-entry boot menu:
  **Install Wraindrock (interactive, choose disks)** (default) and **Install
  Wraindrock - erase first disk (unattended)**. Both pass a kickstart: the
  interactive one only names the bootc payload, so Anaconda's own hub still
  asks for the disk, partitioning and user account.
- The disk workflow asserts both menu entries and two kickstart entries per
  menu; the ISO VM test presses Down+Enter to select the unattended entry.

## [0.8.1] - 2026-10-18

### Changed

- The project's display name is now **Wraindrock**, not "Wraindrock Linux":
  `NAME="Wraindrock"` in os-release, and the GRUB menu title, Plymouth
  description, container title label and documentation use the shorter name.
  Image and repository identifiers (`wraindrock-linux`) are unchanged.
- README and install docs were cut back to the essentials: what the image is,
  what differs from Bluefin DX, and the two supported install paths — pull the
  GHCR image, or download the ISO. The starting-points matrix and the CI
  assertion tables no longer front-load the documentation.

## [0.8.0] - 2026-10-18

### Changed

- **Rebased the project onto Universal Blue's Bluefin DX**
  (`ghcr.io/ublue-os/bluefin-dx:stable`). Wraindrock is now a personal remix of
  Bluefin DX rather than a Fedora Silverblue derivative: the desktop, uBlue
  tooling, update plumbing and akmods integration are inherited; only identity
  and presentation are ours.
- The identity delta is reduced to `NAME`, `PRETTY_NAME`, `LOGO`,
  `DEFAULT_HOSTNAME` and the project URLs. `ID=bluefin`, `ID_LIKE=fedora`,
  `CPE_NAME`, `VERSION_ID`, `OSTREE_VERSION` and `VARIANT_ID` stay upstream's so
  uBlue tooling keeps working; the CPE continues to name Universal Blue.
- `tests/parity.sh` now compares against Bluefin DX: identical RPM set, only the
  identity keys above may differ, and the same `delta.json` manifest is
  enforced.
- Base assertions require `ID=bluefin` and `VARIANT_ID=bluefin-dx*`; the RPM
  provenance check looks up the package owning `/usr/lib/os-release` dynamically.
- Hostname seeding also replaces Bluefin's default `bluefin` on first boot.
- Documentation, install/rollback paths and security boundaries now describe
  Bluefin DX as the feedstock and stock Bluefin DX as the way back.

### Fixed

- Our gschema override is named `zzzz-wraindrock` because Bluefin ships
  `zz0-`/`zz1-` overrides that would otherwise sort after it and keep their
  wallpaper keys.
- The container smoke test boots systemd with the full capability set of its
  user namespace: journald and dbus set up mount namespaces and exit with EPERM
  without it.
- Parity accepts a `delta.json` without an `os_release.added` block (the rebase
  no longer adds `ID_LIKE`), still asserting that the added set is empty.

## [0.7.0] - 2026-10-18

### Changed

- Renamed the project from the misspelling "Wrainrock" to **Wraindrock**.
  This is the one intentional break in the image's continuity: the GitHub
  repository, GHCR image (`ghcr.io/wraindrock/wraindrock-linux`), disk
  artifact package (`ghcr.io/wraindrock/wraindrock-linux-disk`), installed
  paths (`/usr/share/wraindrock`, `/var/lib/wraindrock`,
  `/usr/libexec/wraindrock-*`, `/usr/share/plymouth/themes/wraindrock`),
  hostname, `os-release` identity, labels (`org.wraindrock.*`), and the
  wordmark all use the corrected name. Previously published `wrainrock-*`
  packages and tags are left in place as read-only history and are no longer
  updated.

## [0.6.2] - 2026-10-18

### Added

- The disk workflow publishes verified qcow2 + ISO + `SHA256SUMS` as an
  immutable OCI artifact set on GHCR
  (`ghcr.io/wraindrock/wraindrock-linux-disk:<image version>`), using a pinned
  `oras` release with a verified tarball checksum. The publish step refuses to
  overwrite an existing version tag, checks the stored manifest's layer digests
  and sizes against the local files, and proves the package is anonymously
  pullable. GitHub Release assets are not used: GitHub caps them at 2 GiB and
  both artifacts are larger.

### Fixed

- `SHA256SUMS` is computed after the VM boots, not before: the qcow2 boot test
  previously wrote into the artifact itself (machine-id, logs, SSH keys), so the
  published checksum described a different file than the one pushed. The qcow2
  test now boots a sparse copy under the evidence directory and the publish step
  re-hashes the pristine files immediately before `oras push`.

## [0.6.1] - 2026-10-17

### Added

- `wraindrock-hostname-seed.service` (with `/usr/libexec/wraindrock-hostname-seed`):
  a one-shot first-boot unit that applies `DEFAULT_HOSTNAME` on installed
  systems, where `bootc-image-builder`'s install path otherwise leaves the base
  deployment's `fedora` hostname in place. It only replaces an empty or `fedora`
  hostname, records `/var/lib/wraindrock/hostname-seeded`, and never overwrites a
  name the user or installer chose. Parity exercises the seeder against a
  fixture and checks the unit's `sysinit.target.wants` wiring.

### Fixed

- Fresh installs now report `wraindrock` as the hostname, so the qcow2 install
  test's serial prompt and `hostnamectl` agree with the image identity.

## [0.6.0] - 2026-10-17

### Added

- `.github/workflows/disk.yml`: on-demand qcow2 and unattended Anaconda ISO
  builds from a published image, using a digest-pinned
  `bootc-image-builder`. The run resolves and prints the source image version,
  revision and digest, verifies the qcow2 magic, the ISO9660 volume descriptor,
  the bootable MBR signature, `EFI/BOOT/BOOTX64.EFI` and `images/`, writes
  `SHA256SUMS`, and uploads both artifacts.
- `disk_config/disk.toml`: qcow2 root filesystem sized at 20 GiB.
- The `disk` workflow boots the ISO under QEMU/KVM (`vm_test`, default true),
  installs it to a scratch disk, boots the installed system and requires the
  GNOME welcome screen or the Wraindrock GDM wallpaper before passing. The VM
  harness (`tests/vm-test.sh`, `tests/png-stats.py`) is shared with local runs;
  qcow2 mode still asserts `gdm.service` and the `wraindrock` serial getty.

### Fixed

- The image no longer contains the builder's empty `/etc/hostname` placeholder:
  `podman build --no-hostname` keeps the file out, so a fresh install uses
  `DEFAULT_HOSTNAME` (`wraindrock`) instead of the kernel default `fedora`.
  (Parity cannot assert the absence: `podman run` injects `/etc/hostname` at
  runtime. `tests/lint.sh` asserts the `--no-hostname` build flag instead.)

### Documented

- The ISO is unattended by construction (bootc-image-builder's baked kickstart
  runs `autopart` and clears the first disk); README and install docs warn
  explicitly. Full KVM install-to-GDM verification is the remaining step.

### Changed

- README installation entry points now cover both `bootc switch` (existing
  Atomic systems) and the ISO (fresh machines).

## [0.5.0] - 2026-10-17

### Added

- GRUB boot menu theme, shipped as an opt-in helper:
  `/usr/share/grub/themes/wraindrock/` (theme.txt plus the 1920x1080 Wraindrock
  background) and `/usr/bin/wraindrock-grub-theme`. `enable` copies the theme to
  `/boot/grub2/themes/wraindrock/`, installs the GRUB font, and writes a marked
  `/boot/grub2/custom.cfg` that bootupd's static config sources; `disable`
  removes only files the helper owns; `status` reports the state. It refuses a
  foreign `custom.cfg` and systems without a `custom.cfg` hook, and it never
  edits `/boot/grub2/grub.cfg`.
- Parity checks: theme background dimensions, and a fixture-boot-tree test that
  exercises enable, idempotency, the foreign-`custom.cfg` refusal, the
  missing-hook refusal, non-interactive `disable` refusal and `disable --yes`.
- Lint checks: helper is executable and handles `custom.cfg`, `loadfont`,
  `set theme=`, `--boot-dir`; theme.txt has the expected keys; background is
  1920x1080.

### Changed

- `delta.json` `files.added` now declares the GRUB theme assets and the helper.
- Docs and roadmap: v0.3 step 3 is closed (opt-in by design); the next step is
  the installable ISO.

## [0.4.0] - 2026-10-17

### Added

- Plymouth boot splash: a `two-step` theme at
  `/usr/share/plymouth/themes/wraindrock/` (1920x1080 gradient background plus 30
  animation frames, an outlined `W` with a rotating blue arc), selected by
  `/etc/plymouth/plymouthd.conf` (`[Daemon] Theme=wraindrock`). Uses the plugin
  the base image already ships; no package changes.
- Parity checks: theme file and plugin, `ImageDir`, update progress-bar blocks,
  the daemon config, background dimensions, 30 valid 256x256 frames, and
  `plymouth-set-default-theme -l` listing `wraindrock`.
- Lint checks: Plymouth assets exist, the source SVGs are font-independent, the
  background/frame PNG headers have the expected dimensions, and the docs
  describe the splash.

### Changed

- `delta.json` `files.added` now declares the Plymouth theme, background and
  animation frames; `files.modified` now includes
  `/etc/plymouth/plymouthd.conf`.
- Docs and roadmap: v0.3 step 2 is closed; the next step is the GRUB theme,
  then the installable ISO.

## [0.3.0] - 2026-10-17

### Added

- Default wallpaper (desktop and GDM login): `wraindrock-wallpaper.svg` source
  plus a 3840x2160 PNG (dark blue gradient with a thin blue outlined `W`),
  installed at `/usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png` and
  selected for both `picture-uri` and `picture-uri-dark` through
  `zz-wraindrock.gschema.override`. Fedora's f44 day/night JXLs stay installed
  and untouched.
- Parity checks for the wallpaper: the declared file exists, the PNG is
  3840x2160 and non-trivial, both override keys point at it, the compiled schema
  cache contains it, and `gsettings get` resolves both defaults to it.
- Lint checks: the wallpaper source is font-independent, uses the Wraindrock
  blue, and the PNG header is 3840x2160.

### Changed

- `delta.json` `files.added` now includes the wallpaper, so the delta stays
  "base plus exactly the recorded difference".
- Docs and roadmap: v0.2 is closed; v0.3 is split into wallpaper → Plymouth →
  GRUB theme → installable ISO, one immutable release per step.

## [0.2.0] - 2026-10-17

### Added

- Branded identity: `NAME="Wraindrock Linux"`, `PRETTY_NAME` derived from the base
  version, `ID=wraindrock` with `ID_LIKE="fedora"`, `LOGO=wraindrock-logo-icon`,
  `DEFAULT_HOSTNAME="wraindrock"`, project URLs, and
  `CPE_NAME="cpe:/o:wraindrock:wraindrock_linux:44"`.
- Placeholder logo assets shipped as SVG **outlines** (no font dependency):
  `wraindrock-logo-icon.svg` (Settings → About) and
  `wraindrock-gdm-logo.{svg,png}` (GDM login screen).
- `zz-wraindrock.gschema.override` so the GDM login screen shows the Wraindrock
  wordmark; Fedora's own override is left untouched.
- `/usr/share/wraindrock/delta.json`: the manifest of every intended difference
  from the base — changed/added os-release keys with their actual values,
  modified files and added files.
- CI anonymous-pull check: the published digest must be pullable without
  credentials, because a freshly installed bootc host has none.

### Changed

- `tests/parity.sh` enforces "base plus exactly the recorded delta" instead of
  byte-identical os-release: the RPM set must stay identical, os-release may
  differ only in the manifest's keys (with the recorded values), and
  `rpm -V --nomtime fedora-release-identity-silverblue` must report exactly one
  modified file (the mtime check is skipped because ostree hardlinks carry mtime
  0, not the rpm header's build time).
- `tests/lint.sh` fails if `build.sh` starts changing the RPM set, and requires
  the branding assets to be font-independent outlines.
- The workflow no longer tries to flip GHCR package visibility with
  `GITHUB_TOKEN` (it lacks `packages` scope); it asserts anonymous
  pullability instead and fails with the package-settings link if the package is
  private.
- `build-info.json` gains `"identity": "wraindrock"`.
- Build provenance is now part of the declared delta: the three
  `/usr/share/wraindrock/` files are listed under `files.added`, RPM queries run
  against a throwaway copy of the database, and parity compares the rpmdb's
  sqlite sidecars (`-wal`/`-shm`/`.rpm.lock`) against the base, so the build
  cannot modify them. The builder's empty `/etc/hostname` placeholder is
  documented as inert (systemd reads it as unset).

### Notes

- `VERSION`, `VERSION_ID`, `OSTREE_VERSION` and `SUPPORT_END` stay Fedora's: the
  update cadence and support window are not rewritten yet.
- No package changes: the RPM set is identical to Fedora Silverblue 44.
- GDM background, wallpapers, Plymouth and GRUB theming move to v0.3.
- Known limit: the black wordmark has low contrast on a dark GDM background.

## [0.1.0] - 2026-10-17

### Added

- Bootc image `ghcr.io/wraindrock/wraindrock-linux`, built `FROM
  quay.io/fedora/fedora-silverblue:44` with the base digest resolved and
  recorded at build time.
- Parity invariant: the image's RPM set and `/usr/lib/os-release` are identical
  to the base; only `/usr/share/wraindrock/` is added.
- Build provenance in `/usr/share/wraindrock/build-info.json` (schema, image,
  version, build number, git SHA, build date, base image, base digest, Fedora
  version, parity marker, RPM count, RPM-set SHA-256) and a pristine
  `/usr/share/wraindrock/base-os-release`.
- `bootc container lint` runs inside the image build.
- CI gates: `tests/lint.sh`, `tests/parity.sh` (RPM + os-release diff against the
  base), `tests/smoke.sh` (the image boots under systemd).
- Publishing: immutable tags `<fedora>.<UTC timestamp>.<run>` that are never
  overwritten, moving `44`/`latest` channel tags, and a `previous` rollback tag.
- Keyless Sigstore signing of the published digest with `cosign`, verified in the
  same workflow.
- Nightly rebuild against the freshest Fedora 44 base.
- Documentation: architecture, install with preflight and troubleshooting,
  rollback, roadmap with explicit non-goals, security model, contributing guide.

### Notes

- v0.1 is intentionally unmodified Fedora Silverblue 44. It is a pipeline
  validation release; customization begins in v0.2 (`docs/roadmap.md`).
- Automatic updates are off by default.
- No installer ISO yet; install with `bootc switch` on an existing Fedora Atomic
  Desktop.
