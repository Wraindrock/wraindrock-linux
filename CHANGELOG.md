# Changelog

All notable changes to Wraindrock are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
image versions are the upstream channel plus an immutable build tag, see
[docs/architecture.md](docs/architecture.md).

## [0.20.3] - 2026-10-23

### Fixed

- Remove the stock Silverblue `firefox`, `firefox-langpacks` and `gnome-software`
  packages (plus the Fedora browser config and background-logo extension), so a
  fresh install shows Bazaar and Helium rather than Firefox and GNOME Software.
- Fix the Flatpak preinstall wrapper's app list: it parsed `Branch=`/`IsRuntime=`
  lines as app IDs, so it never considered the set complete.

## [0.20.2] - 2026-10-23

### Added

- Full HPLIP: `hplip-gui` (with `hp-toolbox`) and its Qt5/ReportLab closure,
  selected to match the inherited HPLIP core version.
- TuxTalk 0.17.0-1 (offline voice dictation), pinned from its upstream RPM.
- The Logo Menu GNOME extension is now the official upstream build (v25.2,
  shell 49/50/51) instead of Bluefin's repackaged v38.

## [0.20.1] - 2026-10-23

### Added

- `ipp-duplexd` 0.1.3-1 (manual duplex printing via a virtual IPP printer),
  installed from its pinned upstream Debian package because upstream ships no
  RPM. `qpdf` is installed as its runtime dependency; users run
  `ipp-duplexd-setup` once to configure the real printer.

## [0.20.0] - 2026-10-23

### Changed

- Rebased from `ghcr.io/ublue-os/bluefin-dx-nvidia-open:stable` onto
  `ghcr.io/ublue-os/silverblue-main:44`. The NVIDIA driver and kernel module are
  staged from the matching `akmods-nvidia-open:main-44-<kernel>` build; Docker,
  Incus, libvirt/QEMU, virt-manager and Distrobox are installed from Fedora and
  Docker repositories, and `nvidia-container-toolkit` comes from uBlue's addons.
- Restored the Bluefin DX desktop layer on the lean base: nine GNOME extensions
  with their dconf presets, the seven Bluefin application folders, the Flathub
  remote and the Bazaar `host-etc` preset.
- The wallpaper and all other visual branding are left at stock Silverblue; only
  the dock, folders, input default and UEFI name are curated.
- Base identity is now `ID=fedora`/`VARIANT_ID=silverblue`; `CPE_NAME` names
  Fedora, and the image adds 197 packages to the 1,632-package base.

## [0.19.0] - 2026-10-23

### Added

- A Social (社交) application folder groups WeChat, QQ and DingTalk, with its
  own `wraindrock-social.directory` so the name follows the system language.

### Removed

- The optional HPLIP Qt GUI again: `hplip-gui` and its Qt5/ReportLab closure are
  no longer pinned. Bluefin's HPLIP core (CUPS/SANE backends, `hp-setup`) stays
  inherited and asserted; the toolbox is not needed on this machine.

## [0.18.4] - 2026-10-23

### Added

- Full HPLIP: the pinned `hplip-gui` 3.26.6-1 package and its Qt5/ReportLab
  dependencies join Bluefin's inherited HPLIP core, adding `hp-toolbox` and the
  printer/scanner GUI utilities without upgrading `hplip` itself.

### Changed

- `hplip-gui` has one pin per matching `hplip` core version (3.26.6-1 and
  -2); the build selects the row whose condition matches the inherited core.
- The build records its verified pins at `/usr/share/wraindrock/rpm-pins`, and
  parity compares that list with the packages rpm actually installed, so pin
  bumps no longer need edits to the parity script. The build asserts the
  inherited `hplip`, `hplip-common`, `hplip-libs`, `libsane-hpaio` stack,
  `hp-setup`, the GUI toolbox, the HP CUPS backend and the SANE backend.

## [0.18.3] - 2026-10-22

### Fixed

- The Flatpak retry wrapper now checks that every declared app is actually
  installed before recording completion. Previously, if Bluefin's own
  `flatpak-preinstall.service` was still running when the timer fired, the
  wrapper recorded the new preinstall hash early and the newly added apps could
  stay missing until the next image change.

