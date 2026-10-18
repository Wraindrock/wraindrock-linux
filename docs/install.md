# Installing Wraindrock Linux

Wraindrock v0.4 is a remix of **Bluefin DX**. It is installed either from the
unattended ISO below or with a `bootc switch` on an existing Bluefin DX system.
The switch is not a repartition: your home directory, flatpaks, containers and
user data are untouched. It adds a new boot deployment; your current system
stays on disk as the rollback target.

> **Read [rollback.md](rollback.md) before you switch.** The escape hatch is the
> reason this is safe, and it is boring — but only if you know it.

## Install from the ISO (v0.3)

The ISO produced by `.github/workflows/disk.yml` is **unattended**: its baked
kickstart runs `autopart`, clears the first disk, installs the embedded image and
reboots. There is no disk picker and no confirmation prompt.

> **Warning:** booting the ISO on a machine with data disks attached will wipe
> the first one. Test in a VM, or physically detach everything you want to keep.

```bash
# Pull the immutable artifact set for the image version, then verify it
oras pull ghcr.io/wraindrock/wraindrock-linux-disk:<version>
sha256sum -c SHA256SUMS
sudo dd if=install.iso of=/dev/sdX bs=8M status=progress oflag=direct conv=fsync
```

Boot the USB on a UEFI machine (Secure Boot: enrol Fedora's key if prompted, as
with any Fedora media). Anaconda runs in text mode on the console; when it
finishes, the machine reboots into GDM. The first boot shows the Wraindrock
wallpaper, Plymouth splash and GDM wordmark. The GRUB menu theme remains opt-in
after install (`sudo wraindrock-grub-theme enable`).

## Supported starting points

| System | Notes |
| --- | --- |
| Bluefin DX 44 (`ghcr.io/ublue-os/bluefin-dx:stable`) | Primary target: the same package set plus the recorded delta |
| Bluefin 44 (`ghcr.io/ublue-os/bluefin:stable`) | Works, but the next deployment is the DX variant |
| Bluefin DX `gts` (older release) | Switch to the `44` stream first; do not cross a release |
| Fedora Silverblue/Kinoite 44 | Not a supported target: the next deployment is Bluefin DX and distro-specific layering is lost; use the ISO or a VM |
| Any system older than 44 | Do not cross a release into Wraindrock |

Check that the running system understands bootc:

```bash
bootc --version
bootc status
```

You should see `Booted: ...` and a `Base:` image. On a non-bootc system (plain
Workstation, rpm-ostree from before the bootc split) use the ISO above; a custom
installer with partitioning and encryption choices is not in scope.

## Preheat checks

Run these once. Five minutes now avoids a bad afternoon.

1. **Free space.** The image is roughly the size of Bluefin DX. Keep at least
   **10 GiB free** on the root filesystem, and ideally 15 GiB so both the new
   deployment and the previous one fit comfortably.

   ```bash
   df -h /
   bootc status    # shows existing deployments
   ```

2. **ESP space.** Multi-deployment systems put a kernel+initramfs per deployment
   on the EFI System Partition. Fedora's default 1 GiB ESP usually fits 3–4
   deployments; if you have many layered deployments, prune old ones first:

   ```bash
   rpm-ostree cleanup -p     # prune pending/rollback deployments, not the booted one
   df -h /boot/efi
   ```

3. **Back up what you cannot recreate.** The switch should not touch `/home`,
   but "should not" is not "cannot". A current backup of `~`, SSH keys and
   browser profiles is cheap.

   ```bash
   sudo bootc status > ~/bootc-status-before-switch.txt
   ```

4. **Secure Boot.** Wraindrock ships Bluefin DX's kernels and shim, unmodified.
   Secure Boot is expected to work, but the branded image has not been validated
   on Secure Boot hardware. On an NVIDIA variant, prebuilt akmods are enrolled
   through MOK the same way upstream Bluefin does it; read your firmware's
   recovery path before switching. If you dual-boot with a custom key setup,
   keep that recovery path at hand.

