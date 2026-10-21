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
    if [[ ${BASE_IMAGE:-} == ghcr.io/ublue-os/bluefin-dx-nvidia-open:* ]]; then
        pass "BASE_IMAGE tracks Bluefin DX NVIDIA"
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
for asset in build_files/branding/wraindrock-wallpaper.svg \
             build_files/branding/wraindrock-wallpaper.png; do
    if [[ -s ${asset} ]]; then
        pass "${asset} exists"
    else
        fail "${asset} is missing"
    fi
done
if grep -q '<text' build_files/branding/wraindrock-wallpaper.svg; then
    fail "wallpaper SVG renders text at runtime"
else
    pass "wallpaper SVG is font-independent"
fi
if grep -Fiq '3c6eb4' build_files/branding/wraindrock-wallpaper.svg; then
    pass "wallpaper uses the documented Wraindrock blue"
else
    fail "wallpaper lost the Wraindrock blue"
fi
if python3 - <<'PYWP'
import struct

with open("build_files/branding/wraindrock-wallpaper.png", "rb") as handle:
    data = handle.read(24)
assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
width, height = struct.unpack(">II", data[16:24])
assert (width, height) == (3840, 2160), f"wallpaper is {width}x{height}"
PYWP
then
    pass "wallpaper is a 3840x2160 PNG"
else
    fail "wallpaper is not a 3840x2160 PNG"
fi

echo "identity and application folders"
if grep -Fq "Wraindrock release" build_files/build.sh; then
    pass "build.sh brands /etc/system-release (bootupd UEFI entry name)"
else
    fail "build.sh does not brand /etc/system-release"
fi
if grep -Fq 'software/app-folders' build_files/build.sh; then
    pass "build.sh installs the static application-folder drop-in"
else
    fail "build.sh does not install software/app-folders"
fi
if [[ -s build_files/software/app-folders ]]; then
    pass "the application-folder drop-in exists"
else
    fail "build_files/software/app-folders is missing"
fi
for folder in Virtualization Proxies Wraindrock uBlue; do
    if grep -Fq "app-folders/folders/${folder}]" build_files/software/app-folders; then
        pass "app folder declared: ${folder}"
    else
        fail "app folder is missing: ${folder}"
    fi
done
for gone in Flatpak AppImage Bluefin; do
    if grep -Fq "app-folders/folders/${gone}]" build_files/software/app-folders; then
        fail "channel folder ${gone} would duplicate apps"
    else
        pass "no channel folder ${gone}"
    fi
done
if grep -Fq "favorite-apps=['helium.desktop'" build_files/build.sh; then
    pass "build.sh declares the default dock"
else
    fail "build.sh does not declare the default dock"
fi
if python3 tests/folders.py tests/fixtures/bluefin-folders.conf build_files/software/app-folders >/dev/null; then
    pass "every explicitly grouped app has exactly one folder"
else
    fail "the application folders duplicate at least one app"
fi
for stale in plymouth grub-theme wraindrock-gdm-logo; do
    if grep -Fq "${stale}" build_files/build.sh; then
        fail "build.sh still has removed appearance code: ${stale}"
    else
        pass "build.sh no longer ships ${stale}"
    fi
done

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

echo "software defaults"
for asset in build_files/software/flatpaks.txt build_files/software/mimeapps.list build_files/software/rpms.tsv; do
    if [[ -s ${asset} ]]; then
        pass "${asset} exists"
    else
        fail "${asset} is missing"
    fi
done
flatpak_count=$(grep -v '^#' build_files/software/flatpaks.txt | sed '/^[[:space:]]*$/d' | wc -l)
if [[ ${flatpak_count} == 41 ]]; then
    pass "flatpaks.txt declares 41 Flatpaks"
else
    fail "flatpaks.txt declares ${flatpak_count} Flatpaks, want 41"
fi
if grep -Ev '^#|^[[:space:]]*$' build_files/software/flatpaks.txt \
        | grep -Eqv '^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+$'; then
    fail "flatpaks.txt contains a malformed app ID"