### Added

- Assert the scanner stack inherited from Bluefin: `sane-airscan` and
  `sane-backends-drivers-scanners` must be present in every build.

## [0.18.2] - 2026-10-22

### Changed

- Removed Thunderbird from the first-boot Flatpaks; it installs from Bazaar
  when wanted.
- Added DingTalk, QQ and Open Orpheus to the preinstalled Flatpaks (43 total).

### Added

- Dell G15/G16 control center: a hardware-gated first-boot unit installs a
  pinned commit of `Wraindrock/Ian-g-control-center` (tarball verified by
  sha256) into `/var/opt/g15-controller`, because the upstream installer builds
  a venv and starts a daemon at runtime rather than shipping an RPM.

## [0.18.1] - 2026-10-22

### Fixed

- ISO and qcow2 installs now track the moving `:44` channel. The disk workflow
  verifies that the channel tag resolves to the image it was asked to build,
  hands bootc-image-builder the channel reference, and rewrites the kickstarts'
  `bootc switch` line to the channel with the build digest as an offline
  fallback. Previously an install recorded the immutable build tag, so
  `bootc update` could never move past that build.

## [0.18.0] - 2026-10-22

### Changed

- Split Accessories (附件) from Utilities (工具). GNOME's desktop applications
  now live in their own `Accessories` folder with a custom
  `wraindrock-accessories.directory` (`Name[zh_CN]=附件`); Bluefin's Utilities
  folder keeps its own tools and excludes the GNOME apps, so the two folders no
  longer overlap.

## [0.17.2] - 2026-10-22

### Fixed

- A fresh install could finish without its Flatpaks (including Bazaar): Bluefin's
  `flatpak-preinstall.service` stops after three attempts, which happen before
  Wi-Fi is configured in GNOME Initial Setup. A new
  `wraindrock-flatpak-preinstall.timer` retries the install every ten minutes
  until the preinstall file's hash is recorded in
  `/var/lib/wraindrock/flatpak-preinstall.sha256`; the wrapper is a no-op once
  the declared set is complete.

## [0.17.1] - 2026-10-22

### Changed

- Every GNOME desktop application is now filed under Utilities (附件): Files,
  Terminal, Settings, Disks, System Monitor, Tour, Tweaks, Orca, and the GNOME
  Flathub apps (Calculator, Calendar, Papers, Loupe, Showtime, Text Editor,
  Weather, Maps, Clocks, Fonts, Baobab, Connections, Contacts, DejaDup, File
  Roller, Firmware, Logs, Simple Scan, Snapshot, Decibels). The desktop ids were
  verified against the base rpmdb and Flathub appstream on 2026-10-22 and are
  pinned in `tests/fixtures/gnome-desktop-apps.txt`.

## [0.17.0] - 2026-10-22

### Changed

- The dock defaults to Helium, Rnote, Files, Bazaar, Mission Center and Terminal,
  in that order.
- A `uBlue` folder holds Community, Documentation and System Update. Community
  and Documentation are Bluefin's link launchers; "System Update" is Bluefin's
  `ujust update` app (the request said "Steam update"; Bluefin ships no Steam
  Update launcher, so the system-update entry is what was meant).

## [0.16.1] - 2026-10-21

### Fixed

- Apps no longer appear in several GNOME folders at once. GNOME matches
  `(apps ∪ categories) − excluded-apps` per folder, and the previous `Flatpak`,
  `AppImage` and `Bluefin` folders overlapped Bluefin's Utilities, Development
  and Containers folders. The channel folders are gone; the drop-in now only
  adds Virtualization, Proxies and Wraindrock with explicit apps lists, and
  excludes the re-homed apps from every upstream folder. `tests/folders.py`
  merges both definitions and fails when an app would get two homes.

## [0.16.0] - 2026-10-21

### Changed

