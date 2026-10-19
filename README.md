# Wraindrock

A personal, out-of-the-box remix of **Bluefin DX**, delivered as a bootc system
image. Not an independent distribution and not a Fedora derivative: the desktop,
kernel, drivers, uBlue tooling and update plumbing are upstream; this repository
owns the identity, the presentation and a short list of personal defaults.

[![build](https://github.com/Wraindrock/wraindrock-linux/actions/workflows/build.yml/badge.svg)](https://github.com/Wraindrock/wraindrock-linux/actions/workflows/build.yml)

## What differs from Bluefin DX

- `NAME` and `PRETTY_NAME` say **Wraindrock**; `ID`, `ID_LIKE`, `CPE_NAME` and
  the version fields stay upstream's so uBlue tooling keeps working.
- The GDM logo, a 4K dark wallpaper, a Plymouth boot splash and an opt-in GRUB
  theme replace upstream's presentation.
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
  `zz0-bluefin-modifications.gschema.override`; we only override the wallpaper,
  the login logo and the input-method default.

## Software

The first boot installs **41 Flatpaks** (needs the network and a few GB):
Bluefin's core and DX applications — GNOME apps, Thunderbird, Podman Desktop,
GNOME Builder, DevToolbox, Clapgrep, Embellish, Bazaar, Flatseal, DistroShelf
and the rest of the maintained set — plus WeChat, Rnote and Gear Lever. Firefox
is deliberately not preinstalled; `flatpak install org.mozilla.firefox` adds it.
The two adw-gtk3 theme extensions and Tavern (no longer on Flathub) are skipped.

**Helium is the default browser** for links and HTML. Four programs have no
Flatpak, so their upstream RPMs are baked in at pinned versions: Helium
0.19.4.1 (from the official `imput/helium` COPR), Clash Verge Rev 2.5.8,
Rayburst 4.0.1 and sing-box (SFL) 1.14.3. Each upstream release is caught by the
daily upstream-watch workflow, which bumps the pin and publishes a new signed
image tag — the apps do not wait for a Fedora major release.

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
`.github/workflows/release-iso.yml` from the published ISO layer.

The latest release is [`44.20261019T132911Z.55`](https://github.com/Wraindrock/wraindrock-linux/releases/tag/44.20261019T132911Z.55): `Wraindrock-Live.iso`
(6,869,286,912 bytes, `sha256:84039f3b01689959490fe68c0d9c2fa5b084d9078ee84e9d9ac928b97c15a3cb`),
split into four parts under 2 GiB, plus a self-extracting `-extract.sh` and
`SHA256SUMS`. The image channel currently points at `.59`; `.57`–`.59` are
docs/workflow rebuilds with the same system content as `.55`.

### From the GitHub Release

Download the four parts, `-extract.sh` and `SHA256SUMS` into one directory —
from the release page in a browser, or with plain `curl` (no GitHub account
needed):

```bash
VERSION=44.20261019T132911Z.55
BASE="https://github.com/Wraindrock/wraindrock-linux/releases/download/${VERSION}"
for part in 00 01 02 03; do
  curl -fLO "${BASE}/Wraindrock-Live-${VERSION}.zip.part-${part}"
done
curl -fLO "${BASE}/Wraindrock-Live-${VERSION}-extract.sh"
curl -fLO "${BASE}/SHA256SUMS"
chmod +x "Wraindrock-Live-${VERSION}-extract.sh"
"./Wraindrock-Live-${VERSION}-extract.sh"
```

The script verifies each part against `SHA256SUMS`, joins them, unpacks
`Wraindrock-Live.iso` next to the parts, and re-checks the ISO hash.

On Windows, join the parts with `copy /b` and open the resulting zip with
PeaZip, 7-Zip or WinRAR:

```bat
copy /b Wraindrock-Live-44.20261019T132911Z.55.zip.part-00+Wraindrock-Live-44.20261019T132911Z.55.zip.part-01+Wraindrock-Live-44.20261019T132911Z.55.zip.part-02+Wraindrock-Live-44.20261019T132911Z.55.zip.part-03 Wraindrock-Live.zip
```

### From GHCR (with `oras`)

```bash
oras pull ghcr.io/wraindrock/wraindrock-linux-disk:44.20261019T132911Z.55 -o disk
cd disk && sha256sum -c SHA256SUMS
```

Both routes give the same file. Verify it before writing:

```bash
sha256sum Wraindrock-Live.iso   # must print 84039f3b01689959490fe68c0d9c2fa5b084d9078ee84e9d9ac928b97c15a3cb
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
flatpak list --system                # the 41 declared preinstalls
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
