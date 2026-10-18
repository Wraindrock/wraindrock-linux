#!/usr/bin/env bash
# Give the installer ISO a boot-menu choice instead of force-installing.
#
# bootc-image-builder always injects `inst.ks=...`, so the image it produces
# erases the first disk without asking. This script rewrites the ISO's GRUB
# menus in place so that:
#
#   1. "Install Wraindrock (interactive, choose disks)" is the default and
#      starts Anaconda's hub (no kickstart), and
#   2. "Install Wraindrock - erase first disk (unattended)" keeps the generated
#      kickstart for hands-off installs.
#
# The rewrite is a same-length byte patch (padding with spaces), so the ISO9660
# extents, the El Torito/GPT boot images and the signed grubx64.efi are left
# untouched. Every menu text must match an exact number of times; a changed
# upstream layout fails the build instead of producing a half-themed ISO.
#
#   tests/iso-menu.sh path/to/install.iso
set -euo pipefail

iso="${1:?usage: iso-menu.sh ISO}"
[[ -f "${iso}" ]] || { echo "error: no such ISO: ${iso}" >&2; exit 2; }
command -v xorriso >/dev/null || { echo "error: xorriso is required" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf -- "${tmp}"' EXIT

xorriso -osirrox on -indev "${iso}" \
    -extract /EFI/BOOT/grub.cfg "${tmp}/uefi.cfg" \
    -extract /boot/grub2/grub.cfg "${tmp}/bios.cfg" 2>/dev/null
[[ -s "${tmp}/uefi.cfg" && -s "${tmp}/bios.cfg" ]] || {
    echo "error: the ISO has no expected GRUB menus" >&2
    exit 1
}

python3 - "${iso}" "${tmp}/uefi.cfg" "${tmp}/bios.cfg" <<'PY'
import mmap
import sys

iso_path, uefi_old_path, bios_old_path = sys.argv[1:]

TIME = "\tset timeout=60\n### END /etc/grub.d/00_header ###\n\n"
SEARCH = "\tsearch --no-floppy --set=root -l 'Container-Installer-x86_64'\n\n"
INTERACTIVE = (
    "\tmenuentry 'Install Wraindrock (interactive, choose disks)'"
    " --class fedora --class gnu-linux --class gnu --class os {\n"
    "\t\tlinux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Container-Installer-x86_64 quiet\n"
    "\t\tinitrd /images/pxeboot/initrd.img\n"
    "\t}\n\n"
)
UNATTENDED = (
    "\tmenuentry 'Install Wraindrock - erase first disk (unattended)'"
    " --class fedora --class gnu-linux --class gnu --class os {\n"
    "\t\tlinux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Container-Installer-x86_64"
    " inst.ks=hd:LABEL=Container-Installer-x86_64:/osbuild.ks quiet\n"
    "\t\tinitrd /images/pxeboot/initrd.img\n"
    "\t}\n"
)

UEFI_HEAD = (
    "function load_video {\n"
    "  insmod efi_gop\n"
    "  insmod efi_uga\n"
    "  insmod video_bochs\n"
    "  insmod video_cirrus\n"
    "  insmod all_video\n"
    "}\n\n"
    "load_video\n"
    "set gfxpayload=keep\n"
    "insmod gzio\n"
    "insmod part_gpt\n"
    "insmod ext2\n\n"
)
BIOS_HEAD = (
    "function load_video {\n"
    "  insmod all_video\n"
    "}\n\n"
    "load_video\n"
    "set gfxpayload=keep\n"
    "insmod gzio\n"
    "insmod part_gpt\n"
    "insmod ext2\n"
    "insmod chain\n\n"
)


def menu_text(head, size, path):
    text = (head + TIME + SEARCH + INTERACTIVE + UNATTENDED).encode()
    if len(text) > size:
        raise SystemExit(
            "error: %s needs %d bytes but the ISO stores %d" % (path, len(text), size)
        )
    # GRUB ignores trailing whitespace; keeping the length identical lets us
    # patch the ISO bytes without moving any extent.
    return text + b" " * (size - len(text))


def patch(handle, old, new, expected, label):
    count = 0
    offset = handle.find(old)
    while offset >= 0:
        handle[offset:offset + len(old)] = new
        count += 1
        offset = handle.find(old, offset + len(old))
    if count != expected:
        raise SystemExit(
            "error: %s matched %d times, expected %d (upstream ISO layout changed?)"
            % (label, count, expected)
        )
    print("patched %s: %d occurrence(s)" % (label, count))


with open(iso_path, "r+b") as iso_file:
    size = iso_file.seek(0, 2)
    image = mmap.mmap(iso_file.fileno(), size)
    try:
        uefi_old = open(uefi_old_path, "rb").read()
        bios_old = open(bios_old_path, "rb").read()
        patch(image, uefi_old, menu_text(UEFI_HEAD, len(uefi_old), "EFI menu"), 3, "UEFI menu")
        patch(image, bios_old, menu_text(BIOS_HEAD, len(bios_old), "BIOS menu"), 1, "BIOS menu")
    finally:
        image.flush()
        image.close()
PY

# Re-read through the ISO9660 layer: proves the visible menus changed and the
# filesystem is still readable.
xorriso -osirrox on -indev "${iso}" \
    -extract /EFI/BOOT/grub.cfg "${tmp}/uefi.new" \
    -extract /boot/grub2/grub.cfg "${tmp}/bios.new" 2>/dev/null
for menu in "${tmp}/uefi.new" "${tmp}/bios.new"; do
    grep -Fq "Install Wraindrock (interactive, choose disks)" "${menu}"
    grep -Fq "Install Wraindrock - erase first disk (unattended)" "${menu}"
    [[ "$(grep -cF 'inst.ks=' "${menu}")" == 1 ]] || {
        echo "error: $(basename "${menu}") does not have exactly one kickstart entry" >&2
        exit 1
    }
done
echo "installer choice added: interactive (default) or erase first disk (unattended)"
