#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Parity test for the branded image.
#
# v0.1 asserted "byte identical to Fedora Silverblue". v0.2 keeps the strong
# part of that promise and makes the weaker part explicit:
#
#   * the RPM set is still identical, package for package;
#   * /usr/lib/os-release may differ only in the identity keys listed in the
#     image's own delta manifest, with exactly the recorded values;
#   * every added file is one the delta manifest declares;
#   * the GDM logo and wallpaper overrides are compiled into the schema cache;
#   * the Plymouth boot splash is installed, selected, and complete.
#
#   tests/parity.sh quay.io/fedora/fedora-silverblue:44 \
#                   localhost/wrainrock-linux:44
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
rpm_query='rpm -qa --qf "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n" | LC_ALL=C sort'
in_image "${BASE}" "${rpm_query}" > "${tmpdir}/base.rpm"
in_image "${IMAGE}" "${rpm_query}" > "${tmpdir}/image.rpm"

base_count="$(wc -l < "${tmpdir}/base.rpm")"
image_count="$(wc -l < "${tmpdir}/image.rpm")"
if diff -u "${tmpdir}/base.rpm" "${tmpdir}/image.rpm" > "${tmpdir}/rpm.diff"; then
    pass "RPM set identical (${image_count} packages)"
else
    fail "RPM set differs (base ${base_count}, image ${image_count})"
    head -40 "${tmpdir}/rpm.diff"
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

expect_line "NAME is Wrainrock Linux" 'NAME="Wrainrock Linux"'
if grep -Eq '^PRETTY_NAME="Wrainrock Linux [0-9][^"]* \(Silverblue\)"$' \
        "${tmpdir}/image-os-release"; then
    pass "PRETTY_NAME is branded and keeps the base version"
else
    fail "PRETTY_NAME is not a branded Silverblue string"
fi
expect_line "ID is wrainrock" 'ID=wrainrock'
expect_line "ID_LIKE is fedora" 'ID_LIKE="fedora"'
expect_line "LOGO points at the Wrainrock icon" 'LOGO=wrainrock-logo-icon'
expect_line "DEFAULT_HOSTNAME is wrainrock" 'DEFAULT_HOSTNAME="wrainrock"'
expect_line "HOME_URL points at the project" \
    'HOME_URL="https://github.com/Wraindrock/wrainrock-linux"'
expect_line "DOCUMENTATION_URL points at the install guide" \
    'DOCUMENTATION_URL="https://github.com/Wraindrock/wrainrock-linux/blob/main/docs/install.md"'
expect_line "SUPPORT_URL points at the issue tracker" \
    'SUPPORT_URL="https://github.com/Wraindrock/wrainrock-linux/issues"'
expect_line "BUG_REPORT_URL points at the issue tracker" \
    'BUG_REPORT_URL="https://github.com/Wraindrock/wrainrock-linux/issues"'
expect_line "CPE_NAME identifies Wrainrock" \
    "CPE_NAME=\"cpe:/o:wraindrock:wrainrock_linux:${version_id}\""
expect_line "VERSION_ID still tracks the base" "VERSION_ID=${version_id}"
expect_line "VARIANT_ID still tracks Silverblue" 'VARIANT_ID=silverblue'

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
    "NAME", "PRETTY_NAME", "ID", "LOGO", "DEFAULT_HOSTNAME", "HOME_URL",
    "DOCUMENTATION_URL", "SUPPORT_URL", "BUG_REPORT_URL", "CPE_NAME",
}
added = {"ID_LIKE"}

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
in_image "${IMAGE}" 'cat /usr/share/wrainrock/delta.json' > "${tmpdir}/delta.json"
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

assert delta["schema"] == 1, delta
assert delta["base_image"], delta
assert delta["base_digest"], delta

changed = delta["os_release"]["changed"]
added = delta["os_release"]["added"]
assert set(changed) == {
    "NAME", "PRETTY_NAME", "ID", "LOGO", "DEFAULT_HOSTNAME", "HOME_URL",
    "DOCUMENTATION_URL", "SUPPORT_URL", "BUG_REPORT_URL", "CPE_NAME",
}, changed
assert added == {"ID_LIKE": "fedora"}, added
for key, value in changed.items():
    assert image[key] == value, f"delta says {key}={value!r}, image has {image[key]!r}"
assert image["ID_LIKE"] == "fedora", image

