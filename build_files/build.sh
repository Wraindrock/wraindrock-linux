#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Wrainrock Linux image build step.
#
# Runs as root inside the pristine Fedora Silverblue base image. It does three
# things and nothing else:
#
#   1. prove the base is the Fedora Silverblue bootc image this project claims;
#   2. record provenance at /usr/share/wrainrock/build-info.json and preserve
#      the untouched base os-release next to it;
#   3. apply the v0.2 identity: os-release display fields, the Wrainrock logo
#      icon and the GDM login logo, then record every applied difference in
#      /usr/share/wrainrock/delta.json.
#
# The delta manifest is the contract the parity test enforces: the image may
# differ from the base only in ways listed there. It must not install
# packages, touch /var, or write to /run. Those are later roadmap steps with
# their own assertions.
# ---------------------------------------------------------------------------
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
say() { printf 'wrainrock: %s\n' "$*"; }

[[ ${EUID} -eq 0 ]] || die "build.sh must run as root"
for cmd in rpm sha256sum install grep sed; do
    command -v "${cmd}" >/dev/null 2>&1 || die "${cmd} is required"
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
branding_dir="${script_dir}/branding"

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
# Copy the pristine os-release before branding: parity diffs against this copy.
install -d -m 0755 /usr/share/wrainrock
install -m 0644 "${os_release}" /usr/share/wrainrock/base-os-release

rpm_count="$(rpm -qa | wc -l)"
rpm_set_sha256="$(
    rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
        | LC_ALL=C sort \
        | sha256sum \
        | cut -d' ' -f1
)"

# --- 3. identity ------------------------------------------------------------
for asset in wrainrock-logo-icon.svg wrainrock-gdm-logo.svg wrainrock-gdm-logo.png; do
    [[ -r ${branding_dir}/${asset} ]] || die "branding asset ${asset} is missing"
done

# 3a. os-release. Keep VERSION, VERSION_ID, OSTREE_VERSION and SUPPORT_END from
# the base: update cadence and support window must stay honest. Only identity
# and links change.
sed -i \
    -e 's/^NAME=.*/NAME="Wrainrock Linux"/' \
    -e 's/^PRETTY_NAME="Fedora Linux /PRETTY_NAME="Wrainrock Linux /' \
    -e 's/^ID=fedora$/ID=wrainrock/' \
    -e 's/^LOGO=.*/LOGO=wrainrock-logo-icon/' \
    -e 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME="wrainrock"/' \
    -e 's|^HOME_URL=.*|HOME_URL="https://github.com/Wraindrock/wrainrock-linux"|' \
    -e 's|^DOCUMENTATION_URL=.*|DOCUMENTATION_URL="https://github.com/Wraindrock/wrainrock-linux/blob/main/docs/install.md"|' \
    -e 's|^SUPPORT_URL=.*|SUPPORT_URL="https://github.com/Wraindrock/wrainrock-linux/issues"|' \
    -e 's|^BUG_REPORT_URL=.*|BUG_REPORT_URL="https://github.com/Wraindrock/wrainrock-linux/issues"|' \
    -e "s|^CPE_NAME=.*|CPE_NAME=\"cpe:/o:wraindrock:wrainrock_linux:${FEDORA_VERSION}\"|" \
    "${os_release}"

# Fedora has no ID_LIKE; add one so downstream tooling can still tell this is a
# Fedora-family system.
grep -q '^ID_LIKE=' "${os_release}" \
    || sed -i '/^ID=wrainrock$/a ID_LIKE="fedora"' "${os_release}"

grep -qx 'NAME="Wrainrock Linux"' "${os_release}" \
    || die "failed to brand NAME"
grep -Eq '^PRETTY_NAME="Wrainrock Linux [0-9]' "${os_release}" \
    || die "failed to brand PRETTY_NAME"
grep -qx 'ID=wrainrock' "${os_release}" || die "failed to brand ID"
grep -qx 'ID_LIKE="fedora"' "${os_release}" || die "failed to add ID_LIKE"
grep -qx 'LOGO=wrainrock-logo-icon' "${os_release}" || die "failed to brand LOGO"
grep -qx 'DEFAULT_HOSTNAME="wrainrock"' "${os_release}" \
    || die "failed to brand DEFAULT_HOSTNAME"
grep -qx "VERSION_ID=${FEDORA_VERSION}" "${os_release}" \
    || die "branding changed VERSION_ID"
grep -qx 'VARIANT_ID=silverblue' "${os_release}" \
    || die "branding changed VARIANT_ID"

