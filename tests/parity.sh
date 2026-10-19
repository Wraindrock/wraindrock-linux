#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Parity test for the branded image.
#
# v0.1 asserted "byte identical to Fedora Silverblue"; after the Bluefin DX
# rebase the baseline is the upstream Bluefin DX image. The strong part of the
# promise still holds:
#
#   * the RPM set is still identical, package for package;
#   * /usr/lib/os-release may differ only in the identity keys listed in the
#     image's own delta manifest, with exactly the recorded values;
#   * every added file is one the delta manifest declares;
#   * the GDM logo and wallpaper overrides are compiled into the schema cache;
#   * the Plymouth boot splash is installed, selected, and complete.
#
#   tests/parity.sh ghcr.io/ublue-os/bluefin-dx:stable \
#                   localhost/wraindrock-linux:44
#
# Needs podman and python3; both images must be available locally.
# ---------------------------------------------------------------------------
set -euo pipefail

BASE="${1:-}"
IMAGE="${2:-}"
[[ -n ${BASE} && -n ${IMAGE} ]] || {
    echo "usage: tests/parity.sh <base-image> <image>" >&2
    exit 2
}

ENGINE="${WR_ENGINE:-podman}"
command -v "${ENGINE}" >/dev/null 2>&1 || {
    echo "${ENGINE} is required" >&2
    exit 1
}

failures=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  fail %s\n' "$1"; failures=$((failures + 1)); }

in_image() {
    local image="$1"
    shift
    "${ENGINE}" run --rm --entrypoint /usr/bin/bash "${image}" -c "$*"
}

echo "parity test"
echo "  base:  ${BASE}"
echo "  image: ${IMAGE}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

# --- RPM set ----------------------------------------------------------------
# The image may add packages, but only the ones delta.json declares, and it
# may not remove or replace anything the base shipped.
rpm_query='rpm -qa --qf "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n" | LC_ALL=C sort'
in_image "${BASE}" "${rpm_query}" > "${tmpdir}/base.rpm"
in_image "${IMAGE}" "${rpm_query}" > "${tmpdir}/image.rpm"
comm -13 "${tmpdir}/base.rpm" "${tmpdir}/image.rpm" > "${tmpdir}/rpm.added"
comm -23 "${tmpdir}/base.rpm" "${tmpdir}/image.rpm" > "${tmpdir}/rpm.removed"

base_count="$(wc -l < "${tmpdir}/base.rpm")"
image_count="$(wc -l < "${tmpdir}/image.rpm")"
in_image "${IMAGE}" 'cat /usr/share/wraindrock/delta.json' > "${tmpdir}/delta.json"

if [[ ! -s ${tmpdir}/rpm.removed ]] \
    && python3 - "${tmpdir}/delta.json" "${tmpdir}/rpm.added" "${tmpdir}/rpm.removed" <<'PY'
import json
import sys

delta_path, added_path, removed_path = sys.argv[1:4]
delta = json.load(open(delta_path))
added = [line.strip() for line in open(added_path) if line.strip()]
removed = [line.strip() for line in open(removed_path) if line.strip()]
assert delta["schema"] == 2, delta
assert delta["rpm"]["removed"] == [], delta["rpm"]["removed"]
assert set(delta["rpm"]["added"]) == set(added), (
    "declared", sorted(delta["rpm"]["added"]), "actual", sorted(added)
)
assert removed == [], removed
names = {"clash-verge", "helium-bin", "rayburst", "sing-box"}
assert len(added) == len(names), added
for name in names:
    assert any(entry.startswith(name + "-") for entry in added), (name, added)
PY
then
    pass "RPM set is the base plus exactly the declared additions (${base_count} -> ${image_count})"
else
    fail "RPM set differs beyond the declared additions (base ${base_count}, image ${image_count})"
    head -40 "${tmpdir}/rpm.added" || true
fi

# --- os-release -------------------------------------------------------------
in_image "${BASE}" 'cat /usr/lib/os-release' > "${tmpdir}/base-os-release"
in_image "${IMAGE}" 'cat /usr/lib/os-release' > "${tmpdir}/image-os-release"

