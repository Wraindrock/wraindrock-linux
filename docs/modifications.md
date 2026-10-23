# Everything Wraindrock changes

This is the complete inventory of the delta between **Wraindrock** and its
upstream base. The machine-readable version is `/usr/share/wraindrock/delta.json`
inside every image; CI fails if the image carries anything it does not declare.

## Base

- Base image: `ghcr.io/ublue-os/silverblue-main:44`
- Base digest: `sha256:aa8751e2268e322e49869cedec47f9cb73d506f086dd24b3d4d95b2505faa3bb`
- Current image: `44.20261023T110546Z.115` (`sha256:4d74a88b6b39bcd6d176db3895b82495fc6f64d81516975948c73cc699ad2e6c`)

## Identity

`/usr/lib/os-release` is rewritten in place (all other keys stay upstream):

| Key | Value |
| --- | --- |
| `NAME` | `Wraindrock` |
| `PRETTY_NAME` | `Wraindrock 44.20261023.0 (Silverblue)` |
| `DEFAULT_HOSTNAME` | `wraindrock` |
| `HOME_URL` | `https://github.com/Wraindrock/wraindrock-linux` |
| `DOCUMENTATION_URL` | repository docs |
| `SUPPORT_URL` / `BUG_REPORT_URL` | repository issues |

`ID`, `ID_LIKE`, `CPE_NAME`, `VERSION_ID`, `VARIANT_ID` and `OSTREE_VERSION` keep
their upstream values (`ID=fedora`, `VARIANT_ID=silverblue`) so Fedora and uBlue
tooling keep working. `/etc/system-release` is rewritten to `Wraindrock release
44 (Silverblue)` so bootupd names the UEFI entry **Wraindrock**.

## Desktop defaults

- One 3840x2160 dark wallpaper at `/usr/share/backgrounds/wraindrock/`; day and
  dark picture URIs point at it. No other artwork is replaced.
- Default dock, in order: Helium, Rnote, Files, Bazaar, Mission Center, Terminal.
- Input sources: English (US) keyboard layout plus the `libpinyin` input method on
  the inherited IBus framework.
- App folders (13): `Games`, `GamingUtilities`, `Accessories`, `Utilities`, `Development`, `Containers`, `Wine`, `Productivity`, `Virtualization`, `Proxies`, `Social`, `Wraindrock`, `uBlue`.
  - `Accessories`: `org.gnome.Nautilus.desktop`, `org.gnome.Ptyxis.desktop`, `org.gnome.Settings.desktop`, `org.gnome.DiskUtility.desktop`, `org.gnome.SystemMonitor.desktop`, `org.gnome.Tour.desktop`, `org.gnome.tweaks.desktop`, `orca.desktop`, `org.gnome.Calculator.desktop`, `org.gnome.Calendar.desktop`, `org.gnome.Characters.desktop`, `org.gnome.Connections.desktop`, `org.gnome.Contacts.desktop`, `org.gnome.DejaDup.desktop`, `org.gnome.FileRoller.desktop`, `org.gnome.Firmware.desktop`, `org.gnome.Logs.desktop`, `org.gnome.Loupe.desktop`, `org.gnome.Maps.desktop`, `org.gnome.Papers.desktop`, `org.gnome.Showtime.desktop`, `org.gnome.SimpleScan.desktop`, `org.gnome.Snapshot.desktop`, `org.gnome.Decibels.desktop`, `org.gnome.TextEditor.desktop`, `org.gnome.Weather.desktop`, `org.gnome.baobab.desktop`, `org.gnome.clocks.desktop`, `org.gnome.font-viewer.desktop`
  - `Virtualization`: `virt-manager.desktop`, `io.podman_desktop.PodmanDesktop.desktop`
  - `Proxies`: `Clash Verge.desktop`, `sing-box.desktop`
  - `Social`: `com.tencent.WeChat.desktop`, `com.qq.QQ.desktop`, `com.dingtalk.DingTalk.desktop`
  - `Wraindrock`: `helium.desktop`, `Rayburst.desktop`
  - `uBlue`: `discourse.desktop`, `documentation.desktop`, `system-update.desktop`