# 3b. icons. LOGO names an icon theme entry (Settings -> About); GDM reads the
# wordmark by path from the gsettings override below.
install -D -m 0644 "${branding_dir}/wrainrock-logo-icon.svg" \
    /usr/share/icons/hicolor/scalable/apps/wrainrock-logo-icon.svg
install -D -m 0644 "${branding_dir}/wrainrock-gdm-logo.svg" \
    /usr/share/pixmaps/wrainrock-gdm-logo.svg
install -D -m 0644 "${branding_dir}/wrainrock-gdm-logo.png" \
    /usr/share/pixmaps/wrainrock-gdm-logo.png

# 3c. GDM logo. Fedora's org.gnome.login-screen.gschema.override sets a Fedora
# path; override files are merged in name order, so zz- wins. The login screen
# stays legible on its own background - see docs/architecture.md for the known
# dark-background contrast caveat.
gschema_dir=/usr/share/glib-2.0/schemas
override="${gschema_dir}/zz-wrainrock.gschema.override"
cat > "${override}" <<'EOF'
[org.gnome.login-screen]
logo='/usr/share/pixmaps/wrainrock-gdm-logo.png'
EOF
chmod 0644 "${override}"
command -v glib-compile-schemas >/dev/null 2>&1 \
    || die "glib-compile-schemas is required to apply the GDM logo"
glib-compile-schemas "${gschema_dir}"

# --- 4. delta manifest ------------------------------------------------------
# Every intended difference from the base, machine-readable. tests/parity.sh
# fails the build if the real image differs in any other way.
field() { sed -n "s/^$1=//p" "${os_release}" | tail -n 1; }
unquote() {
    local value="$1"
    value="${value%\"}"
    value="${value#\"}"
    printf '%s' "${value}"
}
json_value() {
    local value="$1"
    [[ ${value} != *'"'* && ${value} != *'\'* ]] \
        || die "refusing to write backslash or quote into delta.json"
    if [[ -z ${value} ]]; then
        printf 'null'
    else
        printf '"%s"' "${value}"
    fi
}

cat > /usr/share/wrainrock/delta.json <<EOF
{
  "schema": 1,
  "base_image": $(json_value "${BASE_IMAGE:-unknown}"),
  "base_digest": $(json_value "${BASE_DIGEST:-unknown}"),
  "os_release": {
    "changed": {
      "NAME": $(json_value "$(unquote "$(field NAME)")"),
      "PRETTY_NAME": $(json_value "$(unquote "$(field PRETTY_NAME)")"),
      "ID": $(json_value "$(unquote "$(field ID)")"),
      "LOGO": $(json_value "$(unquote "$(field LOGO)")"),
      "DEFAULT_HOSTNAME": $(json_value "$(unquote "$(field DEFAULT_HOSTNAME)")"),
      "HOME_URL": $(json_value "$(unquote "$(field HOME_URL)")"),
      "DOCUMENTATION_URL": $(json_value "$(unquote "$(field DOCUMENTATION_URL)")"),
      "SUPPORT_URL": $(json_value "$(unquote "$(field SUPPORT_URL)")"),
      "BUG_REPORT_URL": $(json_value "$(unquote "$(field BUG_REPORT_URL)")"),
      "CPE_NAME": $(json_value "$(unquote "$(field CPE_NAME)")")
    },
    "added": {
      "ID_LIKE": $(json_value "$(unquote "$(field ID_LIKE)")")
    }
  },
  "files": {
    "modified": [
      "/usr/lib/os-release",
      "/usr/share/glib-2.0/schemas/gschemas.compiled"
    ],
    "added": [
      "/usr/share/icons/hicolor/scalable/apps/wrainrock-logo-icon.svg",
      "/usr/share/pixmaps/wrainrock-gdm-logo.svg",
      "/usr/share/pixmaps/wrainrock-gdm-logo.png",
      "/usr/share/glib-2.0/schemas/zz-wrainrock.gschema.override"
    ]
  }
}
EOF
chmod 0644 /usr/share/wrainrock/delta.json

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
  "identity": "wrainrock",
  "parity": "fedora-silverblue-${FEDORA_VERSION:-unknown}",
  "rpm_count": ${rpm_count},
  "rpm_set_sha256": "${rpm_set_sha256}"
}
EOF
chmod 0644 /usr/share/wrainrock/build-info.json

say "provenance written for ${IMAGE_NAME:-unknown} (${rpm_count} packages)"
say "base os-release preserved at /usr/share/wrainrock/base-os-release"
say "identity applied: $(unquote "$(field PRETTY_NAME)")"
say "delta manifest written to /usr/share/wrainrock/delta.json"