- `build.yml` is split into a `changes` classifier, an always-on `lint` job and
  the `build` job. Pushes that only touch `docs/`, `README.md`, `CHANGELOG.md`,
  `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE`, dotfiles, `tools/` or `tests/`
  are linted but not built or published: those files never enter the image, so
  rebuilding only changed `build-info.json` and made clients download the full
  build layer. Any unknown path, nightly run and manual dispatch still build.
- `:44` can therefore lag `main` by documentation commits; `build-info.json`
  remains the record of the commit an image was built from.

## [0.15.1] - 2026-10-20

### Fixed

- `tools/get-live-iso.sh` now resumes interrupted downloads: each release part
  is fetched with `curl --continue-at -` and `--retry-all-errors`, retried with
  backoff, and falls back to HTTP/1.1 when a CDN resets the TLS connection.
  Completed parts are verified against the release `SHA256SUMS` before reuse, so
  re-running the documented one-liner continues from the last partial part
  instead of starting over.

## [0.15.0] - 2026-10-20

### Changed

- Removed every visual customisation except the wallpaper: the logo icon, the
  GDM wordmark, the Plymouth boot splash and the opt-in GRUB theme are gone.
  Bluefin's own presentation is better and stays upstream's. The wallpaper
  remains so deployments are still easy to tell apart.
- `/etc/system-release` is branded `Wraindrock release <ver> (Bluefin DX)`.
  bootupd derives the UEFI firmware entry label from that file, so installs and
  bootloader updates now name the boot entry **Wraindrock** instead of Fedora.
- GNOME application folders are declared in
  `/etc/dconf/db/distro.d/10-wraindrock-folders`: Virtualization, Proxies,
  Bluefin, Wraindrock, Flatpak and AppImage, layered on top of Bluefin's
  existing folders. The Flatpak folder is generated from `flatpaks.txt`.

### Removed

- `build_files/branding/plymouth/`, `build_files/branding/grub/`,
  `build_files/grub-theme/`, the logo/GDM assets, the Plymouth theme and its
  `/etc/plymouth/plymouthd.conf`, and the GRUB theme helper. `delta.json` no
  longer lists them, and parity asserts they never reappear.

## [0.14.1] - 2026-10-20

### Documentation

- README gained an explicit **Download** section: the GitHub Release assets,
  their sizes, the self-extracting script (Linux/macOS/WSL) and the Windows
  `copy /b` route, plus the equivalent `oras pull` from GHCR.
- `docs/install.md` now spells out both download paths and the checksum step.
- New `docs/releases.md` inventories the published image tags, every disk
  artifact tag (including the pre-rename `install.iso` builds) and the GitHub
  Releases, with verification commands.

## [0.14.0] - 2026-10-20

### Added

- The live ISO is now named `Wraindrock-Live.iso` (Fedora-style), not
  `install.iso`, throughout the disk workflow and documentation.
- `tools/release-iso.sh` builds a deterministic split archive (1.85 GiB parts,
  under GitHub's 2 GiB limit) plus a self-extracting `-extract.sh` that
  verifies every part, joins them, unpacks the ISO and re-checks its sha256.
- `.github/workflows/release-iso.yml` publishes that archive as a GitHub
  Release from a CI runner (the home uplink is far too slow for 6.7 GiB), and
  fails if the release is left as a draft.
- Release `44.20261019T132911Z.55` carries `Wraindrock-Live.iso`
  (`sha256:84039f3b…`) in four parts plus the extractor and `SHA256SUMS`.

### Changed

- v0.7 (C/D dev/test data partitions) is explicitly deferred for stability.
- Documentation sweep: removed the obsolete pre-rebase local ISOs and corrected
  the remaining "nine Flatpaks" verification hint to 41.

## [0.13.2] - 2026-10-19

### Fixed

- Documentation distinguishes keyboard layouts from input methods: the English
  (US) layout is inherited, and the only addition is the `libpinyin` IBus input
  method next to it. Super+Space switches between the layout and the input
  method, not between two layouts.

## [0.13.1] - 2026-10-19

### Fixed

- Documentation no longer claims IBus as our choice: GNOME and Bluefin already
  default to the IBus framework. The image only preloads the `libpinyin`
  engine (and `show-all-sources`) in the inherited framework; no input-method
  stack is installed or replaced.

## [0.13.0] - 2026-10-19

### Changed

- Bluefin's desktop defaults are inherited explicitly instead of being left
  implicit: the 13 upstream GNOME extensions and Bluefin's 8-enabled/5-off
  split, Extension Manager, the Flathub remote, the Bazaar `host-etc` Flatpak
  preset and the `flatpak-preinstall.service` enablement. Parity compares the
  base and the image (extension set and enabled list) so upstream changes flow
  through and still cannot drift.

## [0.12.0] - 2026-10-19

### Changed

- Base rebased to `ghcr.io/ublue-os/bluefin-dx-nvidia-open:stable`, so the
  NVIDIA open driver stack (nvidia-driver, kmod-nvidia,
  nvidia-container-toolkit) and the virtualisation stack (QEMU/KVM, libvirt,
  virt-manager, Incus, Docker, Distrobox) are inherited and asserted at build
  time.

### Added

- The first boot now installs 41 Flatpaks: Bluefin's full core and DX set (minus
  Firefox, the unavailable Tavern and the two theme extensions) plus WeChat,
  Rnote and Gear Lever. The declaration lives in
  `build_files/software/flatpaks.txt`; the preinstall file is generated from it.

