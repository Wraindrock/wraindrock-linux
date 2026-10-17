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
#   * the GDM logo override is actually compiled into the schema cache.
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
], delta["files"]
expected_added = {
    "/usr/share/icons/hicolor/scalable/apps/wrainrock-logo-icon.svg",
    "/usr/share/pixmaps/wrainrock-gdm-logo.svg",
    "/usr/share/pixmaps/wrainrock-gdm-logo.png",
    "/usr/share/glib-2.0/schemas/zz-wrainrock.gschema.override",
    "/usr/share/wrainrock/base-os-release",
    "/usr/share/wrainrock/build-info.json",
    "/usr/share/wrainrock/delta.json",
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

# Builder scratch must not ship. A fresh container has no process that would
# create these, so their presence means the build leaked them into the layer.
for stray in \
    /usr/share/rpm/rpmdb.sqlite-wal \
    /usr/share/rpm/rpmdb.sqlite-shm \
    /usr/share/rpm/.rpm.lock; do
    if in_image "${IMAGE}" "test ! -e ${stray}"; then
        pass "no builder artifact: ${stray}"
    else
        fail "builder artifact leaked into the image: ${stray}"
    fi
done

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