## Switch

```bash
sudo bootc switch ghcr.io/wraindrock/wraindrock-linux:44
```

`switch` pulls the image, verifies it is a bootc image, and stages a new
deployment. It does **not** reboot. Inspect what will boot next:

```bash
bootc status
```

Then reboot:

```bash
sudo systemctl reboot
```

## Verify after reboot

```bash
bootc status
```

- `Booted:` should reference `ghcr.io/wraindrock/wraindrock-linux:44`.
- The previous Bluefin deployment should still be listed as the rollback
  deployment.

```bash
cat /usr/lib/os-release
# NAME="Wraindrock Linux"
# ID=bluefin
# ID_LIKE="fedora"
```

`ID` and `ID_LIKE` stay upstream's on purpose: uBlue tooling keys off
`ID=bluefin`. `PRETTY_NAME` keeps the Bluefin version (`Wraindrock (Version:
44.<date>)`), which tells you which upstream snapshot and update window you are
actually running. `CPE_NAME` continues to name Universal Blue — the lineage is
not rewritten.

```bash
cat /usr/share/wraindrock/delta.json
```

Every intended difference from the base is listed there. If the image differs
from the base in any other way, that is a bug — report it.

```bash
gsettings get org.gnome.desktop.background picture-uri
# 'file:///usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png'
```

If you had already changed your wallpaper, your personal setting wins — the
image only changes the default for new users and for the login screen. Reset it
with `gsettings reset org.gnome.desktop.background picture-uri` to see the
Wraindrock default.

```bash
plymouth-set-default-theme
# wraindrock
```

The splash is drawn from the initramfs and handed over to the root filesystem,
so it only changes after the new deployment regenerates its initrd. `bootc`
does that on deploy; if you ever need to force it, `sudo dracut -f`.

```bash
sudo wraindrock-grub-theme status
```

The GRUB menu theme is **opt-in**. bootc images cannot rewrite
`/boot/grub2/grub.cfg`: bootupd installs it as a static config when the system
is installed. The image ships `/usr/bin/wraindrock-grub-theme`, which copies the
theme to `/boot/grub2/themes/wraindrock/` and wires it in through bootupd's
supported `custom.cfg` hook:

```bash
sudo wraindrock-grub-theme enable
sudo systemctl reboot
```

The helper refuses to touch a `custom.cfg` it does not manage, and it only works
on systems whose GRUB config sources `custom.cfg` (systemd-boot hosts are not
supported). To undo it: `sudo wraindrock-grub-theme disable --yes`.

```bash
hostnamectl
```

A fresh install seeds the hostname to `wraindrock` on its first boot
(`wraindrock-hostname-seed.service`). It only replaces an unconfigured name — an
empty file, or the base default `bluefin`/`fedora` — and never touches a name you
already set. On a `bootc switch` the existing `/etc/hostname` wins. Change it
with `sudo hostnamectl set-hostname <name>`; this does not modify the image.

```bash
cat /usr/share/wraindrock/build-info.json
```

This is the receipt: base image digest, Fedora version, git SHA, build date and
RPM-set hash. Compare it with the digest published by the build that you meant
to install.

```bash
cosign verify \
  --certificate-identity-regexp '^https://github.com/Wraindrock/wraindrock-linux/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/wraindrock/wraindrock-linux:44
```

If cosign cannot verify the image, do not trust it — roll back and report it.

## Updating

Updates are manual by default:

```bash
sudo bootc update
sudo systemctl reboot
```

`bootc update` stages the current `44` channel image; the reboot activates it.
Nothing changes in the running system until then.

Automatic updates are **off**. If you want them, enable the bootc update timer
(your base image must ship it; check with `systemctl list-timers | grep -i bootc`):

```bash
systemctl cat bootc-fetch-apply-updates.timer   # confirm it exists first
sudo systemctl enable --now bootc-fetch-apply-updates.timer
```

Pinning an exact build instead of following the channel:

