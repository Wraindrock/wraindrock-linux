#!/usr/bin/env bash
# Give the installer ISO a boot-menu choice instead of force-installing.
#
# bootc-image-builder always injects `inst.ks=...`, so the image it produces
# erases the first disk without asking. This script rewrites the ISO's GRUB
# menus and adds a second, partial kickstart so that:
#
#   1. "Install Wraindrock (interactive, choose disks)" is the default. It
#      passes /interactive.ks, which only tells Anaconda where the bootc
#      payload is; language, disk/partitioning and user creation stay in the
#      user's hands.
#   2. "Install Wraindrock - erase first disk (unattended)" keeps the generated
#      kickstart for hands-off installs.
#
# The GRUB menu copies that live inside the El Torito/GPT EFI images are byte
# patched in place (padded with spaces so no extent moves). The two visible
# menu files and /interactive.ks are then replaced through xorriso, replaying
# the original boot equipment. Every menu copy must match an exact number of
# times; a changed upstream layout fails the build instead of producing a
# half-broken ISO.
#
#   tests/iso-menu.sh path/to/install.iso
set -euo pipefail

iso="${1:?usage: iso-menu.sh ISO}"
[[ -f "${iso}" ]] || { echo "error: no such ISO: ${iso}" >&2; exit 2; }
command -v xorriso >/dev/null || { echo "error: xorriso is required" >&2; exit 2; }

iso_dir="$(cd -- "$(dirname -- "${iso}")" && pwd)"
iso_name="$(basename -- "${iso}")"
iso="${iso_dir}/${iso_name}"
tmp="$(mktemp -d "${iso_dir}/.iso-menu.XXXXXX")"
trap 'rm -rf -- "${tmp}"' EXIT

xorriso -osirrox on -indev "${iso}" \
    -extract /EFI/BOOT/grub.cfg "${tmp}/uefi.cfg" \
    -extract /boot/grub2/grub.cfg "${tmp}/bios.cfg" \
    -extract /osbuild-base.ks "${tmp}/osbuild-base.ks" 2>/dev/null
[[ -s "${tmp}/uefi.cfg" && -s "${tmp}/bios.cfg" && -s "${tmp}/osbuild-base.ks" ]] || {
    echo "error: the ISO has no expected GRUB menus or kickstart" >&2
    exit 1
}

# Reuse the image reference that bootc-image-builder put in the unattended
# kickstart, so the interactive install records the same registry origin.
post_switch="$(grep -m1 '^bootc switch ' "${tmp}/osbuild-base.ks")" || {
    echo "error: the generated kickstart has no 'bootc switch' line" >&2
    exit 1
}
{
    echo 'ostreecontainer --url=/run/install/repo/container --transport=oci'
    echo
    echo '%post --erroronfail'
    echo 'set -e'
    echo "${post_switch}"
    echo '%end'
} >"${tmp}/interactive.ks"

python3 - "${iso}" "${tmp}/uefi.cfg" "${tmp}/bios.cfg" \
    "${tmp}/uefi.new" "${tmp}/bios.new" <<'PY'
import mmap
import re
import sys

iso_path, uefi_old_path, bios_old_path, uefi_new_path, bios_new_path = sys.argv[1:]
uefi_old = open(uefi_old_path, "rb").read()
bios_old = open(bios_old_path, "rb").read()

match = re.search(rb"search --no-floppy --set=root -l '([^']+)'", uefi_old)
if not match:
    raise SystemExit("error: cannot find the ISO volume label in the UEFI menu")
label = match.group(1).decode()

