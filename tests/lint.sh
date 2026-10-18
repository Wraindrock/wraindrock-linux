#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Repository self check. Runs on every pull request and locally via
# `just check`. Deliberately dependency-light: bash, grep and coreutils, with
# optional shellcheck / actionlint upgrades when they are installed.
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."

failures=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  fail %s\n' "$1"; failures=$((failures + 1)); }

echo "shell syntax"
shell_files=()
while IFS= read -r file; do shell_files+=("$file"); done < <(
    find . -path ./.git -prune -o -type f -name '*.sh' -print | sort
)
# The GRUB theme helper is a bash script without a .sh suffix.
shell_files+=("build_files/grub-theme/wraindrock-grub-theme")
# Same for the first-boot hostname seeder.
shell_files+=("build_files/hostname/wraindrock-hostname-seed")
for file in "${shell_files[@]}"; do
    if bash -n "${file}"; then
        pass "${file}"
    else
        fail "${file} (bash -n)"
    fi
done

echo "executable bits"
for file in "${shell_files[@]}" Justfile; do
    if [[ -x ${file} || ${file} == Justfile ]]; then
        pass "${file}"
    else
        fail "${file} is not executable"
    fi
done

echo "image.env"
env_file=./image.env
if [[ -r ${env_file} ]]; then
    pass "${env_file} exists"
    # shellcheck disable=SC1090
    . "${env_file}"
    required=(IMAGE_NAME REPO_ORGANIZATION IMAGE_DESC IMAGE_LICENSE
              FEDORA_VERSION BASE_IMAGE DEFAULT_TAG)
    for key in "${required[@]}"; do
        if [[ -n ${!key:-} ]]; then
            pass "${key}=${!key}"
        else
            fail "${key} is empty or unset"
        fi
    done
    if [[ -z ${IMAGE_NAME:-} || ${IMAGE_NAME} =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
        pass "IMAGE_NAME is a valid image name"
    else
        fail "IMAGE_NAME must be lowercase [a-z0-9._-]"
    fi
    if [[ ${BASE_IMAGE:-} == ghcr.io/ublue-os/bluefin-dx:* ]]; then
        pass "BASE_IMAGE tracks Bluefin DX"
    else
        fail "BASE_IMAGE (${BASE_IMAGE:-}) does not track Bluefin DX"
    fi
    if [[ ${DEFAULT_TAG:-} == "${FEDORA_VERSION:-}" ]]; then
        pass "DEFAULT_TAG is the Fedora channel tag"
    else
        fail "DEFAULT_TAG (${DEFAULT_TAG:-}) must equal FEDORA_VERSION (${FEDORA_VERSION:-})"
    fi
    # The workflow sources this file; an unquoted value with spaces would be
    # parsed as a command. Every assignment must be quoted.
    if grep -Eq '^[A-Z_]+=[^"#]' "${env_file}"; then
        fail "image.env has an unquoted assignment"
    else
        pass "image.env assignments are quoted"
    fi
else
    fail "${env_file} is missing"
fi

echo "Containerfile"
containerfile=./Containerfile
if [[ -r ${containerfile} ]]; then
    pass "${containerfile} exists"
    for needle in \
        'FROM ${BASE_REF}' \
        'RUN bootc container lint' \
        'CMD ["/sbin/init"]' \
        'org.opencontainers.image.source=' \
        'org.wraindrock.base.image='; do
        if grep -Fq "${needle}" "${containerfile}"; then
            pass "Containerfile contains ${needle}"
        else
            fail "Containerfile is missing ${needle}"
        fi
    done
else
    fail "${containerfile} is missing"
fi

echo "branding"
for asset in \
    build_files/branding/wraindrock-logo-icon.svg \
    build_files/branding/wraindrock-gdm-logo.svg \
    build_files/branding/wraindrock-gdm-logo.png \
    build_files/branding/wraindrock-wallpaper.svg \
    build_files/branding/wraindrock-wallpaper.png \
    build_files/branding/plymouth/wraindrock.plymouth \
    build_files/branding/plymouth/background.png \
    build_files/branding/plymouth/wraindrock-boot-background.svg \
    build_files/branding/plymouth/wraindrock-boot-frame.svg \
    build_files/branding/grub/theme.txt \
    build_files/branding/grub/background.png; do
    if [[ -s ${asset} ]]; then
        pass "${asset} exists"
    else
        fail "${asset} is missing"
    fi
done
for svg in \
    build_files/branding/wraindrock-logo-icon.svg \
    build_files/branding/wraindrock-gdm-logo.svg \
    build_files/branding/wraindrock-wallpaper.svg \
    build_files/branding/plymouth/wraindrock-boot-background.svg \
    build_files/branding/plymouth/wraindrock-boot-frame.svg; do
    if grep -q '<text' "${svg}"; then
        fail "${svg} renders text at runtime (use outlines instead)"
    else
        pass "${svg} is font-independent"
    fi
done
if grep -Fiq '#3C6EB4' build_files/branding/wraindrock-logo-icon.svg &&
   grep -Fiq '#3C6EB4' build_files/branding/wraindrock-gdm-logo.svg &&
   grep -Fiq '#3C6EB4' build_files/branding/wraindrock-wallpaper.svg &&
   grep -Fiq '3c6eb4' build_files/branding/plymouth/wraindrock-boot-frame.svg &&
   grep -Fiq '3c6eb4' build_files/branding/plymouth/wraindrock.plymouth &&
   grep -Fiq '3c6eb4' build_files/branding/grub/theme.txt; then
    pass "branding assets use the documented Wraindrock blue"
else
    fail "branding assets lost the Wraindrock blue outline"
fi
if python3 - <<'PY'
import struct

with open("build_files/branding/wraindrock-wallpaper.png", "rb") as handle:
    data = handle.read(24)
assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
width, height = struct.unpack(">II", data[16:24])
assert (width, height) == (3840, 2160), f"wallpaper is {width}x{height}"
PY
then
    pass "wallpaper is a 3840x2160 PNG"
else
    fail "wallpaper is not a 3840x2160 PNG"
fi

plymouth_frames=$(find build_files/branding/plymouth -name 'animation-*.png' | wc -l)
if [[ ${plymouth_frames} -eq 30 ]]; then
    pass "Plymouth theme ships 30 animation frames"
else
    fail "Plymouth theme ships ${plymouth_frames} animation frames, want 30"
fi
if [[ -s build_files/branding/plymouth/animation-0001.png &&
      -s build_files/branding/plymouth/animation-0030.png ]]; then
    pass "Plymouth animation frames are numbered from 0001 to 0030"
else
    fail "Plymouth animation frames are missing or misnumbered"
fi
if python3 - <<'PY'
import glob
import struct


def dims(path):
    with open(path, "rb") as handle:
        data = handle.read(24)
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    return struct.unpack(">II", data[16:24])


assert dims("build_files/branding/plymouth/background.png") == (1920, 1080)
frames = sorted(glob.glob("build_files/branding/plymouth/animation-*.png"))
assert len(frames) == 30, len(frames)
assert dims(frames[0]) == (256, 256), dims(frames[0])
assert dims(frames[-1]) == (256, 256), dims(frames[-1])
PY
then
    pass "Plymouth assets are 1920x1080 background + 256x256 frames"
else
    fail "Plymouth assets have unexpected dimensions"
fi

echo "GRUB boot menu theme"
if [[ -x build_files/grub-theme/wraindrock-grub-theme ]]; then
    pass "GRUB theme helper is executable"
else
    fail "GRUB theme helper is missing or not executable"
fi
for needle in 'custom.cfg' 'set theme=' '--boot-dir' \
              'refusing to modify' 'loadfont'; do
    if grep -Fq -e "${needle}" build_files/grub-theme/wraindrock-grub-theme; then
        pass "GRUB theme helper handles ${needle}"
    else
        fail "GRUB theme helper is missing ${needle}"
    fi
done
for needle in 'desktop-image: "background.png"' 'title-text: "Wraindrock"' \
              '+ boot_menu' 'id = "__timeout__"'; do
    if grep -Fq "${needle}" build_files/branding/grub/theme.txt; then
        pass "GRUB theme contains ${needle}"
    else
        fail "GRUB theme is missing ${needle}"
    fi
done
if python3 - <<'PYGRUB'
import struct

with open("build_files/branding/grub/background.png", "rb") as handle:
    data = handle.read(24)
assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
width, height = struct.unpack(">II", data[16:24])
assert (width, height) == (1920, 1080), f"background is {width}x{height}"
PYGRUB
then
    pass "GRUB theme background is a 1920x1080 PNG"
else
    fail "GRUB theme background is not a 1920x1080 PNG"
fi

echo "first-boot hostname seeding"
for needle in 'DEFAULT_HOSTNAME' 'state_dir=/var/lib/wraindrock' \
              'hostname-seeded' 'hostname "${default}"'; do
    if grep -Fq -e "${needle}" build_files/hostname/wraindrock-hostname-seed; then
        pass "hostname seeder handles ${needle}"
    else
        fail "hostname seeder is missing ${needle}"
    fi
done
for needle in 'ConditionPathExists=!/var/lib/wraindrock/hostname-seeded' \
              'ExecStart=/usr/libexec/wraindrock-hostname-seed' \
              'WantedBy=sysinit.target'; do
    if grep -Fqx -e "${needle}" build_files/hostname/wraindrock-hostname-seed.service; then
        pass "hostname unit contains ${needle}"
    else
        fail "hostname unit is missing ${needle}"
    fi
done

echo "build invariants"
for needle in 'base-os-release' 'delta.json' 'zzzz-wraindrock.gschema.override' \
              'wraindrock-wallpaper.png' 'Theme=wraindrock' \
              'plymouth/animation-' 'grub/theme.txt' 'wraindrock-grub-theme' \
              'wraindrock-hostname-seed'; do
    if grep -Fq "${needle}" build_files/build.sh; then
        pass "build.sh handles ${needle}"
    else
        fail "build.sh does not handle ${needle}"
    fi
done
if grep -Eq 'dnf[[:space:]]+(install|remove|upgrade|groupinstall)|rpm[[:space:]]+-[iUe]' \
        build_files/build.sh; then
    fail "build.sh changes the RPM set; v0.2 must keep it identical to the base"
else
    pass "build.sh does not change the RPM set"
fi
if grep -Fq 'delta' tests/parity.sh; then
    pass "parity.sh enforces the delta manifest"
else
    fail "parity.sh does not check the delta manifest"
fi

echo "documentation"
for doc in README.md docs/architecture.md docs/install.md docs/roadmap.md \
           docs/rollback.md SECURITY.md CHANGELOG.md; do
    if [[ -s ${doc} ]]; then
        pass "${doc} exists"
    else
        fail "${doc} is missing or empty"
    fi
done
if grep -Fq "bootc switch" docs/install.md &&
   grep -Fq "ghcr.io/wraindrock/wraindrock-linux" docs/install.md; then
    pass "install doc documents the switch command"
else
    fail "docs/install.md does not document a bootc switch command"
fi
if grep -Fq 'wraindrock-grub-theme' docs/architecture.md &&
   grep -Fq 'wraindrock-grub-theme' docs/install.md; then
    pass "docs document the GRUB theme helper"
else
    fail "docs do not document the GRUB theme helper"
fi
if grep -Fq 'delta.json' docs/architecture.md &&
   grep -Fq 'delta.json' docs/install.md; then
    pass "docs document the delta manifest"
else
    fail "docs do not describe /usr/share/wraindrock/delta.json"
fi
if grep -Fq 'wraindrock-wallpaper' docs/architecture.md; then
    pass "architecture doc describes the wallpaper override"
else
    fail "docs/architecture.md does not describe the wallpaper"
fi
if grep -Fq 'plymouth' docs/architecture.md; then
    pass "architecture doc describes the Plymouth theme"
else
    fail "docs/architecture.md does not describe the Plymouth theme"
fi

if grep -Fq 'interactive' docs/install.md &&
   grep -Fq 'erase first disk' docs/install.md; then
    pass "docs/install.md documents the interactive and unattended boot entries"
else
    fail "docs/install.md does not document the installer choice"
fi
if [[ -x tests/iso-menu.sh ]]; then
    pass "installer menu patcher is executable"
    for needle in 'interactive, choose disks' 'erase first disk (unattended)' \
                  'inst.ks=' 'occurrence'; do
        if grep -Fq -e "${needle}" tests/iso-menu.sh; then
            pass "iso-menu.sh handles ${needle}"
        else
            fail "iso-menu.sh is missing ${needle}"
        fi
    done
else
    fail "tests/iso-menu.sh is missing or not executable"
fi
for shot in boot-menu gdm-login installer first-boot; do
    if [[ -s "docs/screenshots/${shot}.png" ]]; then
        pass "screenshot ${shot}.png exists"
    else
        fail "docs/screenshots/${shot}.png is missing"
    fi
done
if grep -Fq 'docs/screenshots/boot-menu.png' README.md; then
    pass "README shows the boot menu"
else
    fail "README does not show the boot menu"
fi
if grep -Fq 'disk.yml' README.md; then
    pass "README documents the disk-image workflow"
else
    fail "README does not mention disk.yml"
fi

echo "workflow"
if [[ -r .github/workflows/build.yml ]]; then
    pass "build workflow exists"
    for needle in 'packages: write' 'id-token: write' 'cosign sign' \
                  'bootc container lint' '--no-hostname' 'Anonymous pull check'; do
        if grep -Fq -e "${needle}" .github/workflows/build.yml; then
            pass "workflow contains ${needle}"
        else
            fail "workflow is missing ${needle}"
        fi
    done
else
    fail ".github/workflows/build.yml is missing"
fi
if [[ -r .github/workflows/disk.yml ]]; then
    pass "disk workflow exists"
    for needle in 'bootc-image-builder' '--type anaconda-iso' '--type qcow2' \
                  'SHA256SUMS' 'sha256sum' 'BIB_IMAGE' \
                  'wraindrock-linux-disk' 'oras push' 'oras manifest fetch' \
                  'immutable artifact tags are never overwritten' \
                  'tests/iso-menu.sh' \
                  'tests/iso-interactive-shots.sh' \
                  'Install Wraindrock (interactive, choose disks)' \
                  'vm-interactive' \
                  'f27adb935022d94df8dc77719c322dda592c78a0d57a6f7dcdd8d900b248c454'; do
        if grep -Fq -e "${needle}" .github/workflows/disk.yml; then
            pass "disk workflow contains ${needle}"
        else
            fail "disk workflow is missing ${needle}"
        fi
    done
else
    fail ".github/workflows/disk.yml is missing"
fi
for needle in 'ghcr.io/wraindrock/wraindrock-linux-disk' 'oras pull' \
              'immutable OCI artifact'; do
    if grep -Fq -e "${needle}" README.md docs/install.md docs/roadmap.md; then
        pass "docs mention ${needle}"
    else
        fail "docs are missing ${needle}"
    fi
done
if [[ -r disk_config/disk.toml ]]; then
    if grep -Fq 'minsize = "20 GiB"' disk_config/disk.toml; then
        pass "qcow2 disk config sizes the root filesystem"
    else
        fail "disk_config/disk.toml does not size the root filesystem"
    fi
else
    fail "disk_config/disk.toml is missing"
fi

echo "VM harness"
if [[ -s tests/fixtures/gnome-initial-setup.png ]]; then
    pass "GNOME welcome reference frame"
else
    fail "tests/fixtures/gnome-initial-setup.png is missing"
fi
if python3 -m py_compile tests/png-stats.py 2>/dev/null; then
    pass "tests/png-stats.py compiles"
else
    fail "tests/png-stats.py does not compile"
fi
rm -rf tests/__pycache__
for needle in 'Install finished' 'once=d' 'screen_ok' 'png-stats.py'; do
    if grep -Fq -e "${needle}" tests/vm-test.sh; then
        pass "vm-test.sh handles: ${needle}"
    else
        fail "tests/vm-test.sh is missing: ${needle}"
    fi
done
for fixture in anaconda-hub.png anaconda-destination.png \
               anaconda-partitioning.png boot-menu.png; do
    if [[ -s "tests/fixtures/${fixture}" ]]; then
        pass "interactive installer fixture: ${fixture}"
    else
        fail "tests/fixtures/${fixture} is missing"
    fi
done
for needle in 'interactive.ks' 'ostreecontainer --url=/run/install/repo/container' \
              '-boot_image any replay' 'xorriso'; do
    if grep -Fq -e "${needle}" tests/iso-menu.sh; then
        pass "iso-menu.sh handles: ${needle}"
    else
        fail "tests/iso-menu.sh is missing: ${needle}"
    fi
done
for needle in 'anaconda-hub.png' 'input-send-event' 'interactive-hub.png'; do
    if grep -Fq -e "${needle}" tests/iso-interactive-shots.sh; then
        pass "iso-interactive-shots.sh handles: ${needle}"
    else
        fail "tests/iso-interactive-shots.sh is missing: ${needle}"
    fi
done

echo "secrets"
if grep -rInE 'gh[pousr]_[A-Za-z0-9]{20,}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY' \
        --exclude-dir=.git . >/dev/null 2>&1; then
    fail "a credential-looking string is committed"
else
    pass "no credential-looking strings"
fi

echo "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck --severity=warning --external-sources "${shell_files[@]}"; then
        pass "shellcheck"
    else
        fail "shellcheck (see diagnostics above)"
    fi
else
    pass "shellcheck not installed, skipped"
fi

echo "actionlint"
if command -v actionlint >/dev/null 2>&1; then
    if actionlint .github/workflows/*.yml; then
        pass "actionlint"
    else
        fail "actionlint (see diagnostics above)"
    fi
else
    pass "actionlint not installed, skipped"
fi

echo
if [[ ${failures} -ne 0 ]]; then
    printf '%s check(s) failed\n' "${failures}" >&2
    exit 1
fi
printf 'all checks passed\n'