else
    pass "flatpaks.txt app IDs are well formed"
fi
for app in io.podman_desktop.PodmanDesktop com.tencent.WeChat \
    com.github.flxzt.rnote it.mijorus.gearlever org.gnome.Builder \
    org.gnome.Calculator org.mozilla.thunderbird org.gnome.DejaDup; do
    if grep -Fxq "${app}" build_files/software/flatpaks.txt; then
        pass "flatpaks.txt lists ${app}"
    else
        fail "flatpaks.txt is missing ${app}"
    fi
done
if grep -Eq 'org\.mozilla\.firefox|app\.zen_browser\.zen|Gtk3theme' build_files/software/flatpaks.txt; then
    fail "flatpaks.txt still preinstalls Firefox, Zen or theme extensions"
else
    pass "flatpaks.txt skips Firefox, Zen and theme extensions"
fi
for scheme in text/html application/xhtml+xml x-scheme-handler/http x-scheme-handler/https; do
    if grep -Fxq "${scheme}=helium.desktop" build_files/software/mimeapps.list; then
        pass "Helium is the default for ${scheme}"
    else
        fail "Helium is not the default for ${scheme}"
    fi
done
rpm_rows=$(awk 'NF && $1 !~ /^#/' build_files/software/rpms.tsv | wc -l)
if [[ ${rpm_rows} == 4 ]]; then
    pass "rpms.tsv pins 4 upstream packages"
else
    fail "rpms.tsv pins ${rpm_rows} packages, want 4"
fi
for name in helium-bin clash-verge rayburst sing-box; do
    if awk -F'\t' -v n="${name}" 'NF && $1 == n && $2 != "" && $3 ~ /^https:\/\// && $4 ~ /^[0-9a-f]{64}$/' build_files/software/rpms.tsv | grep -q .; then
        pass "rpms.tsv has a complete pin for ${name}"
    else
        fail "rpms.tsv pin for ${name} is incomplete"
    fi
done
for needle in "flatpaks.txt" "mimeapps.list" "rpms.tsv" "rpm -i" "sha256sum -c" \
    "rpm_base_set_file" "rpmdb.sqlite-wal"; do
    if grep -Fq -- "${needle}" build_files/build.sh; then
        pass "build.sh handles ${needle}"
    else
        fail "build.sh does not handle ${needle}"
    fi
done
if grep -Fq -- 'delta["rpm"]["added"]' tests/parity.sh; then
    pass "parity checks the declared RPM additions"
else
    fail "parity does not check the declared RPM additions"
fi

echo "build invariants"
for needle in 'base-os-release' 'delta.json' 'zzzz-wraindrock.gschema.override' \
              'wraindrock-wallpaper.png' 'Wraindrock release' \
              '10-wraindrock-folders' 'wraindrock-hostname-seed' \
              'install -d -m 0755 /opt' \
              'org.gnome.desktop.input-sources' 'libpinyin' \
              'nvidia-driver' 'qemu-system-x86-core'; do
    if grep -Fq "${needle}" build_files/build.sh; then
        pass "build.sh handles ${needle}"
    else
        fail "build.sh does not handle ${needle}"
    fi
done
if grep -Fq 'GSETTINGS_BACKEND=memory' build_files/build.sh; then
    pass "build.sh verifies the input-method default without a session bus"
else
    fail "build.sh does not verify the compiled input-method default"
fi
if grep -Fq 'fcitx5' tests/parity.sh; then
    pass "parity refuses a stray Fcitx installation"
else
    fail "parity does not guard against Fcitx"
fi
if grep -Eq 'dnf[[:space:]]+(install|remove|upgrade|groupinstall)|rpm[[:space:]]+-[UeF]' \
        build_files/build.sh; then
    fail "build.sh removes or upgrades base packages; only pinned additions are allowed"
else
    pass "build.sh never removes or upgrades base packages"
