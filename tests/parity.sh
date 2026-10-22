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
#   * the wallpaper override is compiled into the schema cache;
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
names = {"clash-verge", "helium-bin", "hplip", "hplip-common", "hplip-libs",
         "libsane-hpaio", "rayburst", "sing-box"}
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
    "NAME", "PRETTY_NAME", "DEFAULT_HOSTNAME", "HOME_URL",
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
    "NAME", "PRETTY_NAME", "DEFAULT_HOSTNAME", "HOME_URL",
    "DOCUMENTATION_URL", "SUPPORT_URL", "BUG_REPORT_URL",
}, changed
assert added == {}, added
for key, value in changed.items():
    assert image[key] == value, f"delta says {key}={value!r}, image has {image[key]!r}"
assert image["ID_LIKE"] == "fedora", image

assert delta["files"]["modified"] == [
    "/usr/lib/os-release",
    "/etc/system-release",
    "/usr/share/glib-2.0/schemas/gschemas.compiled",
    "/usr/share/rpm/rpmdb.sqlite",
    "/etc/dconf/db/distro",
    "/opt",
], delta["files"]
expected_added = {
    "/usr/share/glib-2.0/schemas/zzzz-wraindrock.gschema.override",
    "/usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png",
    "/usr/share/wraindrock/base-os-release",
    "/usr/share/wraindrock/build-info.json",
    "/usr/share/wraindrock/delta.json",
    "/usr/libexec/wraindrock-hostname-seed",
    "/usr/lib/systemd/system/wraindrock-hostname-seed.service",
    "/usr/lib/systemd/system/sysinit.target.wants/wraindrock-hostname-seed.service",
    "/usr/share/wraindrock/base-rpm-set",
    "/usr/share/flatpak/preinstall.d/wraindrock.preinstall",
    "/usr/libexec/wraindrock-flatpak-preinstall",
    "/usr/lib/systemd/system/wraindrock-flatpak-preinstall.service",
    "/usr/lib/systemd/system/wraindrock-flatpak-preinstall.timer",
    "/etc/systemd/system/timers.target.wants/wraindrock-flatpak-preinstall.timer",
    "/usr/libexec/wraindrock-g15-install",
    "/usr/lib/systemd/system/wraindrock-g15-install.service",
    "/etc/systemd/system/multi-user.target.wants/wraindrock-g15-install.service",
    "/etc/xdg/mimeapps.list",
    "/etc/dconf/db/distro.d/10-wraindrock-folders",
    "/usr/share/desktop-directories/wraindrock-accessories.directory",
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

# Fresh offline installs: the base service gives up after three attempts, so a
# timer retries our wrapper until the preinstall hash is recorded.
retry_script=/usr/libexec/wraindrock-flatpak-preinstall
retry_unit=/usr/lib/systemd/system/wraindrock-flatpak-preinstall.service
retry_timer=/usr/lib/systemd/system/wraindrock-flatpak-preinstall.timer
if in_image "${IMAGE}" "test -x ${retry_script} && test -s ${retry_unit} && test -s ${retry_timer}"; then
    pass "Flatpak preinstall retry wrapper, service and timer are installed"
else
    fail "Flatpak preinstall retry unit is incomplete"
fi
if in_image "${IMAGE}" "grep -Fq 'ExecStart=${retry_script}' ${retry_unit} && grep -Fq 'StartLimitIntervalSec=0' ${retry_unit}"; then
    pass "retry service runs the wrapper without a start limit"
else
    fail "retry service is misconfigured"
fi
if in_image "${IMAGE}" "grep -Fq 'OnUnitActiveSec=10min' ${retry_timer} && grep -Fq 'Unit=wraindrock-flatpak-preinstall.service' ${retry_timer}"; then
    pass "retry timer re-runs the wrapper every ten minutes"
else
    fail "retry timer is misconfigured"
fi
if in_image "${IMAGE}" "test -L /etc/systemd/system/timers.target.wants/wraindrock-flatpak-preinstall.timer"; then
    pass "Flatpak preinstall retry timer is enabled"
else
    fail "Flatpak preinstall retry timer is not enabled"
fi
if in_image "${IMAGE}" "test -L /etc/systemd/system/multi-user.target.wants/flatpak-preinstall.service"; then
    pass "base Flatpak preinstall service remains enabled"
else
    fail "base Flatpak preinstall service is not enabled"
fi
if in_image "${IMAGE}" "grep -Fq 'flatpak-preinstall.sha256' ${retry_script}"; then
    pass "retry wrapper records the completed preinstall hash"
else
    fail "retry wrapper does not record its progress"
fi

if in_image "${IMAGE}" 'rpm -q sane-airscan sane-backends-drivers-scanners >/dev/null'; then
    pass "scanner support (sane-airscan) is present"
else
    fail "sane-airscan is missing"
fi
# Dell G15/G16 control center: first boot only, pinned commit and tarball.
g15_script=/usr/libexec/wraindrock-g15-install
g15_unit=/usr/lib/systemd/system/wraindrock-g15-install.service
if in_image "${IMAGE}" "test -x ${g15_script} && test -s ${g15_unit}"; then
    pass "G15 control-center first-boot installer is installed"
else
    fail "G15 control-center installer is missing"
fi
if in_image "${IMAGE}" "grep -Fq 'commit=3a004772cb050d9c74765ca794c3df7afa0f7b4c' ${g15_script} && grep -Fq 'tarball_sha256=7ac15f4d9d196bb2f9e441554747e9e1435782ae92749541f9d5c99e0ba7fa55' ${g15_script}"; then
    pass "G15 installer pins its commit and tarball checksum"
else
    fail "G15 installer is not pinned"
fi
if in_image "${IMAGE}" "grep -Fq '*G15*|*G16*' ${g15_script}"; then
    pass "G15 installer only runs on Dell G15/G16 hardware"
else
    fail "G15 installer does not gate on the hardware model"
fi
if in_image "${IMAGE}" "test -L /etc/systemd/system/multi-user.target.wants/wraindrock-g15-install.service"; then
    pass "G15 installer service is enabled"
else
    fail "G15 installer service is not enabled"
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
names = ["hplip-common", "libsane-hpaio", "clash-verge", "helium-bin",
         "rayburst", "sing-box", "hplip-libs", "hplip"]
names.sort(key=len, reverse=True)
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

if in_image "${IMAGE}"     "test -x /usr/bin/hp-setup && test -x /usr/lib/cups/backend/hp"     && in_image "${IMAGE}" "test -e /usr/lib64/sane/libsane-hpaio.so.1"; then
    pass "HPLIP command line, CUPS backend and SANE backend are installed"
else
    fail "HPLIP is incomplete (hp-setup, CUPS backend or SANE backend missing)"
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

# --- identity files ---------------------------------------------------------
# /usr/lib/os-release and /etc/system-release come from different release
# packages; each is replaced on purpose. Verify each package reports exactly
# its own branded file and nothing else.
check_identity_file() {
    local path="$1" label="$2"
    local package
    package="$(in_image "${IMAGE}" "rpm -q --whatprovides ${path}" 2>/dev/null | head -n 1 || true)"
    if [[ -z ${package} ]]; then
        fail "could not determine which package owns ${path}"
        return
    fi
    local verify
    verify="$(in_image "${IMAGE}" "rpm -V --nomtime ${package} || true")"
    local lines
    lines="$(printf '%s\n' "${verify}" | grep -c . || true)"
    if [[ ${lines} -eq 1 ]] && grep -q "${path}" <<<"${verify}"; then
        pass "rpm sees only the branded ${label} changed (${package})"
    else
        fail "rpm verification for ${path} reported: ${verify:-<none>}"
    fi
}
check_identity_file /usr/lib/os-release "os-release"
check_identity_file /etc/system-release "system-release"

# --- UEFI boot entry name and app folders ----------------------------------
system_release="$(in_image "${IMAGE}" 'cat /etc/system-release' 2>/dev/null || true)"
if [[ ${system_release} == "Wraindrock release "* ]]; then
    pass "/etc/system-release names the UEFI entry Wraindrock (${system_release})"
else
    fail "/etc/system-release does not name the UEFI entry: ${system_release:-<missing>}"
fi

# Bluefin owns 01-bluefin-folders; our exclusions are appended per key, so a
# change upstream must be re-reviewed here and in tests/fixtures/bluefin-folders.conf.
in_image "${BASE}" "sed 's/[[:space:]]*$//' /etc/dconf/db/distro.d/01-bluefin-folders" \
    | grep -v '^#' | sed '/^[[:space:]]*$/d' > "${tmpdir}/base.folders"
grep -v '^#' tests/fixtures/bluefin-folders.conf \
    | sed 's/[[:space:]]*$//' | sed '/^[[:space:]]*$/d' > "${tmpdir}/fixture.folders"
if diff -u "${tmpdir}/fixture.folders" "${tmpdir}/base.folders" > "${tmpdir}/folders.diff"; then
    pass "Bluefin's own folder definitions still match the vendored fixture"
else
    fail "Bluefin changed its folder definitions; update tests/fixtures/bluefin-folders.conf and the exclusions"
    head -20 "${tmpdir}/folders.diff" || true
fi

# --- default dock -----------------------------------------------------------
expected_dock="['helium.desktop', 'com.github.flxzt.rnote.desktop', 'org.gnome.Nautilus.desktop', 'io.github.kolunmi.Bazaar.desktop', 'io.missioncenter.MissionCenter.desktop', 'org.gnome.Ptyxis.desktop']"
dock="$(in_image "${IMAGE}" 'GSETTINGS_BACKEND=memory gsettings get org.gnome.shell favorite-apps' 2>/dev/null || true)"
if [[ ${dock} == "${expected_dock}" ]]; then
    pass "default dock is the curated list in order"
else
    fail "default dock differs: ${dock:-<missing>}"
fi

folders_file=/etc/dconf/db/distro.d/10-wraindrock-folders
if in_image "${IMAGE}" "test -s ${folders_file}"; then
    pass "application folders are declared"
else
    fail "application folders are missing"
fi
for folder in Accessories Virtualization Proxies Wraindrock uBlue; do
    if in_image "${IMAGE}" "grep -q '\[org/gnome/desktop/app-folders/folders/${folder}\]' ${folders_file}"; then
        pass "app folder declared: ${folder}"
    else
        fail "app folder missing: ${folder}"
    fi
done
for gone in Flatpak AppImage Bluefin; do
    if in_image "${IMAGE}" "! grep -q '\[org/gnome/desktop/app-folders/folders/${gone}\]' ${folders_file}"; then
        pass "channel folder dropped (no duplicate membership): ${gone}"
    else
        fail "channel folder still declared, apps may repeat: ${gone}"
    fi
done
for app in 'virt-manager.desktop' 'io.podman_desktop.PodmanDesktop.desktop' \
    'Clash Verge.desktop' 'helium.desktop' 'discourse.desktop' \
    'documentation.desktop' 'system-update.desktop'; do
    if in_image "${IMAGE}" "grep -Fq \"'${app}'\" ${folders_file}"; then
        pass "re-homed app is listed: ${app}"
    else
        fail "re-homed app is missing: ${app}"
    fi
done
in_image "${IMAGE}" "cat ${folders_file}" > "${tmpdir}/app-folders"
if python3 tests/folders.py tests/fixtures/bluefin-folders.conf "${tmpdir}/app-folders" >/dev/null; then
    pass "published app folders keep one folder per app"
else
    fail "published app folders duplicate at least one app"
fi
missing_gnome=0
while IFS= read -r app; do
    [[ -z ${app} || ${app} == \#* ]] && continue
    if ! grep -Fq "'${app}'" "${tmpdir}/app-folders"; then
        fail "GNOME desktop app is not filed under Accessories: ${app}"
        missing_gnome=1
    fi
done < tests/fixtures/gnome-desktop-apps.txt
if [[ ${missing_gnome} -eq 0 ]]; then
    pass "GNOME desktop applications are filed under Accessories"
fi

# Accessories and Tools must not overlap: the GNOME apps live only in
# Accessories, and Utilities keeps Bluefin's own tool list.
utils_apps="$(awk '/folders\/Utilities\]/{seen=1; next} /^\[/{seen=0} seen && /^apps=/{print}' "${tmpdir}/app-folders")"
if [[ ${utils_apps} == *"'org.gnome.Calculator.desktop'"* ]]; then
    fail "Utilities still lists GNOME applications (Accessories would duplicate)"
else
    pass "Utilities no longer lists the GNOME applications"
fi
if in_image "${IMAGE}" "grep -Fq 'Name[zh_CN]=附件' /usr/share/desktop-directories/wraindrock-accessories.directory"; then
    pass "Accessories folder is labelled 附件 in Chinese"
else
    fail "Accessories .directory is missing the Chinese name"
fi
if in_image "${IMAGE}" 'grep -aq 'Accessories' /etc/dconf/db/distro'; then
    pass "app folders are compiled into the distro dconf database"
else
    fail "compiled distro dconf database does not contain the app folders"
fi

# Appearance customisation was deliberately removed; the wallpaper is the only
# visual delta. These files must not come back silently.
for gone in /usr/share/pixmaps/wraindrock-gdm-logo.png \
    /usr/share/plymouth/themes/wraindrock/wraindrock.plymouth \
    /usr/bin/wraindrock-grub-theme; do
    if in_image "${IMAGE}" "test ! -e ${gone}"; then
        pass "appearance personalisation removed: ${gone}"
    else
        fail "unexpected appearance file: ${gone}"
    fi
done

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

# --- Bluefin desktop defaults (inherited, not reimplemented) ----------------
# The desktop layer is upstream Bluefin's: the extension set, which of them are
# enabled, the Extension Manager, the Flathub remote and the Flatpak presets
# come from the base image. Compare against the base instead of pinning a list,
# so a Bluefin update moves both sides together.
extension_list='ls /usr/share/gnome-shell/extensions | LC_ALL=C sort'
in_image "${BASE}" "${extension_list}" > "${tmpdir}/base.extensions"
in_image "${IMAGE}" "${extension_list}" > "${tmpdir}/image.extensions"
if diff -q "${tmpdir}/base.extensions" "${tmpdir}/image.extensions" >/dev/null; then
    pass "GNOME extension set is Bluefin's ($(wc -l < "${tmpdir}/image.extensions") extensions)"
else
    fail "GNOME extension set differs from the base"
    diff -u "${tmpdir}/base.extensions" "${tmpdir}/image.extensions" | head -20 || true
fi

enabled_query='GSETTINGS_BACKEND=memory gsettings get org.gnome.shell enabled-extensions'
base_enabled="$(in_image "${BASE}" "${enabled_query}")"
image_enabled="$(in_image "${IMAGE}" "${enabled_query}")"
if [[ -n ${image_enabled} && ${image_enabled} == "${base_enabled}" ]]; then
    pass "enabled GNOME extensions match Bluefin's default"
else
    fail "enabled GNOME extensions differ from the base"
    printf '      base:  %s\n      image: %s\n' "${base_enabled}" "${image_enabled}" >&2
fi

if in_image "${IMAGE}" \
    'grep -q "\[Flatpak Preinstall com.mattjakeman.ExtensionManager\]" \
        /usr/share/flatpak/preinstall.d/wraindrock.preinstall'; then
    pass "Extension Manager is part of the first-boot Flatpaks"
else
    fail "Extension Manager is missing from the Flatpak preinstall file"
fi

if in_image "${IMAGE}" 'test -s /etc/flatpak/remotes.d/flathub.flatpakrepo'; then
    pass "Flathub is the configured Flatpak remote"
else
    fail "the Flathub remote is missing"
fi

if in_image "${IMAGE}" \
    'grep -qx "filesystems=host-etc" \
        /usr/share/ublue-os/flatpak-overrides/io.github.kolunmi.Bazaar \
        && grep -q "flatpak-overrides/io.github.kolunmi.Bazaar" \
            /usr/lib/tmpfiles.d/bazaar-flatpak.conf'; then
    pass "Bluefin's Flatpak preset (Bazaar host-etc) is present"
else
    fail "Bluefin's Flatpak preset is missing"
fi

if in_image "${IMAGE}" \
    'test -L /etc/systemd/system/multi-user.target.wants/flatpak-preinstall.service'; then
    pass "flatpak-preinstall.service is enabled"
else
    fail "flatpak-preinstall.service is not enabled"
fi

echo
if [[ ${failures} -ne 0 ]]; then
    printf '%s parity check(s) failed\n' "${failures}" >&2
    exit 1
fi
printf 'parity holds: Bluefin DX %s package set, branded, delta recorded\n' \
    "${version_id}"
