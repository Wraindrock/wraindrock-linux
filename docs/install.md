# Installing Wraindrock

Wraindrock v0.4 is a remix of **Bluefin DX**. There are two install paths:

1. pull the image with `bootc switch` on an existing Bluefin DX 44 system;
2. download the ISO and install from scratch.

Read [rollback.md](rollback.md) before either. The switch does not repartition
or touch `/home`, and the previous deployment stays on disk as the rollback
target — but only if you know where it is.

## Before you start

- **Bluefin DX 44** is the only supported starting point. Do not cross a
  release.
- **Disk space:** keep 10 GiB free on `/`, ideally 15 GiB so two deployments fit.
- **ESP:** each deployment adds a kernel and initramfs. If `df -h /boot/efi`
  is tight, prune rollback deployments first (`sudo rpm-ostree cleanup -p`).
- **Backup:** `/home` should be untouched, but back up what you cannot recreate.
- **Secure Boot:** the image ships Bluefin DX's signed kernels and shim
  unmodified; on an NVIDIA variant, MOK enrollment works as upstream.

## 1. Pull the image (ghcr.io)

```bash
bootc --version
bootc status
sudo bootc switch ghcr.io/wraindrock/wraindrock-linux:44
bootc status          # inspect the staged deployment
sudo systemctl reboot
```

Updates follow the `44` channel:

```bash
sudo bootc update
sudo systemctl reboot
```

To pin one exact build, switch to its immutable tag
(`ghcr.io/wraindrock/wraindrock-linux:44.<UTC>.<run>`).

## 2. Download the ISO

Two equivalent sources; every build publishes both. The full inventory is in
[releases.md](releases.md).

**GitHub Release (split, self-extracting).** One command downloads the newest
release, verifies every part, joins them and unpacks `Wraindrock-Live.iso`
(no GitHub account required):

```bash
curl -fsSL https://raw.githubusercontent.com/Wraindrock/wraindrock-linux/main/tools/get-live-iso.sh | bash
```

Add `--out DIR` (as `bash -s -- --out DIR`) to choose the directory, or
`--dry-run` to print the resolved version and asset names first.

**GHCR OCI artifact.** The same files are stored as one immutable artifact:

```bash
oras pull ghcr.io/wraindrock/wraindrock-linux-disk:<version> -o disk
cd disk && sha256sum -c SHA256SUMS
```

The helper verifies the ISO hash; compare it with the release notes, then write
it:

```bash
sudo dd if=Wraindrock-Live.iso of=/dev/sdX bs=8M status=progress oflag=direct conv=fsync
```

The boot menu offers two entries:

- **Install Wraindrock (interactive, choose disks)** — the default. Anaconda's
  hub opens so you choose the target disk, partitioning and user account
  yourself. Its partial kickstart only supplies the bootc payload location;
  language is picked at first boot.
- **Install Wraindrock - erase first disk (unattended)** — keeps the generated
  kickstart: it clears the first disk and installs without prompting. Use it
  only on a scratch machine, with data disks detached, or in a VM.

> The ISO is larger than 4 GB, so use an 8 GB or larger USB stick formatted for
> a single >4 GB file (exFAT) or write it directly with `dd`.

Boot the stick on a UEFI machine, pick an entry and let Anaconda install; the
system reboots into GDM. On the first boot the network must be up: the system
installs 41 Flatpaks in the background (Podman Desktop, GNOME Builder,
DevToolbox, Clapgrep, Embellish, WeChat, Rnote, Gear Lever, …). Helium is the
default browser; Firefox is not preinstalled. The
GRUB menu theme stays opt-in: `sudo wraindrock-grub-theme enable`.

## Verify after reboot

```bash
bootc status                         # Booted: ghcr.io/wraindrock/wraindrock-linux:44
cat /usr/lib/os-release              # NAME="Wraindrock", ID=bluefin
cat /usr/share/wraindrock/delta.json # every intended difference
hostnamectl                          # wraindrock on a fresh install
flatpak list --system                # the 41 declared preinstalls
rpm -q helium-bin clash-verge rayburst sing-box  # baked apps
nvidia-smi                           # NVIDIA open driver
virsh --version && incus version     # KVM/libvirt and Incus
gsettings get org.gnome.desktop.background picture-uri
gsettings get org.gnome.desktop.input-sources sources  # IBus + libpinyin
plymouth-set-default-theme           # wraindrock
sudo wraindrock-grub-theme status    # opt-in
```

The first boot downloads the Flatpaks in the background; give it network and a
few GB of free space, and `systemctl status flatpak-preinstall` shows progress.
The four RPMs are part of the image and update with it. For a package you
need newer before an image update, use
`sudo rpm-ostree override replace <path-or-url-to-rpm>`; removing the override
goes back to the baked version. Flatpaks update independently of the image
through Flathub.

`ID=bluefin` and `CPE_NAME` stay upstream's on purpose: uBlue tooling keys off
`ID`, and the CPE keeps the lineage honest. `PRETTY_NAME` keeps the Bluefin
version so you can tell which upstream snapshot you run.

Verify the published signature before trusting the image:

```bash
cosign verify \
  --certificate-identity-regexp '^https://github.com/Wraindrock/wraindrock-linux/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/wraindrock/wraindrock-linux:44
```

## Going back

```bash
sudo bootc rollback && sudo systemctl reboot          # previous deployment
sudo bootc switch ghcr.io/ublue-os/bluefin-dx:stable  # stock Bluefin DX
```

See [rollback.md](rollback.md) for bootloader recovery.

## Troubleshooting

### `unauthorized: authentication required`

The GHCR package is private or your credentials are stale. Make the package
public in its GitHub settings, or run `podman login ghcr.io` with a token that
has `read:packages`. Your running system was not modified.

### `error: No space left on device`

A second deployment does not fit. Free space (`sudo rpm-ostree cleanup -p`
removes pending/rollback deployments only), prune containers, or grow the root
filesystem. The booted deployment is intact.

### `error: Bootloader ... couldn't add entry`

The ESP is full or EFI variables are read-only. Free ESP space and retry; if
the firmware mounts EFI variables read-only, fix that first — deployments
cannot be staged otherwise.

### The GRUB menu still looks like upstream

The theme is opt-in. `sudo wraindrock-grub-theme enable` writes a managed
`custom.cfg`; `sudo wraindrock-grub-theme disable --yes` removes it. If enable
reports that the config does not source `custom.cfg`, run
`sudo bootupctl migrate-static-grub-config` first (it keeps
`/boot/grub2/grub.cfg.backup`).
