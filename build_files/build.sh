#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Wrainrock Linux image build step.
#
# Runs as root inside the base image. Its job in v0.1 is deliberately narrow:
#
#   1. prove the base is the Fedora Silverblue bootc image this project claims;
#   2. record provenance at /usr/share/wrainrock/build-info.json;
#   3. keep the pristine base os-release around for later parity checks
#      (v0.1 does not modify the image identity - that is a later step).
#
# It must not install packages, touch /etc or /var, or write to /run. Those are
# later roadmap steps with their own assertions.
# ---------------------------------------------------------------------------
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
say() { printf 'wrainrock: %s\n' "$*"; }

[[ ${EUID} -eq 0 ]] || die "build.sh must run as root"
for cmd in rpm sha256sum install; do
    command -v "${cmd}" >/dev/null 2>&1 || die "${cmd} is required"
done

os_release=/usr/lib/os-release
[[ -r ${os_release} ]] || die "${os_release} is missing"

# --- 1. base assertions -----------------------------------------------------
# These are deliberately exact: a silent base change (wrong variant, wrong
# Fedora release, a tag that moved) has to fail the build, not ship.
grep -qx 'ID=fedora' "${os_release}" \
    || die "base is not Fedora (ID=fedora missing)"
grep -qx "VERSION_ID=${FEDORA_VERSION}" "${os_release}" \
    || die "base is not Fedora ${FEDORA_VERSION} (VERSION_ID mismatch)"
grep -qx 'VARIANT_ID=silverblue' "${os_release}" \
    || die "base is not Silverblue (VARIANT_ID=silverblue missing)"

[[ -x /usr/bin/bootc ]] || die "base does not ship the bootc CLI"
[[ -d /usr/lib/bootc ]] || die "base is not a bootc image (/usr/lib/bootc missing)"

# --- 2. provenance ----------------------------------------------------------
install -d -m 0755 /usr/share/wrainrock
install -m 0644 "${os_release}" /usr/share/wrainrock/base-os-release

rpm_count="$(rpm -qa | wc -l)"
rpm_set_sha256="$(
    rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
        | LC_ALL=C sort \
        | sha256sum \
        | cut -d' ' -f1
)"

cat > /usr/share/wrainrock/build-info.json <<EOF
{
  "schema": 1,
  "image": "${IMAGE_NAME:-unknown}",
  "version": "${IMAGE_VERSION:-dev}",
  "build_number": "${BUILD_NUMBER:-local}",
  "git_sha": "${GIT_SHA:-unknown}",
  "build_date": "${BUILD_DATE:-unknown}",
  "base_image": "${BASE_IMAGE:-unknown}",
  "base_digest": "${BASE_DIGEST:-unknown}",
  "fedora_version": "${FEDORA_VERSION:-unknown}",
  "parity": "fedora-silverblue-${FEDORA_VERSION:-unknown}",
  "rpm_count": ${rpm_count},
  "rpm_set_sha256": "${rpm_set_sha256}"
}
EOF
chmod 0644 /usr/share/wrainrock/build-info.json

say "provenance written for ${IMAGE_NAME:-unknown} (${rpm_count} packages)"
say "base os-release preserved at /usr/share/wrainrock/base-os-release"
