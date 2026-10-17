# Installing Wrainrock Linux

Wrainrock v0.2 is installed **on top of an existing Fedora Atomic Desktop**. It
is a `bootc switch`, not a repartition: your home directory, flatpaks, containers
and user data are untouched. The switch adds a new boot deployment; your current
system stays on disk as the rollback target.

> **Read [rollback.md](rollback.md) before you switch.** The escape hatch is the
> reason this is safe, and it is boring — but only if you know it.

## Supported starting points

| System | Notes |
| --- | --- |
| Fedora Silverblue 44 | Primary target |
| Fedora Kinoite 44 | bootc switch works; the new deployment is GNOME (Silverblue), not KDE |
| Bluefin / Aurora 44 (`ublue-os` bootc images) | Works; Wrainrock owns the whole image, so Bluefin tooling is not carried over |
| Fedora Silverblue 43 or older | Switch to 44 first; do not cross a release into Wrainrock |

Check that the running system understands bootc:

```bash
bootc --version
bootc status
```

You should see `Booted: ...` and a `Base:` image. On a non-bootc system (plain
Workstation, rpm-ostree from before the bootc split) stop here — Wrainrock does
not ship an installer yet; that is v0.3 on the roadmap.

## Preheat checks

Run these once. Five minutes now avoids a bad afternoon.

1. **Free space.** The image is roughly the size of Silverblue. Keep at least
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

4. **Secure Boot.** Wrainrock ships Fedora's signed kernels and shim,
   unmodified. Secure Boot is expected to work, but the branded image has not
   been validated on Secure Boot hardware. If you dual-boot with a custom key
   setup, read your firmware's recovery path before switching.

## Switch

```bash
sudo bootc switch ghcr.io/wraindrock/wrainrock-linux:44
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

- `Booted:` should reference `ghcr.io/wraindrock/wrainrock-linux:44`.
- The previous Silverblue deployment should still be listed as the rollback
  deployment.

```bash
cat /usr/lib/os-release
# NAME="Wrainrock Linux"
# ID=wrainrock
# ID_LIKE="fedora"
```

`PRETTY_NAME` keeps the base Fedora version (`Wrainrock Linux 44.<build>
(Silverblue)`): the version tells you which Fedora release and update window
you are actually running.

```bash
cat /usr/share/wrainrock/delta.json
```

Every intended difference from the base is listed there. If the image differs
from the base in any other way, that is a bug — report it.

```bash
gsettings get org.gnome.desktop.background picture-uri
# 'file:///usr/share/backgrounds/wrainrock/wrainrock-wallpaper.png'
```

If you had already changed your wallpaper, your personal setting wins — the
image only changes the default for new users and for the login screen. Reset it
with `gsettings reset org.gnome.desktop.background picture-uri` to see the
Wrainrock default.

```bash
hostnamectl
```

The default hostname for new installs is `wrainrock`, but on a `bootc switch`
the existing static hostname in `/etc/hostname` wins. Change it with
`sudo hostnamectl set-hostname <name>`; this does not modify the image.

```bash
cat /usr/share/wrainrock/build-info.json
```

This is the receipt: base image digest, Fedora version, git SHA, build date and
RPM-set hash. Compare it with the digest published by the build that you meant
to install.

```bash
cosign verify \
  --certificate-identity-regexp '^https://github.com/Wraindrock/wrainrock-linux/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/wraindrock/wrainrock-linux:44
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
sudo bootc switch ghcr.io/wraindrock/wrainrock-linux:44.20261017T061500Z.42
```

## Going back

See [rollback.md](rollback.md). The short version:

```bash
sudo bootc rollback
sudo systemctl reboot
```

To return to stock Fedora Silverblue instead of the previous Wrainrock build:

```bash
sudo bootc switch quay.io/fedora/fedora-silverblue:44
sudo systemctl reboot
```

## Troubleshooting

Worked examples, in the "symptom → exact message → cause → fix" form. Exact
strings matter because they are what you search for.

### `unauthorized: authentication required`

```
error: copying image ...: reading manifest 44 in ghcr.io/wraindrock/wrainrock-linux:
unauthorized: authentication required
```

**Cause:** the GHCR package is still private, or your podman has stale GHCR
credentials.

**Fix:** make the package public (GitHub → Packages → the package → Package
settings → Change visibility), or authenticate:

```bash
podman login ghcr.io        # username: your GitHub user, password: a PAT with read:packages
sudo bootc switch ghcr.io/wraindrock/wrainrock-linux:44
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

### Secure Boot refuses to boot Wrainrock

**Cause:** Wrainrock uses Fedora's signed kernels, but a custom key enrollment or
a non-standard shim can break the chain.

**Fix:** enroll Fedora's key or disable Secure Boot after understanding the risk;
this is a firmware/key-management issue, not an image defect.

**Escape hatch:** bootloader menu → previous Silverblue entry.

### Logs and upstream

```bash
RUST_LOG=bootc=debug sudo bootc update     # verbose bootc client logs
journalctl -b -u bootc-fetch-apply-updates  # if you enabled the timer
```

- bootc: <https://github.com/bootc-dev/bootc/issues>
- Fedora Atomic Desktops: <https://docs.fedoraproject.org/en-US/atomic-desktops/>
- Wrainrock issues: <https://github.com/Wraindrock/wrainrock-linux/issues>