assert delta["files"]["modified"] == [
    "/usr/lib/os-release",
    "/usr/share/glib-2.0/schemas/gschemas.compiled",
    "/etc/plymouth/plymouthd.conf",
], delta["files"]
expected_added = {
    "/usr/share/icons/hicolor/scalable/apps/wrainrock-logo-icon.svg",
    "/usr/share/pixmaps/wrainrock-gdm-logo.svg",
    "/usr/share/pixmaps/wrainrock-gdm-logo.png",
    "/usr/share/glib-2.0/schemas/zz-wrainrock.gschema.override",
    "/usr/share/backgrounds/wrainrock/wrainrock-wallpaper.png",
    "/usr/share/wrainrock/base-os-release",
    "/usr/share/wrainrock/build-info.json",
    "/usr/share/wrainrock/delta.json",
    "/usr/share/plymouth/themes/wrainrock/wrainrock.plymouth",
    "/usr/share/plymouth/themes/wrainrock/background.png",
    "/usr/share/grub/themes/wrainrock/theme.txt",
    "/usr/share/grub/themes/wrainrock/background.png",
    "/usr/bin/wrainrock-grub-theme",
}
expected_added |= {
    f"/usr/share/plymouth/themes/wrainrock/animation-{i:04d}.png"
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

# The base ships sqlite's sidecar files next to the RPM database. The build
# must not touch them: equal checksums prove the image inherited them instead
# of copying them up with new content (or adding them where the base has none).
for sidecar in .rpm.lock rpmdb.sqlite-wal rpmdb.sqlite-shm; do
    base_sum="$(in_image "${BASE}" "sha256sum /usr/share/rpm/${sidecar} 2>/dev/null || true")"
    image_sum="$(in_image "${IMAGE}" "sha256sum /usr/share/rpm/${sidecar} 2>/dev/null || true")"
    if [[ -n ${base_sum} && ${base_sum} == "${image_sum}" ]]; then
        pass "rpm database sidecar untouched: ${sidecar}"
    elif [[ -z ${base_sum} && -z ${image_sum} ]]; then
        pass "rpm database sidecar absent in base and image: ${sidecar}"
    else
        fail "rpm database sidecar differs from the base: ${sidecar}"
    fi
done

echo "hostname file"
# buildah injects an empty /etc/hostname unless --no-hostname is used; an empty
# file tells systemd to ignore DEFAULT_HOSTNAME, so the installed host falls
# back to the kernel default (fedora) instead of wrainrock.
if in_image "${IMAGE}" 'test ! -e /etc/hostname'; then
    pass "image does not ship /etc/hostname (DEFAULT_HOSTNAME applies)"
else
    fail "image ships /etc/hostname, so DEFAULT_HOSTNAME will not apply"
fi

if in_image "${IMAGE}" \
    "grep -qx \"logo='/usr/share/pixmaps/wrainrock-gdm-logo.png'\" \
        /usr/share/glib-2.0/schemas/zz-wrainrock.gschema.override"; then
    pass "GDM logo override points at the Wrainrock wordmark"
else
    fail "GDM logo override is missing or wrong"
fi

if in_image "${IMAGE}" \
    'grep -aq wrainrock-gdm-logo /usr/share/glib-2.0/schemas/gschemas.compiled'; then
    pass "GDM logo override is compiled into the schema cache"
else
    fail "compiled schema cache does not contain the GDM logo override"
fi

# --- default wallpaper ------------------------------------------------------
wallpaper=/usr/share/backgrounds/wrainrock/wrainrock-wallpaper.png
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
        /usr/share/glib-2.0/schemas/zz-wrainrock.gschema.override" &&
   in_image "${IMAGE}" \
    "grep -qxF \"picture-uri-dark='file://${wallpaper}'\" \
        /usr/share/glib-2.0/schemas/zz-wrainrock.gschema.override"; then
    pass "wallpaper override sets both day and dark defaults"
else
    fail "wallpaper override is missing or wrong"
fi

if in_image "${IMAGE}" \
    'grep -aq wrainrock-wallpaper /usr/share/glib-2.0/schemas/gschemas.compiled'; then
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
        pass "default ${key} is the Wrainrock wallpaper"
    else
        fail "default ${key} is ${got:-<unset>}, want ${want}"
    fi
done

# --- Plymouth boot splash ---------------------------------------------------
plymouth_dir=/usr/share/plymouth/themes/wrainrock
theme_file=${plymouth_dir}/wrainrock.plymouth

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

if in_image "${IMAGE}" "grep -qx 'Theme=wrainrock' /etc/plymouth/plymouthd.conf"; then
    pass "Plymouth daemon config selects the Wrainrock theme"
else
    fail "Plymouth daemon config does not select the Wrainrock theme"
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
    for f in /usr/share/plymouth/themes/wrainrock/animation-*.png; do
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
if grep -qx 'wrainrock' <<<"${plymouth_themes}"; then
    pass "plymouth-set-default-theme lists the Wrainrock theme"
else
    fail "plymouth-set-default-theme does not list wrainrock: ${plymouth_themes:-<none>}"
fi

# rpm must agree that the only tracked file we changed is os-release.
# On Fedora 44, /usr/lib/os-release belongs to the variant identity package
# (fedora-release-identity-silverblue), not to fedora-release-common. Verify
# that rather than hard-coding an assumption; base packaging drift in a future
# Fedora release then fails with a clear message instead of a puzzling diff.
#
# The mtime check is disabled: image layers store mtime 0 for files that are
# hardlinks into the ostree repo, while rpm headers record the package build
# time. A plain `rpm -V` would therefore report a T flag for every tracked file
# of the package, drowning out the single content change we actually made.
identity_package=fedora-release-identity-silverblue
if owner="$(in_image "${IMAGE}" 'rpm -q --whatprovides /usr/lib/os-release')"; then
    if [[ ${owner} == "${identity_package}"-* ]]; then
        pass "release identity package owns /usr/lib/os-release (${owner})"
    else
        fail "unexpected owner of /usr/lib/os-release: ${owner}"
    fi
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
if in_image "${IMAGE}" 'wrainrock-grub-theme status --boot-dir /nonexistent' > /dev/null; then
    pass "GRUB theme helper handles a missing GRUB directory"
else
    fail "GRUB theme helper failed on a missing directory"
fi

if grub_dims="$(in_image "${IMAGE}" 'od -An -tu4 --endian=big -j16 -N8 /usr/share/grub/themes/wrainrock/background.png' 2>/dev/null || true)"; then
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
wrainrock-grub-theme enable --boot-dir "$fixture" > /dev/null
test -s "$fixture/grub2/themes/wrainrock/theme.txt"
test -s "$fixture/grub2/themes/wrainrock/background.png"
test -s "$fixture/grub2/themes/wrainrock/unicode.pf2"
grep -q "loadfont \${prefix}/themes/wrainrock/unicode.pf2" "$fixture/grub2/custom.cfg"
grep -q "set theme=\${prefix}/themes/wrainrock/theme.txt" "$fixture/grub2/custom.cfg"
wrainrock-grub-theme status --boot-dir "$fixture" | grep -q "managed by wrainrock-grub-theme"
wrainrock-grub-theme enable --boot-dir "$fixture" > /dev/null
printf "user snippet\n" > "$fixture/grub2/custom.cfg"
if wrainrock-grub-theme enable --boot-dir "$fixture" > /dev/null 2>&1; then exit 1; fi
grep -qx "user snippet" "$fixture/grub2/custom.cfg"
fixture2=$(mktemp -d)
mkdir -p "$fixture2/grub2"
printf "blscfg\n" > "$fixture2/grub2/grub.cfg"
if wrainrock-grub-theme enable --boot-dir "$fixture2" > /dev/null 2>&1; then exit 1; fi
fixture3=$(mktemp -d)
mkdir -p "$fixture3/grub2"
printf "if [ -f \$prefix/custom.cfg ]; then source \$prefix/custom.cfg; fi\n" > "$fixture3/grub2/grub.cfg"
wrainrock-grub-theme enable --boot-dir "$fixture3" > /dev/null
if wrainrock-grub-theme disable --boot-dir "$fixture3" < /dev/null > /dev/null 2>&1; then exit 1; fi
wrainrock-grub-theme disable --yes --boot-dir "$fixture3" > /dev/null
test ! -e "$fixture3/grub2/custom.cfg"
test ! -e "$fixture3/grub2/themes/wrainrock"'
if in_image "${IMAGE}" "${grub_test_script}"; then
    pass "GRUB theme helper: enable, idempotency, refusals, disable"
else
    fail "GRUB theme helper behavior is wrong"
fi

# --- Provenance -------------------------------------------------------------
in_image "${IMAGE}" 'cat /usr/share/wrainrock/base-os-release' \
    > "${tmpdir}/image-base-os-release"
if diff -u "${tmpdir}/base-os-release" "${tmpdir}/image-base-os-release" > /dev/null; then
    pass "pristine base os-release preserved"
else
    fail "the preserved base os-release does not match the real base"
fi

in_image "${IMAGE}" 'cat /usr/share/wrainrock/build-info.json' \
    > "${tmpdir}/build-info.json"
if python3 - "${tmpdir}/build-info.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    info = json.load(handle)

assert info["schema"] == 1, info
assert info["identity"] == "wrainrock", info
assert info["parity"].startswith("fedora-silverblue-"), info
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
assert labels.get("org.wrainrock.base.image"), labels
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

echo
if [[ ${failures} -ne 0 ]]; then
    printf '%s parity check(s) failed\n' "${failures}" >&2
    exit 1
fi
printf 'parity holds: Fedora Silverblue %s package set, branded, delta recorded\n' \
    "${version_id}"