```bash
sudo bootc switch ghcr.io/wraindrock/wraindrock-linux:44.20261017T061500Z.42
```

## Going back

See [rollback.md](rollback.md). The short version:

```bash
sudo bootc rollback
sudo systemctl reboot
```

To return to stock Bluefin DX instead of the previous Wraindrock build:

```bash
sudo bootc switch ghcr.io/ublue-os/bluefin-dx:stable
sudo systemctl reboot
```

## Troubleshooting

Worked examples, in the "symptom → exact message → cause → fix" form. Exact
strings matter because they are what you search for.

### `unauthorized: authentication required`

```
error: copying image ...: reading manifest 44 in ghcr.io/wraindrock/wraindrock-linux:
unauthorized: authentication required
```

**Cause:** the GHCR package is still private, or your podman has stale GHCR
credentials.

**Fix:** make the package public (GitHub → Packages → the package → Package
settings → Change visibility), or authenticate:

```bash
podman login ghcr.io        # username: your GitHub user, password: a PAT with read:packages
sudo bootc switch ghcr.io/wraindrock/wraindrock-linux:44
```

**Escape hatch:** your running system was never modified; nothing to undo.

### `error: No space left on device` during switch/update

**Cause:** root filesystem or ESP is full; a second full deployment does not fit.

**Fix:** free space (`sudo rpm-ostree cleanup -p` removes *pending/rollback*
deployments only, never the booted one; `podman system prune` for containers),
or grow the root LV. Retry `bootc update`.

**Escape hatch:** the running deployment is intact. If the update already staged
a partial new deployment and the ESP is full, reboot into the booted entry and
clean up before retrying.

### `error: Bootloader ... couldn't add entry`

**Cause:** ESP is full or the EFI variables are read-only (firmware/BIOS bug,
or `efivars` mounted read-only).

**Fix:** free ESP space, reboot once, retry. If EFI variables are genuinely
read-only, the system cannot stage new deployments — stop updating and fix the
firmware setup first.

**Escape hatch:** current system boots; no data lost.

### `error: Image is not a bootc image`

**Cause:** wrong reference (e.g. a plain container image or a typo), or an old
bootc CLI that does not understand the base.

**Fix:** double-check the exact tag; update `bootc` on the host. `bootc --version`
should be at least the version Fedora 44 ships.

### `bootc status` shows `Base: none` / unexpected image after switch

**Cause:** you are looking at the booted deployment, not the newly staged one.
`bootc status` shows both; the staged deployment appears under `Staged:`.

**Fix:** reboot, then re-check. If `Booted:` is still the old image, the switch
did not stage — re-run it and read the error.

### Secure Boot refuses to boot Wraindrock

**Cause:** Wraindrock uses the base image's signed kernels, but a custom key
enrollment, a non-standard shim, or an unenrolled NVIDIA MOK can break the chain.

**Fix:** enroll Fedora's key or disable Secure Boot after understanding the risk;
this is a firmware/key-management issue, not an image defect.

**Escape hatch:** bootloader menu → previous Bluefin entry.

### GRUB menu still looks like Fedora

`sudo wraindrock-grub-theme status` reports `custom.cfg: absent`, and the boot
menu is unchanged. The theme is opt-in by design; enable it with
`sudo wraindrock-grub-theme enable`.

If enable fails with `error: ... does not source custom.cfg`, the installed
bootloader config predates bootupd's static configs. Run
`sudo bootupctl migrate-static-grub-config` (it keeps a backup at
`/boot/grub2/grub.cfg.backup`), then retry. Escape hatch:
`sudo wraindrock-grub-theme disable --yes`.

### Logs and upstream

```bash
RUST_LOG=bootc=debug sudo bootc update     # verbose bootc client logs
journalctl -b -u bootc-fetch-apply-updates  # if you enabled the timer
```

- bootc: <https://github.com/bootc-dev/bootc/issues>
- Bluefin documentation: <https://docs.projectbluefin.io/>
- Wraindrock issues: <https://github.com/Wraindrock/wraindrock-linux/issues>
