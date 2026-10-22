# Wraindrock

A personal, out-of-the-box remix of **Bluefin DX**, delivered as a bootc system
image. Not an independent distribution and not a Fedora derivative: the desktop,
kernel, drivers, uBlue tooling and update plumbing are upstream; this repository
owns the identity, the presentation and a short list of personal defaults.

[![build](https://github.com/Wraindrock/wraindrock-linux/actions/workflows/build.yml/badge.svg)](https://github.com/Wraindrock/wraindrock-linux/actions/workflows/build.yml)

## What differs from Bluefin DX

- `NAME` and `PRETTY_NAME` say **Wraindrock**; `ID`, `ID_LIKE`, `CPE_NAME` and
  the version fields stay upstream's so uBlue tooling keeps working.
- A 4K dark wallpaper replaces upstream's. Everything else visual — the logo,
  GDM artwork, boot splash and boot-menu theme — is Bluefin's own.
- The UEFI boot entry is labelled **Wraindrock** (not Fedora or Bluefin).
- GNOME application folders group launchers by purpose: Accessories (附件) for
  GNOME's own desktop apps, Utilities (工具) for Bluefin's tools, plus
  Wraindrock, Virtualization, Proxies, uBlue and Bluefin's other folders. Each
  app appears in exactly one folder.
- The dock starts as Helium, Rnote, Files, Bazaar, Mission Center, Terminal.
- A fresh install seeds the hostname to `wraindrock`.
- **NVIDIA open drivers**, QEMU/KVM with virt-manager, libvirt, Incus, Docker
  and Distrobox come from the Bluefin DX NVIDIA base.

Everything else matches Bluefin DX package for package, except the four
software packages listed below. `/usr/share/wraindrock/delta.json` records every
difference, and CI fails the build if the image carries anything that is not in
that manifest.

## Bluefin defaults we keep

The desktop is upstream Bluefin's, so its defaults are inherited rather than
re-implemented — and the parity test compares the base and the image so they
cannot drift apart silently.

- 13 GNOME extensions are installed in `/usr/share/gnome-shell/extensions`;
  8 are enabled by default: AppIndicator support, Bazaar integration,
  Blur my Shell, Dash to Dock, Gradia integration, GSConnect, Logo Menu and
  Search Light. The other five (`apps-menu`, `caffeine`, `places-menu`,
  `window-list`, `launch-new-instance`) stay installed but off, exactly as
  upstream ships them.
- Extension Manager (`com.mattjakeman.ExtensionManager`) is installed on first
  boot and wired into Logo Menu.
- Flatpak defaults are Bluefin's: the Flathub remote, the first-boot app set,
  the Bazaar `host-etc` preset, and `flatpak-preinstall.service`.
- **IBus** is the input-method framework, exactly as in GNOME and Bluefin — we
  install nothing and switch nothing. Our only input change is preloading the
  `libpinyin` engine in the source list (and `show-all-sources`), so Chinese
  typing works on first login; the framework itself is upstream's.
- GNOME look, fonts, dock, keybindings and favourite apps come from Bluefin's
  `zz0-bluefin-modifications.gschema.override`; we only override the wallpaper
  and the input-method default.

## Software

The first boot installs **43 Flatpaks** (needs the network and a few GB); a
timer retries every ten minutes until they are in, and
`sudo systemctl start wraindrock-flatpak-preinstall.service` runs it now:
Bluefin's core and DX applications — GNOME apps, Podman Desktop, GNOME Builder,
DevToolbox, Clapgrep, Embellish, Bazaar, Flatseal, DistroShelf and the rest of
the maintained set — plus DingTalk, QQ, Open Orpheus, WeChat, Rnote and Gear
Lever. Firefox and Thunderbird are deliberately not preinstalled; both install
from Bazaar (or `flatpak install flathub org.mozilla.firefox`). The two
adw-gtk3 theme extensions and Tavern (no longer on Flathub) are skipped.

**Helium is the default browser** for links and HTML. Four programs have no
Flatpak, so their upstream RPMs are baked in at pinned versions: Helium
0.19.4.1 (from the official `imput/helium` COPR), Clash Verge Rev 2.5.8,
Rayburst 4.1.0 and sing-box (SFL) 1.14.3. Each upstream release is caught by the
daily upstream-watch workflow, which bumps the pin and publishes a new signed
image tag — the apps do not wait for a Fedora major release.

Scanning is inherited from Bluefin: `sane-airscan` and the SANE scanner
drivers are installed, so network scanners appear in Document Scanner without
extra packages.

Dell G15/G16 owners also get the
[G15 control center](https://github.com/Wraindrock/Ian-g-control-center): a
first-boot unit installs a pinned commit into `/var/opt/g15-controller` and
starts its daemon, only when the DMI model matches. Other machines skip it.

KVM (`virt-manager`, `libvirt`, `qemu-system-x86`), Incus and Docker are part of
the inherited Bluefin DX base, so virtual machines work out of the box. The
NVIDIA open driver stack (`nvidia-driver`, `kmod-nvidia`,
`nvidia-container-toolkit`) is inherited from the NVIDIA base variant as well.

Input: the keyboard layout and the input method are separate entries in the
input-source list. Bluefin's English (US) layout stays; we add the **libpinyin
input method** on top, so Super+Space switches between typing English (US) and
Chinese (pinyin). The IBus framework itself is inherited from GNOME/Bluefin —
Fcitx is not installed, and Noto Sans CJK ships in the base.

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
| System image | `ghcr.io/wraindrock/wraindrock-linux:44` | Switching an existing Bluefin DX install |

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

On an existing Bluefin DX 44 system:

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