TIME = "\tset timeout=60\n### END /etc/grub.d/00_header ###\n\n"
SEARCH = "\tsearch --no-floppy --set=root -l '{}'\n\n".format(label)
INTERACTIVE = (
    "\tmenuentry 'Install Wraindrock (interactive, choose disks)'"
    " --class fedora --class gnu-linux --class gnu --class os {\n"
    "\t\tlinux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=" + label +
    " inst.ks=hd:LABEL=" + label + ":/interactive.ks quiet\n"
    "\t\tinitrd /images/pxeboot/initrd.img\n"
    "\t}\n\n"
)
UNATTENDED = (
    "\tmenuentry 'Install Wraindrock - erase first disk (unattended)'"
    " --class fedora --class gnu-linux --class gnu --class os {\n"
    "\t\tlinux /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=" + label +
    " inst.ks=hd:LABEL=" + label + ":/osbuild.ks quiet\n"
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


def menu_text(head):
    return (head + TIME + SEARCH + INTERACTIVE + UNATTENDED).encode()


uefi_new = menu_text(UEFI_HEAD)
bios_new = menu_text(BIOS_HEAD)
open(uefi_new_path, "wb").write(uefi_new)
open(bios_new_path, "wb").write(bios_new)

# The EFI boot images embed a copy of the UEFI menu. Patch every copy in place
# with the same byte length; the visible tree file is replaced via xorriso.
patched = uefi_new + b" " * (len(uefi_old) - len(uefi_new)) if len(uefi_new) <= len(uefi_old) else None
if patched is None:
    raise SystemExit(
        "error: new UEFI menu needs %d bytes but the image stores %d"
        % (len(uefi_new), len(uefi_old))
    )
count = 0
with open(iso_path, "r+b") as iso_file:
    size = iso_file.seek(0, 2)
    image = mmap.mmap(iso_file.fileno(), size)
    try:
        offset = image.find(uefi_old)
        while offset >= 0:
            image[offset:offset + len(uefi_old)] = patched
            count += 1
            offset = image.find(uefi_old, offset + len(uefi_old))
    finally:
        image.flush()
        image.close()
if count != 3:
    raise SystemExit(
        "error: UEFI menu matched %d times, expected 3 (tree + two EFI images);"
        " upstream ISO layout changed?" % count
    )
print("patched embedded UEFI menus: %d occurrence(s)" % count)
PY

# Replace the two visible menus and add the interactive kickstart, replaying the
# original El Torito/GPT boot equipment so the ISO stays hybrid-bootable.
xorriso -indev "${iso}" -outdev "${tmp}/install.partial" \
    -map "${tmp}/uefi.new" /EFI/BOOT/grub.cfg \
    -map "${tmp}/bios.new" /boot/grub2/grub.cfg \
    -map "${tmp}/interactive.ks" /interactive.ks \
    -boot_image any replay >"${tmp}/xorriso.log" 2>&1 || {
    cat "${tmp}/xorriso.log" >&2
    echo "error: xorriso failed to remaster the ISO" >&2
    exit 1
}

xorriso -osirrox on -indev "${tmp}/install.partial" \
    -extract /EFI/BOOT/grub.cfg "${tmp}/uefi.chk" \
    -extract /boot/grub2/grub.cfg "${tmp}/bios.chk" \
    -extract /interactive.ks "${tmp}/interactive.chk" 2>/dev/null
for menu in "${tmp}/uefi.chk" "${tmp}/bios.chk"; do
    grep -Fq "Install Wraindrock (interactive, choose disks)" "${menu}"
    grep -Fq "Install Wraindrock - erase first disk (unattended)" "${menu}"
    [[ "$(grep -cF 'inst.ks=' "${menu}")" == 2 ]] || {
        echo "error: $(basename "${menu}") must have exactly two kickstart entries" >&2
        exit 1
    }
    [[ "$(grep -cF '/interactive.ks' "${menu}")" == 1 ]] || {
        echo "error: $(basename "${menu}") must use /interactive.ks once" >&2
        exit 1
    }
    [[ "$(grep -cF '/osbuild.ks' "${menu}")" == 1 ]] || {
        echo "error: $(basename "${menu}") must use /osbuild.ks once" >&2
        exit 1
    }
done
grep -Fq 'ostreecontainer --url=/run/install/repo/container --transport=oci' "${tmp}/interactive.chk"
grep -Fq 'bootc switch --mutate-in-place --transport registry' "${tmp}/interactive.chk"

xorriso -indev "${tmp}/install.partial" -report_el_torito plain 2>/dev/null |
    grep -q 'BIOS' || { echo "error: remastered ISO lost its BIOS boot image" >&2; exit 1; }
xorriso -indev "${tmp}/install.partial" -report_el_torito plain 2>/dev/null |
    grep -q 'UEFI' || { echo "error: remastered ISO lost its UEFI boot image" >&2; exit 1; }

mv -f -- "${tmp}/install.partial" "${iso}"
echo "installer choice added: interactive (default) or erase first disk (unattended)"