version_id="$(sed -n 's/^VERSION_ID=//p' "${tmpdir}/image-os-release" | tail -n 1)"
[[ -n ${version_id} ]] || fail "image os-release has no VERSION_ID"

expect_line() {
    local description="$1" line="$2"
    if grep -qxF "${line}" "${tmpdir}/image-os-release"; then
        pass "${description}"
    else
        fail "${description}: expected ${line}"
    fi
}

expect_line "NAME is Wraindrock" 'NAME="Wraindrock"'
if grep -Eq '^PRETTY_NAME="Wraindrock \(Version: [0-9][^"]*\)"$' \
        "${tmpdir}/image-os-release"; then
    pass "PRETTY_NAME is branded and keeps the base version"
else
    fail "PRETTY_NAME is not a branded Bluefin string"
fi
expect_line "ID stays bluefin for uBlue tooling" 'ID=bluefin'
expect_line "ID_LIKE is fedora" 'ID_LIKE="fedora"'
expect_line "LOGO points at the Wraindrock icon" 'LOGO=wraindrock-logo-icon'
expect_line "DEFAULT_HOSTNAME is wraindrock" 'DEFAULT_HOSTNAME="wraindrock"'
expect_line "HOME_URL points at the project" \
    'HOME_URL="https://github.com/Wraindrock/wraindrock-linux"'
expect_line "DOCUMENTATION_URL points at the install guide" \
    'DOCUMENTATION_URL="https://github.com/Wraindrock/wraindrock-linux/blob/main/docs/install.md"'
expect_line "SUPPORT_URL points at the issue tracker" \
    'SUPPORT_URL="https://github.com/Wraindrock/wraindrock-linux/issues"'
expect_line "BUG_REPORT_URL points at the issue tracker" \
    'BUG_REPORT_URL="https://github.com/Wraindrock/wraindrock-linux/issues"'
expect_line "CPE_NAME keeps the Bluefin lineage" \
    "CPE_NAME=\"cpe:/o:universal-blue:bluefin:${version_id}\""
expect_line "VERSION_ID still tracks the base" "VERSION_ID=${version_id}"
base_variant_id="$(sed -n 's/^VARIANT_ID=//p' "${tmpdir}/base-os-release" | tail -n 1)"
expect_line "VARIANT_ID still tracks Bluefin DX" "VARIANT_ID=${base_variant_id}"

# The diff itself must stay inside the documented whitelist. This is what
# catches a branding step that quietly rewrites something else.
if python3 - "${tmpdir}/base-os-release" "${tmpdir}/image-os-release" <<'PY'
import sys


def parse(path):
    fields = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            key, sep, value = line.partition("=")
            assert sep == "=", line
            fields[key] = value
    return fields


base = parse(sys.argv[1])
image = parse(sys.argv[2])

changed = {
    "NAME", "PRETTY_NAME", "LOGO", "DEFAULT_HOSTNAME", "HOME_URL",
    "DOCUMENTATION_URL", "SUPPORT_URL", "BUG_REPORT_URL",
}
added = set()

problems = []
for key, value in base.items():
    if key not in image:
        problems.append(f"removed {key}")
    elif image[key] != value and key not in changed:
        problems.append(f"unexpected change {key}: {value} -> {image[key]}")
for key in image:
    if key not in base and key not in added:
        problems.append(f"unexpected addition {key}")

if problems:
    print("\n".join(problems))
    sys.exit(1)
PY
then
    pass "only the whitelisted os-release keys differ"
else
    fail "os-release differs outside the delta whitelist"
fi

# --- delta manifest ---------------------------------------------------------
# delta.json was captured together with the RPM set above; validate that copy.
[[ -s ${tmpdir}/delta.json ]] || fail "delta manifest is missing"
if python3 - "${tmpdir}/delta.json" "${tmpdir}/image-os-release" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    delta = json.load(handle)

image = {}
with open(sys.argv[2], encoding="utf-8") as handle:
    for line in handle:
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        key, _, value = line.partition("=")
        image[key] = value.strip('"')

assert delta["schema"] == 2, delta
assert delta["base_image"], delta
assert delta["base_digest"], delta