## [0.11.0] - 2026-10-19

### Added

- IBus with the libpinyin engine is the system default input method, declared
  through `zzzz-wraindrock.gschema.override`; no Fcitx is installed and the
  Noto CJK fonts come from the base. A user's own input-sources setting wins.

## [0.10.0] - 2026-10-18

### Changed

- Helium Browser replaces Zen Browser as the default browser. It is installed
  at build time as a pinned RPM from Helium's official Fedora COPR
  (`imput/helium`, package `helium-bin` 0.19.4.1), so `/etc/xdg/mimeapps.list`
  now points at `helium.desktop`; Firefox stays installed and selectable.
- The Flatpak preinstall list drops Zen Browser and now declares nine apps.
- RPM pins moved out of `build_files/build.sh` into
  `build_files/software/rpms.tsv` (name, version-release, URL, sha256), so a
  workflow can refresh them without touching the build script.

### Added

- `.github/workflows/upstream-watch.yml` checks Helium (COPR), Clash Verge Rev,
  Rayburst and SagerNet/sing-box daily; when an upstream release lands it
  recomputes the sha256, updates `rpms.tsv`, commits, and dispatches a build.
  Every app release therefore becomes its own signed immutable image tag
  instead of waiting for a Fedora major release.

## [0.9.0] - 2026-10-18

### Added

- First-boot software: `/usr/share/flatpak/preinstall.d/wraindrock.preinstall`
  declares ten Flatpaks (Bluefin DX's Podman Desktop, GNOME Builder, DevToolbox,
  Clapgrep, Embellish and Tavern, plus Zen Browser, WeChat, Rnote and Gear
  Lever) and is consumed by Bluefin's `flatpak-preinstall.service`.
- Zen Browser is the default handler for HTML and http(s) links in
  `/etc/xdg/mimeapps.list`; Firefox is left installed and selectable.
- Three pinned GitHub RPMs are installed at build time after a sha256 and
  version check: Clash Verge Rev 2.5.8, Rayburst 4.0.1 and sing-box (SFL)
  1.14.3. The dependency closure already exists in the base.

### Changed

- `delta.json` moves to schema 2: it now records `rpm.added` (exactly the three
  packages), `rpm.removed` (empty) and adds the preinstall file, mimeapps list
  and base RPM set to `files.added`; `rpmdb.sqlite` becomes a listed
  modification. Parity compares the real `rpm -qa` diff against the manifest.
- The build no longer keeps the RPM database byte-identical to the base (it must
  write it); it asserts the sqlite WAL is checkpointed to 0 bytes instead and
  keeps the sidecars a read-only `/usr` needs.
- `/opt` is a real directory in the image instead of Bluefin's symlink into
  `/var`, so packages that only install under `/opt` (SFL) survive a bootc
  install. The base installs nothing else there; the directory is read-only at
  runtime and listed under `files.modified`.

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
