# Rolling back

Every bootc system keeps its previous deployment on disk. Rollback is local and
offline: it does not need the registry, the network, or a working new image.

## The normal escape hatch

```bash
bootc status              # identify the rollback deployment
sudo bootc rollback
sudo systemctl reboot
```

After reboot, `bootc status` should show the previous deployment as `Booted:`.
The bad deployment remains listed — rolling forward again is `bootc rollback`
once more (it swaps booted/rollback), or `bootc switch` to a known-good tag.

`bootc rollback` is implemented on top of ostree deployments, so on Fedora
Atomic systems `sudo rpm-ostree rollback` still works as a fallback. Prefer
`bootc rollback`; it is the supported interface for bootc images.

## Rolling back to the previous *published* image

If the previous local deployment is already gone (for example after several
updates), switch to the registry's rollback pointer:

```bash
sudo bootc switch ghcr.io/wraindrock/wrainrock-linux:previous
sudo systemctl reboot
```

`previous` is the `44` channel image that was current before the last release.
It is a moving tag, so record the digest if you need it to be reproducible:

```bash
podman inspect --format '{{index .RepoDigests 0}}' ghcr.io/wraindrock/wrainrock-linux:previous
```

## Rolling back to stock Fedora Silverblue

```bash
sudo bootc switch quay.io/fedora/fedora-silverblue:44
sudo systemctl reboot
```

This is the cleanest "uninstall": your data stays, and the next boot is plain
Fedora. Do this before reporting an install problem if you need a working
machine quickly.

## If the system does not boot

1. **Bootloader menu.** Hold `Shift` (BIOS) or press `Esc` (UEFI) during boot to
   get the menu. Fedora keeps one entry per deployment; pick the older one. This
   is the recovery path that does not require a working new deployment.
2. **Recovery shell.** Fedora entries include rescue/recovery options. From a
   root shell, `bootc status` and `bootc rollback` still work.
3. **Live USB.** Boot a Fedora Atomic live image and inspect the installed
   system read-only (`ostree admin status` against the deployment root). Do not
   attempt to "repair" the deployment by editing files in place — switch to a
   known-good image instead.
4. **Reinstall as a last resort.** Back up `/home` from the live environment
   first. Wrainrock has no installer of its own yet; reinstall Silverblue with
   Anaconda and then `bootc switch` back if you want Wrainrock again.

## What rollback does *not* recover

- **Data you deleted.** Rollback swaps OS deployments, not `/home` or `/var`.
  Flatpak app data in `~/.var` is equally yours to back up.
- **A full disk.** If there is no room for another deployment, clean up first
  (`rpm-ostree cleanup -p`, `podman system prune`) — but never delete the booted
  deployment.
- **A corrupted ESP or firmware.** These need firmware/partition work, not a
  bootc command; use a live USB.
- **Container images pulled after the last deployment.** They live in `/var` and
  are unaffected by rollback; that is usually desirable, occasionally surprising.

## Checking that rollback is available *before* you need it

```bash
bootc status | grep -A2 'Rollback'
```

If no rollback deployment is listed, you have one deployment only — a good
moment to decide whether that is acceptable before switching images.