- Nine GNOME extensions are vendored under `/usr/share/gnome-shell/extensions`
  (AppIndicator, Bazaar integration, Blur my Shell, Caffeine, Dash to Dock, Gradia
  integration, GSConnect, Logo Menu, Search Light); the Bluefin DX enabled set is
  enabled by default, and the four dconf presets configure keybindings, Logo Menu,
  Search Light and Blur my Shell.

## First boot

- Hostname seed: a oneshot unit sets `/etc/hostname` to `wraindrock` when it is
  absent or still `fedora`, then never touches it again (marker in `/var/lib/wraindrock`).
- Flatpak preinstall: 43 apps are declared in
  `/usr/share/flatpak/preinstall.d/wraindrock.preinstall`; a wrapper plus a ten-minute
  timer retries `flatpak preinstall` until the network is up and every app is present.
- Dell G15/G16 only: a first-boot unit installs the pinned Ian-g-control-center commit
  into `/var/opt/g15-controller` and starts its daemon.

## Software

The first boot installs 43 Flatpaks from Flathub: `be.alexandervanhee.gradia`, `com.github.PintaProject.Pinta`, `com.github.tchx84.Flatseal`, `com.mattjakeman.ExtensionManager`, `com.ranfdev.DistroShelf`, `io.github.flattool.Ignition`, `io.github.kolunmi.Bazaar`, `io.gitlab.adhami3310.Impression`, `io.missioncenter.MissionCenter`, `org.gnome.Calculator`, `org.gnome.Calendar`, `org.gnome.Characters`, `org.gnome.Connections`, `org.gnome.Contacts`, `org.gnome.DejaDup`, `org.gnome.FileRoller`, `org.gnome.Firmware`, `org.gnome.Logs`, `org.gnome.Loupe`, `org.gnome.Maps`, `org.gnome.NautilusPreviewer`, `org.gnome.Papers`, `org.gnome.Showtime`, `org.gnome.SimpleScan`, `org.gnome.Snapshot`, `org.gnome.Decibels`, `org.gnome.TextEditor`, `org.gnome.Weather`, `org.gnome.baobab`, `org.gnome.clocks`, `org.gnome.font-viewer`, `page.tesk.Refine`, `de.leopoldluley.Clapgrep`, `io.github.getnf.embellish`, `io.podman_desktop.PodmanDesktop`, `me.iepure.devtoolbox`, `org.gnome.Builder`, `com.tencent.WeChat`, `com.github.flxzt.rnote`, `it.mijorus.gearlever`, `com.dingtalk.DingTalk`, `com.qq.QQ`, `io.github.yucling.open-orpheus`.

Four RPMs without a Flatpak are baked at pinned versions: `helium-bin 0.20.1.1-1.fc44`, `clash-verge 2.5.8-1`, `rayburst 4.1.0-1`, `sing-box 1.14.3-1`.

Restored on top of the lean base (197 added packages in total):

- NVIDIA open driver stack: `kmod-nvidia`, `nvidia-driver` and userland,
  `nvidia-container-toolkit`, staged from `ublue-os/akmods-nvidia-open:main-44-<kernel>`.