fi
if [[ $(grep -Fc 'rpm -i "${rpm_dir}"' build_files/build.sh) -eq 1 ]]; then
    pass "build.sh installs only the pinned RPM directory"
else
    fail "build.sh has an unexpected rpm install command"
fi
if grep -Fq 'delta' tests/parity.sh; then
    pass "parity.sh enforces the delta manifest"
else
    fail "parity.sh does not check the delta manifest"
fi
if grep -Fq "enabled GNOME extensions match Bluefin's default" tests/parity.sh \
        && grep -Fq 'extension_list=' tests/parity.sh; then
    pass "parity.sh compares the GNOME extension set and enabled state with the base"
else
    fail "parity.sh does not verify the inherited GNOME extension defaults"
fi
if grep -Fq 'Extension Manager' README.md \
        && grep -Fq 'zz0-bluefin-modifications.gschema.override' README.md; then
    pass "README documents the inherited Bluefin desktop defaults"
else
    fail "README does not document the inherited Bluefin desktop defaults"
fi

echo "documentation"
for doc in README.md docs/architecture.md docs/install.md docs/releases.md \
           docs/roadmap.md docs/rollback.md SECURITY.md CHANGELOG.md; do
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
if grep -Fq 'system-release' docs/architecture.md &&
   grep -Fq 'system-release' docs/install.md; then
    pass "docs document the UEFI boot entry name"
else
    fail "docs do not document /etc/system-release"
fi
if grep -Fq '10-wraindrock-folders' docs/architecture.md; then
    pass "architecture doc describes the application folders"
else
    fail "docs/architecture.md does not describe the application folders"
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
for shot in boot-menu gdm-login installer-destination installer-partitioning first-boot; do
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

if grep -Eq '^gh (release|api|run|workflow|auth)\b' README.md docs/install.md docs/releases.md; then
    fail "user-facing docs must not require an authenticated gh CLI"
elif grep -Fq 'get-live-iso.sh' README.md \
        && grep -Fq 'get-live-iso.sh' docs/install.md \
        && grep -Fq 'get-live-iso.sh' docs/releases.md; then
    pass "download docs point at the newest-release helper"
else
    fail "download docs do not mention tools/get-live-iso.sh"
fi

if grep -Eq '44\.20[0-9]{6}T[0-9]{6}Z\.' README.md docs/install.md; then
    fail "user download docs must not pin a release version"
else
    pass "user download docs do not pin a version"
fi

if [[ -x tools/get-live-iso.sh ]] && grep -Fq 'releases/latest' tools/get-live-iso.sh \
        && grep -Fq -- '--dry-run' tools/get-live-iso.sh \
        && grep -Fq -- '--continue-at' tools/get-live-iso.sh \
        && grep -Fq -- '--retry-all-errors' tools/get-live-iso.sh; then
    pass "get-live-iso.sh resolves the newest release and resumes interrupted parts"
else
    fail "tools/get-live-iso.sh is missing, does not resolve releases/latest, or cannot resume"
fi

if grep -Fq 'Wraindrock-Live.iso' README.md \
        && grep -Fq 'docs/releases.md' README.md \
        && grep -Fq 'wraindrock-linux-disk' docs/releases.md \
        && grep -Fq 'get-live-iso.sh' docs/install.md; then
    pass "download paths and the release inventory are documented"
else
    fail "download docs are incomplete (README, install.md, releases.md)"
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
if [[ -r .github/workflows/upstream-watch.yml ]]; then
    pass "upstream watch workflow exists"
    for needle in 'rpms.tsv' 'copr.fedorainfracloud.org' 'clash-verge-rev' \
                  'rayburst' 'SagerNet/sing-box' 'workflow run build.yml'; do
        if grep -Fq -e "${needle}" .github/workflows/upstream-watch.yml; then
            pass "upstream watch workflow contains ${needle}"
        else
            fail "upstream watch workflow is missing ${needle}"
        fi
    done
else
    fail ".github/workflows/upstream-watch.yml is missing"
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
