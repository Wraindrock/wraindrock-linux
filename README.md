# Wraindrock

A personal, out-of-the-box remix of **uBlue Silverblue** — Universal Blue's
Fedora Silverblue base — delivered as a bootc system image. Not an independent
distribution and not a Fedora derivative: the desktop, kernel, firmware and
update plumbing are upstream, while this repository owns the identity, the
personal defaults, and the NVIDIA + developer-tool stack that Bluefin DX used to
add on top.

[![build](https://github.com/Wraindrock/wraindrock-linux/actions/workflows/build.yml/badge.svg)](https://github.com/Wraindrock/wraindrock-linux/actions/workflows/build.yml)

## What differs from uBlue Silverblue

- `NAME` and `PRETTY_NAME` say **Wraindrock**; `ID`, `ID_LIKE`, `CPE_NAME` and
  the version fields stay upstream's, so uBlue and Fedora tooling keep working.
- The Bluefin DX experience is restored on top of the lean base: the NVIDIA open
  driver and kernel module, `nvidia-container-toolkit`, Docker, Incus,
  libvirt/QEMU, virt-manager, Distrobox, the nine Bluefin GNOME extensions and
  their dconf presets, and the Bluefin application folders.
- A 4K dark wallpaper replaces upstream's. Everything else visual — logo, GDM
  artwork, boot splash and boot-menu theme — is stock Silverblue/GNOME.
- The UEFI boot entry is labelled **Wraindrock** (not Fedora).
- GNOME application folders group launchers by purpose: Accessories (附件) for
  GNOME's own desktop apps, Utilities (工具) for the tools, plus Wraindrock,
  Virtualization, Proxies, Social (社交), uBlue and the other Bluefin folders.
  Each app appears in exactly one folder.
- The dock starts as Helium, Rnote, Files, Bazaar, Mission Center, Terminal.
- A fresh install seeds the hostname to `wraindrock`.

Everything else is stock uBlue Silverblue plus the four pinned RPMs and the
Flatpak set below — 197 packages are added to the 1632-package base.
`/usr/share/wraindrock/delta.json` records every difference, and CI fails the
build if the image carries anything that is not in that manifest.

## Defaults we restore

The base is deliberately lean; the Bluefin DX defaults are reapplied by this
image, and parity compares the base and the image so the sets cannot drift
silently.

- 14 GNOME extensions are installed: the 5 Fedora ones plus AppIndicator
  support, Bazaar integration, Blur my Shell, Dash to Dock, Gradia integration,
  GSConnect, Logo Menu and Search Light. The Bluefin DX enabled set is enabled
  by default; `apps-menu`, `caffeine`, `places-menu`, `window-list` and
  `launch-new-instance` stay installed but off.
- Extension Manager (`com.mattjakeman.ExtensionManager`) is installed on first
  boot and wired into Logo Menu.
- The Flathub remote, the Bazaar `host-etc` preset, the first-boot app set and
  the retry timer are provided by this image (the base ships none of them).
- **IBus** is the input-method framework inherited from GNOME — we install
  nothing and switch nothing. Our only input change is preloading the
  `libpinyin` engine in the source list (and `show-all-sources`), so Chinese
  typing works on first login.
- Look, fonts, dock, keybindings and the default favourite apps come from this
  repository's dconf presets; we override the wallpaper and the input-method
  default as well.

## Software

The first boot installs **43 Flatpaks** (needs the network and a few GB); a
timer retries every ten minutes until they are in, and
`sudo systemctl start wraindrock-flatpak-preinstall.service` runs it now:
the maintained Bluefin set — GNOME apps, Podman Desktop, GNOME Builder,
DevToolbox, Clapgrep, Embellish, Bazaar, Flatseal, DistroShelf and more — plus
DingTalk, QQ, Open Orpheus, WeChat, Rnote and Gear Lever. Firefox and
Thunderbird are deliberately not preinstalled; both install from Bazaar (or
`flatpak install flathub org.mozilla.firefox`). The two adw-gtk3 theme
extensions and Tavern (no longer on Flathub) are skipped.

**Helium is the default browser** for links and HTML. Four programs have no
Flatpak, so their upstream RPMs are baked in at pinned versions: Helium
0.20.1.1 (from the official `imput/helium` COPR), Clash Verge Rev 2.5.8,
Rayburst 4.1.0 and sing-box (SFL) 1.14.3. Each upstream release is caught by the
daily upstream-watch workflow, which bumps the pin and publishes a new signed
image tag — the apps do not wait for a Fedora major release.

Printing and scanning are inherited from Fedora Silverblue: HPLIP 3.26.6 is
already in the base with the HP CUPS backend and filters, `hp-setup`/`hp-info`,
and the `libsane-hpaio` SANE backend; the build asserts that this stack is
present. The Qt graphical toolbox (`hplip-gui`) is intentionally not installed;
use `hp-setup -i` or the CUPS web interface. `sane-airscan` and the SANE
scanner drivers are also inherited, so network scanners appear in Document
Scanner.

Dell G15/G16 owners also get the
[G15 control center](https://github.com/Wraindrock/Ian-g-control-center): a
first-boot unit installs a pinned commit into `/var/opt/g15-controller` and
starts its daemon, only when the DMI model matches. Other machines skip it.

KVM (`virt-manager`, `libvirt`, `qemu-system-x86`), Incus, Docker and Distrobox
are installed by this image, so virtual machines work out of the box. The NVIDIA
open driver stack (`nvidia-driver`, `kmod-nvidia`,
`nvidia-container-toolkit`) is staged from uBlue's matching akmods build.

Input: the keyboard layout and the input method are separate entries in the
input-source list. The English (US) layout stays; we add the **libpinyin input
method** on top, so Super+Space switches between typing English (US) and
Chinese (pinyin). The IBus framework is GNOME's — Fcitx is not installed, and
Noto Sans CJK ships in the base.

## Screenshots

Real QEMU frames from CI runs of the published ISO.

| Boot menu | Disk layout | Manual partitioning |
| --- | --- | --- |
| ![GRUB boot menu](docs/screenshots/boot-menu.png) | ![Installation destination](docs/screenshots/installer-destination.png) | ![Manual partitioning](docs/screenshots/installer-partitioning.png) |

| GDM login | First boot |
| --- | --- |
| ![GDM login](docs/screenshots/gdm-login.png) | ![First boot](docs/screenshots/first-boot.png) |

The first menu entry installs interactively: choose the disk, the layout
(Automatic, Custom or Blivet-GUI) and the user. Language is picked at GNOME
Initial Setup on first boot. The second entry erases the first disk without
asking.

## Download

Every build publishes the same three things; pick one:

| Artifact | Where | Use when |
| --- | --- | --- |
| Split live ISO | [GitHub Releases](https://github.com/Wraindrock/wraindrock-linux/releases) | Installing from a USB stick |
| Disk OCI artifact | `ghcr.io/wraindrock/wraindrock-linux-disk:<version>` | You prefer `oras`/registry pulls (qcow2 + ISO + checksums) |
| System image | `ghcr.io/wraindrock/wraindrock-linux:44` | Switching an existing uBlue Silverblue or Bluefin DX install |

Both disk artifacts come from `.github/workflows/disk.yml`; releases are cut by
`.github/workflows/release-iso.yml` from the published ISO layer. Systems
installed from the ISO track the moving `:44` channel, so `bootc update` keeps
them current; [docs/install.md](docs/install.md) explains how to restore that
tracking if an older install pinned an immutable tag or digest.

The newest release is on the [Releases page](https://github.com/Wraindrock/wraindrock-linux/releases);
its notes list the ISO size and sha256. Each release ships the ISO split
into under-2 GiB parts, a self-extracting `-extract.sh` and `SHA256SUMS`.

### From the GitHub Release

Download the parts, `-extract.sh` and `SHA256SUMS` from the release page in a
browser, or with the helper, which always resolves the newest release (no
GitHub account needed):

```bash
curl -fsSL https://raw.githubusercontent.com/Wraindrock/wraindrock-linux/main/tools/get-live-iso.sh | bash
```

It prints the resolved version, downloads every part with `curl`, verifies them
against `SHA256SUMS`, unpacks `Wraindrock-Live.iso` and re-checks its sha256.
Pass `--out DIR` as `bash -s -- --out DIR`, or `--dry-run` to only see what it
would fetch. To read it first: `curl -fsSLO <same URL>` then `bash get-live-iso.sh`.

On Windows, join the part files in name order and open the resulting zip with
PeaZip, 7-Zip or WinRAR:

```powershell
$parts = Get-ChildItem Wraindrock-Live-*.zip.part-* | Sort-Object Name
$out = [IO.File]::Create("$PWD\Wraindrock-Live.zip")
$parts | ForEach-Object { $s = [IO.File]::OpenRead($_.FullName); $s.CopyTo($out); $s.Dispose() }
$out.Dispose()
```

### From GHCR (with `oras`)

```bash
oras pull ghcr.io/wraindrock/wraindrock-linux-disk:<version> -o disk
cd disk && sha256sum -c SHA256SUMS
```

Both routes give the same file. Verify it before writing:

```bash
sha256sum Wraindrock-Live.iso   # compare with the hash printed by the helper
```

Older immutable builds remain published, but prefer the latest release. See
[docs/releases.md](docs/releases.md) for the full inventory (image tags, disk
artifact tags, release assets).

## Install

Two supported paths.

### 1. Pull the image (ghcr.io)

On an existing uBlue Silverblue 44 (or Bluefin DX 44) system:

```bash
sudo bootc switch ghcr.io/wraindrock/wraindrock-linux:44
sudo systemctl reboot
```

The switch only adds a boot deployment; `/home`, flatpaks and containers stay
put. Read [docs/install.md](docs/install.md) for preflight checks and
[docs/rollback.md](docs/rollback.md) for the way back.

### 2. Write the ISO

Get `Wraindrock-Live.iso` from [Download](#download), verify its sha256, then
write it to a USB stick:

```bash
sudo dd if=Wraindrock-Live.iso of=/dev/sdX bs=8M status=progress oflag=direct conv=fsync
```

The boot menu offers two entries. The default, **Install Wraindrock
(interactive, choose disks)**, opens Anaconda's hub so you pick the disk,
partitioning and user account yourself; its kickstart only tells Anaconda where
the image payload is. The second, **Install Wraindrock - erase first disk
(unattended)**, clears the first disk without asking — use that one only on a
scratch machine, with data disks detached, or in a VM.

> The ISO is larger than 4 GB, so a FAT32 USB stick will not work — use an 8 GB
> or larger exFAT stick, or write it directly with `dd`.

## Verify

```bash
cat /usr/lib/os-release              # NAME="Wraindrock", ID=bluefin
cat /usr/share/wraindrock/delta.json # every intended difference
hostnamectl                          # wraindrock
flatpak list --system                # the 43 declared preinstalls
rpm -q helium-bin clash-verge rayburst sing-box # the four baked packages
cosign verify \
  --certificate-identity-regexp '^https://github.com/Wraindrock/wraindrock-linux/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/wraindrock/wraindrock-linux:44
```

## Tags

| Tag | Meaning | Mutable |
| --- | --- | --- |
| `44` | Bluefin 44 channel; what `bootc switch ...:44` follows | yes |
| `latest` | Alias of the newest channel | yes |
| `previous` | The channel image `44` pointed at before the last release | yes |
| `44.<UTC timestamp>.<run>` | Artifact of record for one build | **never** |

Install the channel tag; quote the immutable tag when you need to say exactly
which build you ran. Updates: `sudo bootc update && sudo systemctl reboot`.

## Development

`main` is built by GitHub Actions. Pushes that only touch documentation,
`tools/` or `tests/` are linted but do not publish a new image; the channel
advances on image-affecting changes and on the nightly build. Unknown paths
always build.

- Complete inventory of changes: [docs/modifications.md](docs/modifications.md)
- Design, invariants and non-goals: [docs/architecture.md](docs/architecture.md)
- Install, verification, troubleshooting: [docs/install.md](docs/install.md)
- Rollback and escape hatches: [docs/rollback.md](docs/rollback.md)
- Roadmap: [docs/roadmap.md](docs/roadmap.md)
- Published images, disk artifacts and releases: [docs/releases.md](docs/releases.md)
- Build, test and patch rules: [CONTRIBUTING.md](CONTRIBUTING.md)

## License

MIT for this repository's own files. Bluefin, Universal Blue, Fedora, GNOME and
every inherited component remain their upstream projects' work under their own
licenses.