- Docker: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`,
  `docker-compose-plugin`.
- Incus: `incus`, `incus-client`.
- Virtualisation: the libvirt stack, `qemu-system-x86-core`, `qemu-img`,
  `virt-manager`, `virt-install`, `distrobox`.
- Runtime dependencies the pinned apps need (for example `libayatana-appindicator-gtk3`,
  `libXScrnSaver`, `webkit2gtk4.1`) and their transitive Fedora packages.
- Flathub is added as a system remote, plus the Bazaar `host-etc` Flatpak preset.

The complete, exact package list is in `delta.json` (`rpm.added`); the base is
1,632 packages and the image is 1,829.

## Files

Modified (6): `/usr/lib/os-release`, `/etc/system-release`,
`/usr/share/glib-2.0/schemas/gschemas.compiled`, `/usr/share/rpm/rpmdb.sqlite`,
`/etc/dconf/db/distro`, `/opt` (bluefin used a symlink into `/var`; the image needs a
real directory so `/opt` payloads survive).

Added (38):

- `/usr/share/glib-2.0/schemas/zzzz-wraindrock.gschema.override`
- `/usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png`
- `/usr/libexec/wraindrock-hostname-seed`
- `/usr/lib/systemd/system/wraindrock-hostname-seed.service`
- `/usr/lib/systemd/system/sysinit.target.wants/wraindrock-hostname-seed.service`
- `/usr/share/wraindrock/base-os-release`
- `/usr/share/wraindrock/base-rpm-set`
- `/usr/share/wraindrock/rpm-pins`
- `/usr/share/wraindrock/build-info.json`
- `/usr/share/wraindrock/delta.json`
- `/usr/share/flatpak/preinstall.d/wraindrock.preinstall`
- `/usr/libexec/wraindrock-flatpak-preinstall`
- `/usr/lib/systemd/system/wraindrock-flatpak-preinstall.service`
- `/usr/lib/systemd/system/wraindrock-flatpak-preinstall.timer`
- `/etc/systemd/system/timers.target.wants/wraindrock-flatpak-preinstall.timer`
- `/usr/libexec/wraindrock-g15-install`
- `/usr/lib/systemd/system/wraindrock-g15-install.service`
- `/etc/systemd/system/multi-user.target.wants/wraindrock-g15-install.service`
- `/etc/xdg/mimeapps.list`
- `/etc/dconf/db/distro.d/10-wraindrock-folders`
- `/usr/share/desktop-directories/wraindrock-accessories.directory`
- `/usr/share/desktop-directories/wraindrock-social.directory`
- `/etc/dconf/db/distro.d/20-wraindrock-keybindings`
- `/etc/dconf/db/distro.d/21-wraindrock-logomenu`
- `/etc/dconf/db/distro.d/22-wraindrock-searchlight`
- `/etc/dconf/db/distro.d/23-wraindrock-blur`
- `/usr/share/ublue-os/flatpak-overrides/io.github.kolunmi.Bazaar`
- `/usr/lib/tmpfiles.d/bazaar-flatpak.conf`
- `/etc/flatpak/remotes.d/flathub.flatpakrepo`
- `/usr/share/gnome-shell/extensions/appindicatorsupport@rgcjonas.gmail.com`
- `/usr/share/gnome-shell/extensions/bazaar-integration@kolunmi.github.io`
- `/usr/share/gnome-shell/extensions/blur-my-shell@aunetx`
- `/usr/share/gnome-shell/extensions/caffeine@patapon.info`
- `/usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com`
- `/usr/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io`
- `/usr/share/gnome-shell/extensions/gsconnect@andyholmes.github.io`
- `/usr/share/gnome-shell/extensions/logomenu@aryan_k`
- `/usr/share/gnome-shell/extensions/search-light@icedman.github.com`

## Install media and build

- The ISO has two boot entries: interactive Anaconda (default) and an explicit
  "erase first disk" unattended install. Installed systems follow the moving `:44`
  channel tag, so `bootc update` keeps working.
- Disk artifacts are immutable OCI artifacts on GHCR; the release workflow splits
  the ISO into under-2-GiB parts with a self-extracting script and `SHA256SUMS`.
- Every push lints; image builds run when a changed path can affect the image, and
  parity compares the base and image RPM sets, files, identity, NVIDIA stack, DX
  stack, extensions, folders and the Flatpak set.

## Not changed

- Kernel, firmware, GDM, GNOME Shell, bootloader binaries, systemd and the update
  plumbing stay upstream; no Fedora or uBlue package is forked or replaced.
- No mutable `/usr`, no physical A/B partitions, no custom installer UI.
