#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Parity test: the v0.1 image must be Fedora Silverblue 44, not merely boot
# from it. Same RPM set, same /usr/lib/os-release, same bootc labels. Only
# /usr/share/wrainrock/* is allowed to differ.
#
#   tests/parity.sh quay.io/fedora/fedora-silverblue:44 \
#                   localhost/wrainrock-linux:44
#
# Needs podman and both images available locally.
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

# --- Identity ---------------------------------------------------------------
in_image "${BASE}" 'cat /usr/lib/os-release' > "${tmpdir}/base-os-release"
in_image "${IMAGE}" 'cat /usr/lib/os-release' > "${tmpdir}/image-os-release"
if diff -u "${tmpdir}/base-os-release" "${tmpdir}/image-os-release" > /dev/null; then
    pass "/usr/lib/os-release identical"
else
    fail "/usr/lib/os-release was modified in the parity build"
fi

# --- Provenance -------------------------------------------------------------
if in_image "${IMAGE}" 'test -r /usr/share/wrainrock/build-info.json'; then
    pass "build-info.json exists"
else
    fail "build-info.json is missing"
fi

if in_image "${IMAGE}" 'test -r /usr/share/wrainrock/base-os-release'; then
    pass "pristine base os-release preserved"
else
    fail "pristine base os-release is missing"
fi

parity_json="$("${ENGINE}" run --rm --entrypoint /usr/bin/bash "${IMAGE}" \
    -c 'cat /usr/share/wrainrock/build-info.json')"
if python3 - "${parity_json}" <<'PY'
import json
import sys

info = json.loads(sys.argv[1])
assert info["schema"] == 1, info
assert info["parity"].startswith("fedora-silverblue-"), info
assert info["rpm_count"] > 0, info
assert len(info["rpm_set_sha256"]) == 64, info
PY
then
    pass "build-info.json is valid and complete"
else
    fail "build-info.json is invalid or incomplete: ${parity_json}"
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
printf 'parity holds: the image is Fedora Silverblue 44 plus provenance\n'