changed = delta["os_release"]["changed"]
added = delta["os_release"].get("added", {})
assert set(changed) == {
    "NAME", "PRETTY_NAME", "LOGO", "DEFAULT_HOSTNAME", "HOME_URL",
    "DOCUMENTATION_URL", "SUPPORT_URL", "BUG_REPORT_URL",
}, changed
assert added == {}, added
for key, value in changed.items():
    assert image[key] == value, f"delta says {key}={value!r}, image has {image[key]!r}"
assert image["ID_LIKE"] == "fedora", image

assert delta["files"]["modified"] == [
    "/usr/lib/os-release",
    "/usr/share/glib-2.0/schemas/gschemas.compiled",
    "/etc/plymouth/plymouthd.conf",
    "/usr/share/rpm/rpmdb.sqlite",
    "/opt",
], delta["files"]
expected_added = {
    "/usr/share/icons/hicolor/scalable/apps/wraindrock-logo-icon.svg",
    "/usr/share/pixmaps/wraindrock-gdm-logo.svg",
    "/usr/share/pixmaps/wraindrock-gdm-logo.png",
    "/usr/share/glib-2.0/schemas/zzzz-wraindrock.gschema.override",
    "/usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png",
    "/usr/share/wraindrock/base-os-release",
    "/usr/share/wraindrock/build-info.json",
    "/usr/share/wraindrock/delta.json",
    "/usr/share/plymouth/themes/wraindrock/wraindrock.plymouth",
    "/usr/share/plymouth/themes/wraindrock/background.png",
    "/usr/share/grub/themes/wraindrock/theme.txt",
    "/usr/share/grub/themes/wraindrock/background.png",
    "/usr/bin/wraindrock-grub-theme",
    "/usr/libexec/wraindrock-hostname-seed",
    "/usr/lib/systemd/system/wraindrock-hostname-seed.service",
    "/usr/lib/systemd/system/sysinit.target.wants/wraindrock-hostname-seed.service",
    "/usr/share/wraindrock/base-rpm-set",
    "/usr/share/flatpak/preinstall.d/wraindrock.preinstall",
    "/etc/xdg/mimeapps.list",
}
expected_added |= {
    f"/usr/share/plymouth/themes/wraindrock/animation-{i:04d}.png"
    for i in range(1, 31)
}
assert set(delta["files"]["added"]) == expected_added, delta["files"]["added"]
PY
then
    pass "delta manifest matches the image"
else
    fail "delta manifest is missing, invalid, or out of sync"
fi

# Every file the image adds must be one the manifest declares, and every
# declared path must really exist. This is the added-file half of the delta
# invariant; a stray file cannot ride along unnoticed.
python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["files"]["added"]))' \
    "${tmpdir}/delta.json" > "${tmpdir}/added-files"
while IFS= read -r path; do
    if in_image "${IMAGE}" "test -s ${path}"; then
        pass "declared added file present: ${path}"
    else
        fail "declared added file missing: ${path}"
    fi
done < "${tmpdir}/added-files"

# The build writes the RPM database (the pinned packages are added), so the sqlite
# sidecars cannot stay byte-identical to the base. A clean rpm exit checkpoints
# the WAL; require an empty WAL and keep the sidecars the base ships, because
# rpm on a read-only /usr relies on the pre-created -shm and -wal files.
wal_size="$(in_image "${IMAGE}" "stat -c %s /usr/share/rpm/rpmdb.sqlite-wal")"
if [[ ${wal_size} == 0 ]]; then
    pass "RPM database WAL is checkpointed (0 bytes)"
else
    fail "RPM database WAL is not empty (${wal_size} bytes)"
fi
if in_image "${IMAGE}" "test -e /usr/share/rpm/rpmdb.sqlite-shm"; then
    pass "RPM database ships its sqlite shared-memory file"
else
    fail "RPM database is missing rpmdb.sqlite-shm"
fi

# --- software ---------------------------------------------------------------
preinstall=/usr/share/flatpak/preinstall.d/wraindrock.preinstall
if in_image "${IMAGE}" "test -s ${preinstall}"; then
    pass "first-boot Flatpak preinstall file is installed"
else
    fail "first-boot Flatpak preinstall file is missing"
