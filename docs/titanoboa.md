# Titanoboa migration (draft for review)

Status: draft, not wired into CI yet. Target: qcow2 stays on
`bootc-image-builder`; the ISO moves to
[`ublue-os/titanoboa`](https://github.com/ublue-os/titanoboa).

## What Titanoboa expects inside the bootc image

The ISO builder is a thin wrapper around the container-native ISO contract.
It reads the image and *fails* unless the image itself provides:

- `/usr/lib/bootc-image-builder/iso.yaml` — label + GRUB entries (this change).
- `/usr/lib/modules/<kver>/vmlinuz` and `initramfs.img` next to it.
- `/usr/lib/grub/i386-pc/` — BIOS GRUB modules.
- `/boot/efi/EFI/<vendor>/` — `shimx64.efi`, `mmx64.efi`, `gcdx64.efi`.
  (uBlue example images copy `/usr/lib/efi/*/*/EFI` to `/boot/efi/` at build
  time, install `grub2-efi-x64-cdboot`, and add an `EFI/BOOT/fbx64.efi`
  fallback.)
- A live-capable initramfs: `dracut-live` and a regenerated initramfs with
  `dmsquash-live dmsquash-live-autooverlay`.
- `livesys-scripts` with `livesys.service` and `livesys-late.service` enabled.
- A larger `/var/tmp` for `bootc install` (the example ships a tmpfs mount
  unit, because `/run` is small on the live overlay).

Our current image has the kernel, initramfs and GRUB modules, but **not** the
live initramfs, livesys units, or `/boot/efi/EFI`. Those are the image-side
changes the migration needs.

## Image-side changes (proposed)

Add one section to `build_files/build.sh`:

1. `dnf install dracut-live livesys-scripts grub2-efi-x64-cdboot`.
2. Regenerate `/usr/lib/modules/<kver>/initramfs.img` with
   `dmsquash-live dmsquash-live-autooverlay`.
3. `systemctl enable livesys.service livesys-late.service`.
4. `mkdir -p /boot/efi && cp -av /usr/lib/efi/*/*/EFI /boot/efi/`, then the
   `EFI/BOOT/fbx64.efi` fallback copy.
5. Install the `/var/tmp` tmpfs mount unit.
6. Install `build_files/iso/iso.yaml` to
   `/usr/lib/bootc-image-builder/iso.yaml` and assert it parses.
7. Declare every new path in `delta.json`; parity asserts the contract files
   exist and the image boots.

## CI changes (proposed)

- `disk.yml`:
  - keep the qcow2 job on `bootc-image-builder`;
  - delete the Anaconda-ISO build, the `iso-menu.sh` remaster step and the
    interactive screenshot step;
  - add `uses: ublue-os/titanoboa@<pinned commit>` with
    `image-ref: ${{ ... }}` and `iso-dest: output/Wraindrock-Live.iso`;
  - recompute SHA256SUMS on the renamed file (Titanoboa returns
    `output.iso`; never reuse a hash taken before the rename).
- ISO VM test: the ISO now boots a live desktop, so the old
  "install unattended then reach GDM" assertion no longer applies. Test
  becomes "boot live ISO, reach the desktop" unless an unattended path is
  chosen below.
- `release-iso.yml`: unchanged split/self-extracting flow, but it downloads
  the Titanoboa ISO artifact and recomputes checksums after the rename.

## Unattended installation (decision needed)

Titanoboa's ISO is a live desktop; installation is started from the live
session (Readymade / `bootc install`). A classic Anaconda kickstart is **not**
available unless we embed an Anaconda stage2, which is the old BIB-style
ISO we are leaving.

Options:

- **A. Live only (simplest).** One GRUB entry, user installs from the live
  session. No unattended path.
- **B. Kernel-arg autoinstall (recommended if unattended is required).**
  Ship a small systemd unit that runs only when the kernel command line
  contains `wraindrock.autoinstall=1`; it selects the first non-removable
  disk (or a disk named by `wraindrock.disk=/dev/...`) and runs
  `bootc install to-disk --wipe`. A separate GRUB entry adds that argument.
  Needs an explicit rule for disk selection because it is destructive.
- **C. Anaconda variant.** Keep an Anaconda-enabled ISO alongside the
  Titanoboa live ISO, with the kickstart in `build_files/iso/kickstart.ks`.
  Most work, two ISO products.

`build_files/iso/kickstart.ks` is the draft for option C only; it does not
work with a Titanoboa live ISO as-is.

## Open questions

1. Unattended: A, B or C? For B, what disk-selection rule is acceptable
   (first disk, explicit kernel argument, refuse if more than one disk)?
2. Pin the Titanoboa action to a commit SHA (supply-chain rule) — the
   upstream README uses `@main`; Bluefin pins `840217d97b…` and uses the
   Justfile instead of the action.
3. Keep the split self-extracting release (yes per earlier decision)?
