# What Wraindrock changes on top of uBlue Silverblue

This is the complete inventory. It is the human-readable counterpart of
`/usr/share/wraindrock/delta.json`, which parity enforces against the base.

| | |
|---|---|
| Base image | `ghcr.io/ublue-os/silverblue-main:44` |
| Base digest | `sha256:aa8751e2268e322e49869cedec47f9cb73d506f086dd24b3d4d95b2505faa3bb` |
| Base packages | 1,632 (Fedora 44, kernel `7.2.11-200.fc44`) |
| Project | a personal, out-of-the-box Wraindrock system — not a Bluefin clone |

## Identity

- `/usr/lib/os-release`: `NAME="Wraindrock"`, `PRETTY_NAME="Wraindrock (Version: …)"`,
  `DEFAULT_HOSTNAME="wraindrock"`, project URLs. `ID=fedora`, `ID_LIKE` and
  `CPE_NAME="cpe:/o:fedoraproject:fedora:44"` stay upstream's so Fedora/uBlue
  tooling keeps working; `VERSION_ID` and `VARIANT_ID=silverblue` are unchanged.
- `/etc/system-release` becomes `Wraindrock release 44 (Silverblue)`, which makes
  bootupd create the UEFI boot entry **Wraindrock**.
- No wallpaper, logo, GDM artwork, Plymouth splash or GRUB theme: the stock
  Silverblue look is deliberate.

## Desktop defaults

- Dock, in order: Helium, Rnote, DistroShelf, Files, Bazaar, Mission Center, Terminal.
- Input sources: English (US) keyboard layout plus the `libpinyin` input method on
  the inherited IBus framework.
- Eight application folders, with every visible app in exactly one folder:

  - **附件** — `org.gnome.DiskUtility`, `org.gnome.Tour`, `org.gnome.ColorProfileViewer`
  - **工具** — `hplip`, `hp-uiscan`, `io.github.ronb1964.TuxTalk`, `it.mijorus.gearlever`
  - **系统** — `org.gnome.Settings`, `org.gnome.SystemMonitor`, `htop`, `nvtop`,
    `nvidia-settings`, `rygel-preferences`, `io.github.kolunmi.Bazaar`,
    `org.freedesktop.MalcontentControl`
  - **网络** — `helium`, `Rayburst`, `io.github.yucling.open-orpheus`
  - **代理** — `Clash Verge`, `sing-box`
  - **社交** — `com.tencent.WeChat`, `com.qq.QQ`, `com.dingtalk.DingTalk`
  - **办公** — `com.github.flxzt.rnote`
  - **虚拟化** — `virt-manager`, `com.ranfdev.DistroShelf`, `io.podman_desktop.PodmanDesktop`

## Removed from the base

`firefox`, `firefox-langpacks`, `gnome-software`, `fedora-bookmarks`,
`fedora-chromium-config`, `fedora-chromium-config-gnome`, `yelp`.
Firefox and Software can be reinstalled from Bazaar when wanted.

## Restored stack (the parts explicitly requested)

- NVIDIA open driver: `kmod-nvidia` + `nvidia-driver` + userland +
  `nvidia-container-toolkit`, staged from `ublue-os/akmods-nvidia-open:main-44-<kernel>`.
- Incus, Distrobox, the libvirt stack, `qemu-system-x86-core`, `qemu-img`,
  `virt-manager`, `virt-install`.
- Cockpit (`cockpit-bridge/system/machines/networkmanager/podman/storaged/selinux`).
- LXC (`lxc`, `lxc-libs`, `lxc-templates`, `lxcfs`).
- A development toolchain (gcc/clang/llvm, make/cmake/meson/ninja, autotools,
  gdb/strace, python3-devel/pip, rpm-build) and extra fonts
  (JetBrains Mono, Cascadia Code, Adwaita, Inter).
- Nine GNOME extensions (AppIndicator, Bazaar integration, Blur my Shell,
  Caffeine, Dash to Dock, Gradia integration, GSConnect, Logo Menu, Search Light)
  with the Bluefin DX enabled set; Logo Menu is the official upstream v25.2 build,
  and all extension schemas are compiled into the system schema directory.

Docker and VS Code are deliberately **not** installed.

## Software

- Nine Flatpaks are installed at build time when the container allows it:
  Bazaar, Podman Desktop, WeChat, QQ, DingTalk, Open Orpheus, Rnote, Gear Lever,
  DistroShelf. `apply_extra` apps cannot run under the build container's bwrap
  (`/proc/sys/user/max_user_namespaces` is read-only), so those fall back to the
  first-boot preinstall service, which retries every ten minutes until the network
  is up and every declared app is present.
- RPMs baked at pinned versions: Helium (official COPR), Clash Verge Rev,
  Rayburst, sing-box (SFL), TuxTalk, `hplip-gui` (matching the inherited HPLIP
  core) and its Qt5/ReportLab closure. `ipp-duplexd` (upstream .deb) is unpacked
  with its user unit. A daily watcher bumps upstream releases; every pin carries
  a sha256 and an expected version.

## First boot

- Hostname seed: sets `/etc/hostname` to `wraindrock` when absent or still
  `fedora`, then never touches it again.
- Flatpak preinstall wrapper + ten-minute timer (network-aware, self-healing).
- Dell G15/G16 only: installs the pinned Ian-g-control-center commit into
  `/var/opt/g15-controller` and starts its daemon.

## Install media and automation

- The ISO has two boot entries: interactive (default, Anaconda asks for disk
  layout) and an explicit "erase first disk (unattended)" entry.
- Installed systems track `:44`; ISOs rewrite the kickstart `bootc switch` to the
  channel with a digest fallback for offline installs.
- Images are signed keyless with cosign; disk artifacts and split self-extracting
  ISO releases are published to GHCR and GitHub Releases.

## Files

`delta.json` records the authoritative lists: 4 app RPMs added, the seven stock
packages removed, 6 modified files (`/usr/lib/os-release`, `/etc/system-release`,
`gschemas.compiled`, the RPM database, `/etc/dconf/db/distro`, `/opt`) and the
added files that implement the identity, wallpaper-free desktop, folders,
hostname seed, Flatpak retry, G15 installer, pins manifest and build provenance.