fi
# The declaration lives in build_files/software/flatpaks.txt; the image must
# carry exactly that set.
flatpak_list="build_files/software/flatpaks.txt"
mapfile -t expected_apps < <(grep -v '^#' "${flatpak_list}" | sed '/^[[:space:]]*$/d')
preinstall_count="$(in_image "${IMAGE}" "grep -c '^\[Flatpak Preinstall ' ${preinstall}")"
if [[ ${preinstall_count} -eq ${#expected_apps[@]} ]]; then
    pass "preinstall file declares ${preinstall_count} Flatpaks"
else
    fail "preinstall file declares ${preinstall_count} Flatpaks (expected ${#expected_apps[@]})"
fi
for app in "${expected_apps[@]}"; do
    if in_image "${IMAGE}" "grep -Fxq '[Flatpak Preinstall ${app}]' ${preinstall}"; then
        :
    else
        fail "preinstall file is missing ${app}"
    fi
done
pass "preinstall file lists every app in flatpaks.txt"
if in_image "${IMAGE}" "grep -q 'org.mozilla.firefox' ${preinstall}"; then
    fail "the preinstall file installs Firefox, which the user asked to skip"
else
    pass "Firefox is not preinstalled"
fi

if in_image "${IMAGE}" \
    "grep -Fxq 'x-scheme-handler/https=helium.desktop' /etc/xdg/mimeapps.list"; then
    pass "Helium is the default for https"
else
    fail "Helium is not the default for https"
fi
if in_image "${IMAGE}" "test -x /usr/bin/helium && test -x /opt/helium/helium"; then
    pass "Helium browser binary is installed"
else
    fail "Helium browser binary is missing"
fi

# --- input method -----------------------------------------------------------
# IBus with the libpinyin engine is the declared default; Fcitx must not be
# present, because the two frameworks would fight over the same session.
im_sources="$(in_image "${IMAGE}" \
    'GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.input-sources sources' 2>/dev/null || true)"
if [[ ${im_sources} == *"'ibus', 'libpinyin'"* ]]; then
    pass "input method default is IBus with libpinyin (${im_sources})"
else
    fail "input method default is not IBus/libpinyin (${im_sources:-empty})"
fi
if in_image "${IMAGE}" "rpm -q ibus-libpinyin >/dev/null 2>&1"; then
    pass "ibus-libpinyin engine is installed"
else
    fail "ibus-libpinyin is missing"
fi
if in_image "${IMAGE}" "rpm -q google-noto-sans-cjk-fonts >/dev/null 2>&1"; then
    pass "CJK fonts are installed"
else
    fail "google-noto-sans-cjk-fonts is missing"
fi
if in_image "${IMAGE}" "rpm -q fcitx5 >/dev/null 2>&1"; then
    fail "fcitx5 is installed, but the default input method must be IBus"
else
    pass "no Fcitx packages are installed"
fi

# Expected versions come from the manifest, which build.sh derived from the
# pins it verified; compare them with what rpm actually installed.
python3 - "${tmpdir}/delta.json" <<'RPM_VERSIONS' > "${tmpdir}/rpm.versions"
import json
import sys

delta = json.load(open(sys.argv[1]))
names = ["clash-verge", "helium-bin", "rayburst", "sing-box"]
for entry in delta["rpm"]["added"]:
    for name in names:
        if entry.startswith(name + "-"):
            version = entry[len(name) + 1:]
            if version.endswith(".x86_64"):
                version = version[:-len(".x86_64")]
            print(f"{name}\t{version}")
RPM_VERSIONS
while IFS=$'\t' read -r name version; do
    installed="$(in_image "${IMAGE}" "rpm -q --qf '%{VERSION}-%{RELEASE}' ${name}")"
    if [[ ${installed} == "${version}" ]]; then
        pass "baked package present at the pinned version: ${name} ${installed}"
    else
        fail "baked package ${name} is ${installed}, expected ${version}"
    fi
done < "${tmpdir}/rpm.versions"

if in_image "${IMAGE}" \
    "grep -qx \"logo='/usr/share/pixmaps/wraindrock-gdm-logo.png'\" \
        /usr/share/glib-2.0/schemas/zzzz-wraindrock.gschema.override"; then
    pass "GDM logo override points at the Wraindrock wordmark"
else
    fail "GDM logo override is missing or wrong"
fi

if in_image "${IMAGE}" \
    'grep -aq wraindrock-gdm-logo /usr/share/glib-2.0/schemas/gschemas.compiled'; then
    pass "GDM logo override is compiled into the schema cache"
else
    fail "compiled schema cache does not contain the GDM logo override"
fi

# --- default wallpaper ------------------------------------------------------
wallpaper=/usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png
if in_image "${IMAGE}" "test -s ${wallpaper}"; then
    pass "default wallpaper is installed"
else
    fail "default wallpaper is missing"
fi

png_size="$(in_image "${IMAGE}" "stat -c %s ${wallpaper} 2>/dev/null || true")"
png_dims="$(in_image "${IMAGE}" "od -An -tu4 --endian=big -j16 -N8 ${wallpaper} 2>/dev/null || true")"
read -r png_w png_h <<<"${png_dims}"
if [[ ${png_size:-0} -ge 50000 ]]; then
    pass "default wallpaper is a real image (${png_size} bytes)"
else
    fail "default wallpaper is suspiciously small (${png_size:-0} bytes)"
fi
if [[ ${png_w:-0} -eq 3840 && ${png_h:-0} -eq 2160 ]]; then
    pass "default wallpaper is 3840x2160"
else
    fail "default wallpaper is ${png_w:-?}x${png_h:-?}, want 3840x2160"
fi

if in_image "${IMAGE}" \
    "grep -qxF \"picture-uri='file://${wallpaper}'\" \
        /usr/share/glib-2.0/schemas/zzzz-wraindrock.gschema.override" &&
   in_image "${IMAGE}" \
    "grep -qxF \"picture-uri-dark='file://${wallpaper}'\" \
        /usr/share/glib-2.0/schemas/zzzz-wraindrock.gschema.override"; then
    pass "wallpaper override sets both day and dark defaults"
else
    fail "wallpaper override is missing or wrong"
fi

if in_image "${IMAGE}" \
    'grep -aq wraindrock-wallpaper /usr/share/glib-2.0/schemas/gschemas.compiled'; then
    pass "wallpaper override is compiled into the schema cache"
else
    fail "compiled schema cache does not contain the wallpaper override"
fi

for key in picture-uri picture-uri-dark; do
    want="'file://${wallpaper}'"
    got="$(in_image "${IMAGE}" \
        "GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.background ${key}" \
        2>/dev/null || true)"
    if [[ ${got} == "${want}" ]]; then
        pass "default ${key} is the Wraindrock wallpaper"
    else
        fail "default ${key} is ${got:-<unset>}, want ${want}"
    fi
done

# --- Plymouth boot splash ---------------------------------------------------
plymouth_dir=/usr/share/plymouth/themes/wraindrock
theme_file=${plymouth_dir}/wraindrock.plymouth

if in_image "${IMAGE}" "test -s ${theme_file}"; then
    pass "Plymouth theme file is installed"
else
    fail "Plymouth theme file is missing"
fi

if in_image "${IMAGE}" "grep -qx 'ModuleName=two-step' ${theme_file}"; then
    pass "Plymouth theme uses the two-step plugin (shipped by the base)"
else
    fail "Plymouth theme does not use the two-step plugin"
fi

if in_image "${IMAGE}" "grep -qx 'ImageDir=${plymouth_dir}' ${theme_file}"; then
    pass "Plymouth theme points at its own asset directory"
else
    fail "Plymouth theme ImageDir is missing or wrong"
fi

if in_image "${IMAGE}" "grep -qx 'UseProgressBar=true' ${theme_file}"; then
    pass "Plymouth theme keeps progress bars for offline updates"
else
    fail "Plymouth theme dropped the update progress bar"
fi

if in_image "${IMAGE}" "grep -qx 'Theme=wraindrock' /etc/plymouth/plymouthd.conf"; then
    pass "Plymouth daemon config selects the Wraindrock theme"
else
    fail "Plymouth daemon config does not select the Wraindrock theme"
fi

if in_image "${IMAGE}" "test -s ${plymouth_dir}/background.png"; then
    pass "Plymouth background is installed"
else
    fail "Plymouth background is missing"
fi

plymouth_bg_dims="$(in_image "${IMAGE}" \
    "od -An -tu4 --endian=big -j16 -N8 ${plymouth_dir}/background.png 2>/dev/null || true")"
read -r plymouth_bg_w plymouth_bg_h <<<"${plymouth_bg_dims}"
if [[ ${plymouth_bg_w:-0} -eq 1920 && ${plymouth_bg_h:-0} -eq 1080 ]]; then
    pass "Plymouth background is 1920x1080"
else
    fail "Plymouth background is ${plymouth_bg_w:-?}x${plymouth_bg_h:-?}, want 1920x1080"
fi

plymouth_frames="$(in_image "${IMAGE}" \
    "ls ${plymouth_dir}/animation-*.png 2>/dev/null | wc -l" 2>/dev/null || true)"
if [[ ${plymouth_frames:-0} -eq 30 ]]; then
    pass "Plymouth animation has 30 frames"
else
    fail "Plymouth animation has ${plymouth_frames:-0} frames, want 30"
fi

if in_image "${IMAGE}" 'set -e
    for f in /usr/share/plymouth/themes/wraindrock/animation-*.png; do
        sig=$(head -c 8 "$f" | od -An -tx1 | tr -d " \n")
        [ "$sig" = 89504e470d0a1a0a ] || exit 1
    done'; then
    pass "every Plymouth animation frame is a valid PNG"
else
    fail "a Plymouth animation frame is not a valid PNG"
fi

plymouth_frame_dims="$(in_image "${IMAGE}" \
    "od -An -tu4 --endian=big -j16 -N8 ${plymouth_dir}/animation-0001.png 2>/dev/null || true")"
read -r plymouth_frame_w plymouth_frame_h <<<"${plymouth_frame_dims}"
if [[ ${plymouth_frame_w:-0} -eq 256 && ${plymouth_frame_h:-0} -eq 256 ]]; then
    pass "Plymouth animation frames are 256x256"
else
    fail "Plymouth animation frame is ${plymouth_frame_w:-?}x${plymouth_frame_h:-?}, want 256x256"
fi

plymouth_themes="$(in_image "${IMAGE}" 'plymouth-set-default-theme -l 2>/dev/null || true')"
if grep -qx 'wraindrock' <<<"${plymouth_themes}"; then
    pass "plymouth-set-default-theme lists the Wraindrock theme"
else
    fail "plymouth-set-default-theme does not list wraindrock: ${plymouth_themes:-<none>}"
fi

# rpm must agree that the only tracked file we changed is os-release.
# /usr/lib/os-release belongs to the variant identity package, not to
# fedora-release-common. Look the package name up rather than hard-coding it:
# base packaging drift in a future Bluefin release then fails with a clear
# message instead of a puzzling diff.
#
# The mtime check is disabled: image layers store mtime 0 for files that are
# hardlinks into the ostree repo, while rpm headers record the package build
# time. A plain `rpm -V` would therefore report a T flag for every tracked file
# of the package, drowning out the single content change we actually made.
identity_package="$(in_image "${IMAGE}" 'rpm -q --whatprovides /usr/lib/os-release' || true)"
if [[ -n ${identity_package} ]]; then
    pass "release identity package owns /usr/lib/os-release (${identity_package})"
else
    fail "could not determine which package owns /usr/lib/os-release"
fi

if rpm_verify="$(in_image "${IMAGE}" "rpm -V --nomtime ${identity_package} || true")"; then
    verify_lines="$(printf '%s\n' "${rpm_verify}" | grep -c . || true)"
    if [[ ${verify_lines} -eq 1 ]] && grep -q '/usr/lib/os-release' <<<"${rpm_verify}"; then
        pass "rpm sees exactly one modified file: /usr/lib/os-release"
    else
        fail "rpm verification reported unexpected changes: ${rpm_verify:-<none>}"
    fi
else
    fail "could not run rpm verification"
fi

# --- GRUB boot menu theme ---------------------------------------------------
# The image ships an opt-in helper because bootc images cannot rewrite
# /boot/grub2/grub.cfg (bootupd installs it as a static config). Exercise the
# helper against throwaway boot trees inside the image.
if in_image "${IMAGE}" 'wraindrock-grub-theme status --boot-dir /nonexistent' > /dev/null; then
    pass "GRUB theme helper handles a missing GRUB directory"
else
    fail "GRUB theme helper failed on a missing directory"
fi

if grub_dims="$(in_image "${IMAGE}" 'od -An -tu4 --endian=big -j16 -N8 /usr/share/grub/themes/wraindrock/background.png' 2>/dev/null || true)"; then
    read -r grub_w grub_h <<<"${grub_dims}"
    if [[ ${grub_w:-} == 1920 && ${grub_h:-} == 1080 ]]; then
        pass "GRUB theme background is 1920x1080"
    else
        fail "GRUB theme background is ${grub_w:-?}x${grub_h:-?}, want 1920x1080"
    fi
else
    fail "could not read the GRUB theme background"
fi

grub_test_script='set -eu
fixture=$(mktemp -d)
mkdir -p "$fixture/grub2"
printf "insmod blscfg\nblscfg\nif [ -f \$prefix/custom.cfg ]; then source \$prefix/custom.cfg; fi\n" > "$fixture/grub2/grub.cfg"
wraindrock-grub-theme enable --boot-dir "$fixture" > /dev/null
test -s "$fixture/grub2/themes/wraindrock/theme.txt"
test -s "$fixture/grub2/themes/wraindrock/background.png"
test -s "$fixture/grub2/themes/wraindrock/unicode.pf2"
grep -q "loadfont \${prefix}/themes/wraindrock/unicode.pf2" "$fixture/grub2/custom.cfg"
grep -q "set theme=\${prefix}/themes/wraindrock/theme.txt" "$fixture/grub2/custom.cfg"
wraindrock-grub-theme status --boot-dir "$fixture" | grep -q "managed by wraindrock-grub-theme"
wraindrock-grub-theme enable --boot-dir "$fixture" > /dev/null
printf "user snippet\n" > "$fixture/grub2/custom.cfg"
if wraindrock-grub-theme enable --boot-dir "$fixture" > /dev/null 2>&1; then exit 1; fi
grep -qx "user snippet" "$fixture/grub2/custom.cfg"
fixture2=$(mktemp -d)
mkdir -p "$fixture2/grub2"
printf "blscfg\n" > "$fixture2/grub2/grub.cfg"
if wraindrock-grub-theme enable --boot-dir "$fixture2" > /dev/null 2>&1; then exit 1; fi
fixture3=$(mktemp -d)
mkdir -p "$fixture3/grub2"
printf "if [ -f \$prefix/custom.cfg ]; then source \$prefix/custom.cfg; fi\n" > "$fixture3/grub2/grub.cfg"
wraindrock-grub-theme enable --boot-dir "$fixture3" > /dev/null
if wraindrock-grub-theme disable --boot-dir "$fixture3" < /dev/null > /dev/null 2>&1; then exit 1; fi
wraindrock-grub-theme disable --yes --boot-dir "$fixture3" > /dev/null
test ! -e "$fixture3/grub2/custom.cfg"
test ! -e "$fixture3/grub2/themes/wraindrock"'
if in_image "${IMAGE}" "${grub_test_script}"; then
    pass "GRUB theme helper: enable, idempotency, refusals, disable"
else
    fail "GRUB theme helper behavior is wrong"
fi

# --- Hostname seeding -------------------------------------------------------
# A fresh install inherits the base deployment's /etc and comes up as "fedora"
# even though os-release carries DEFAULT_HOSTNAME. The image ships a one-shot
# first-boot unit; test its file wiring and its behavior against a fixture.
seed_test_script='set -eu
unit=/usr/lib/systemd/system/wraindrock-hostname-seed.service
want=/usr/lib/systemd/system/sysinit.target.wants/wraindrock-hostname-seed.service
test -x /usr/libexec/wraindrock-hostname-seed
grep -qx "ExecStart=/usr/libexec/wraindrock-hostname-seed" "$unit"
grep -qx "ConditionPathExists=!/var/lib/wraindrock/hostname-seeded" "$unit"
grep -qx "WantedBy=sysinit.target" "$unit"
test -L "$want"
test "$(readlink -f "$want")" = "$(readlink -f "$unit")"
fixture=$(mktemp -d)
mkdir -p "$fixture/state"
printf "%s\n" "NAME=\"Wraindrock\"" "DEFAULT_HOSTNAME=\"wraindrock\"" > "$fixture/os-release"
printf "fedora\n" > "$fixture/hostname"
sed -e "s|/usr/lib/os-release|$fixture/os-release|" \
    -e "s|/etc/hostname|$fixture/hostname|" \
    -e "s|/var/lib/wraindrock|$fixture/state|" \
    /usr/libexec/wraindrock-hostname-seed > "$fixture/seed"
chmod +x "$fixture/seed"
"$fixture/seed"
test "$(cat "$fixture/hostname")" = wraindrock
test -f "$fixture/state/hostname-seeded"
printf "myhost\n" > "$fixture/hostname"
rm -f "$fixture/state/hostname-seeded"
"$fixture/seed"
test "$(cat "$fixture/hostname")" = myhost'
if in_image "${IMAGE}" "${seed_test_script}"; then
    pass "hostname seed unit is wired and only replaces the base default"
else
    fail "hostname seed unit is missing or behaves destructively"
fi

# --- Provenance -------------------------------------------------------------
in_image "${IMAGE}" 'cat /usr/share/wraindrock/base-os-release' \
    > "${tmpdir}/image-base-os-release"
if diff -u "${tmpdir}/base-os-release" "${tmpdir}/image-base-os-release" > /dev/null; then
    pass "pristine base os-release preserved"
else
    fail "the preserved base os-release does not match the real base"
fi

in_image "${IMAGE}" 'cat /usr/share/wraindrock/build-info.json' \
    > "${tmpdir}/build-info.json"
if python3 - "${tmpdir}/build-info.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    info = json.load(handle)

assert info["schema"] == 1, info
assert info["identity"] == "wraindrock", info
assert info["parity"].startswith("bluefin-dx-"), info
assert info["rpm_count"] > 0, info
assert len(info["rpm_set_sha256"]) == 64, info
PY
then
    pass "build-info.json is valid and complete"
else
    fail "build-info.json is invalid or incomplete"
fi

# --- Inherited bootc contract ----------------------------------------------
labels="$("${ENGINE}" image inspect "${IMAGE}" --format '{{json .Labels}}')"
if python3 - "${labels}" <<'PY'
import json
import sys

labels = json.loads(sys.argv[1]) or {}
assert labels.get("containers.bootc") == "1", labels
assert labels.get("ostree.bootable") == "true", labels
assert labels.get("org.wraindrock.base.image"), labels
PY
then
    pass "inherited bootc labels are intact"
else
    fail "bootc labels are missing: ${labels}"
fi

image_cmd="$("${ENGINE}" image inspect "${IMAGE}" --format '{{json .Config.Cmd}}')"
if [[ ${image_cmd} == '["/sbin/init"]' ]]; then
    pass "image command is /sbin/init"
else
    fail "image command is ${image_cmd}, want [\"/sbin/init\"]"
fi

if in_image "${IMAGE}" 'bootc --version'; then
    pass "bootc CLI is present"
else
    fail "bootc CLI is missing"
fi

# --- drivers and virtualisation (inherited from the NVIDIA base) ------------
if in_image "${IMAGE}" \
    'rpm -q nvidia-driver nvidia-container-toolkit kmod-nvidia >/dev/null 2>&1 \
        && test -x /usr/bin/nvidia-smi'; then
    pass "NVIDIA driver stack is present"
else
    fail "NVIDIA driver stack is missing"
fi
if in_image "${IMAGE}" \
    'rpm -q qemu-system-x86-core libvirt-daemon-kvm virt-manager >/dev/null 2>&1'; then
    pass "QEMU/KVM, libvirt and virt-manager are present"
else
    fail "the virtualisation stack is incomplete"
fi
if in_image "${IMAGE}" 'rpm -q incus docker-ce distrobox >/dev/null 2>&1'; then
    pass "Incus, Docker and Distrobox are present"
else
    fail "the container stack is incomplete"
fi

echo
if [[ ${failures} -ne 0 ]]; then
    printf '%s parity check(s) failed\n' "${failures}" >&2
    exit 1
fi
printf 'parity holds: Bluefin DX %s package set, branded, delta recorded\n' \
    "${version_id}"
