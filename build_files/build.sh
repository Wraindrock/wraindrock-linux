#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Wraindrock Linux image build step.
#
# Runs as root inside the pristine Bluefin DX base image. It does three
# things and nothing else:
#
#   1. prove the base is the Bluefin DX bootc image this project claims;
#   2. record provenance at /usr/share/wraindrock/build-info.json and preserve
#      the untouched base os-release next to it;
#   3. apply the Wraindrock identity: os-release display fields, the Wraindrock
#      logo icon, the GDM login logo, the default desktop/GDM wallpaper and
#      the Plymouth boot splash, then record every applied difference in
#      /usr/share/wraindrock/delta.json.
#
# The delta manifest is the contract the parity test enforces: the image may
# differ from the base only in ways listed there. It must not install
# packages, touch /var, or write to /run. Those are later roadmap steps with
# their own assertions.
# ---------------------------------------------------------------------------
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
say() { printf 'wraindrock: %s\n' "$*"; }

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
grep -qx 'ID=bluefin' "${os_release}" \
    || die "base is not Bluefin (ID=bluefin missing)"
grep -qx "VERSION_ID=${FEDORA_VERSION}" "${os_release}" \
    || die "base is not Bluefin ${FEDORA_VERSION} (VERSION_ID mismatch)"
grep -Eq '^VARIANT_ID=bluefin-dx' "${os_release}" \
    || die "base is not Bluefin DX (VARIANT_ID=bluefin-dx* missing)"
base_variant_id="$(sed -n 's/^VARIANT_ID=//p' "${os_release}" | tail -n 1)"

[[ -x /usr/bin/bootc ]] || die "base does not ship the bootc CLI"
[[ -d /usr/lib/bootc ]] || die "base is not a bootc image (/usr/lib/bootc missing)"

# --- 2. provenance ----------------------------------------------------------
# Copy the pristine os-release before branding: parity diffs against this copy.
install -d -m 0755 /usr/share/wraindrock
install -m 0644 "${os_release}" /usr/share/wraindrock/base-os-release

# Query a throwaway copy of the RPM database. The base image ships the database
# together with sqlite's sidecar files (.rpm.lock, -wal, -shm); opening the
# image's copies directly (even read-only) can copy them up into our layer, so
# the build must leave every byte of /usr/share/rpm alone.
rpm_db_signature() {
    local dir=/usr/share/rpm name
    (cd "${dir}" && LC_ALL=C ls -A) | while IFS= read -r name; do
        [[ -f ${dir}/${name} ]] || continue
        printf '%s %s %s\n' "${name}" "$(stat -c '%s %Y' "${dir}/${name}")" \
            "$(sha256sum "${dir}/${name}" | cut -d' ' -f1)"
    done
}
rpm_db_before="$(rpm_db_signature)"

rpm_db_tmp="$(mktemp -d /tmp/wraindrock-rpmdb.XXXXXX)"
cp -a /usr/share/rpm/rpmdb.sqlite "${rpm_db_tmp}/rpmdb.sqlite"
rpm_query() { rpm --dbpath "${rpm_db_tmp}" "$@"; }
rpm_count="$(rpm_query -qa | wc -l)"
rpm_set_sha256="$(
    rpm_query -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
        | LC_ALL=C sort \
        | sha256sum \
        | cut -d' ' -f1
)"
rm -rf "${rpm_db_tmp}"

[[ $(rpm_db_signature) == "${rpm_db_before}" ]] \
    || die "the RPM database changed during the build"

# --- 3. identity ------------------------------------------------------------
for asset in wraindrock-logo-icon.svg wraindrock-gdm-logo.svg \
    wraindrock-gdm-logo.png wraindrock-wallpaper.png \
    plymouth/wraindrock.plymouth plymouth/background.png \
    plymouth/animation-0001.png plymouth/animation-0030.png \
    grub/theme.txt grub/background.png; do
    [[ -r ${branding_dir}/${asset} ]] || die "branding asset ${asset} is missing"
done

# 3a. os-release. Keep VERSION, VERSION_ID, OSTREE_VERSION and SUPPORT_END from
# the base: update cadence and support window must stay honest. Only identity
# and links change.
sed -i \
    -e 's/^NAME=.*/NAME="Wraindrock Linux"/' \
    -e 's/^PRETTY_NAME="Bluefin/PRETTY_NAME="Wraindrock/' \
    -e 's/^LOGO=.*/LOGO=wraindrock-logo-icon/' \
    -e 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME="wraindrock"/' \
    -e 's|^HOME_URL=.*|HOME_URL="https://github.com/Wraindrock/wraindrock-linux"|' \
    -e 's|^DOCUMENTATION_URL=.*|DOCUMENTATION_URL="https://github.com/Wraindrock/wraindrock-linux/blob/main/docs/install.md"|' \
    -e 's|^SUPPORT_URL=.*|SUPPORT_URL="https://github.com/Wraindrock/wraindrock-linux/issues"|' \
    -e 's|^BUG_REPORT_URL=.*|BUG_REPORT_URL="https://github.com/Wraindrock/wraindrock-linux/issues"|' \
    "${os_release}"


grep -qx 'NAME="Wraindrock Linux"' "${os_release}" \
    || die "failed to brand NAME"
grep -Eq '^PRETTY_NAME="Wraindrock \(Version: [0-9]' "${os_release}" \
    || die "failed to brand PRETTY_NAME"
grep -qx 'ID=bluefin' "${os_release}" || die "branding changed ID"
grep -qx 'ID_LIKE="fedora"' "${os_release}" || die "base lost ID_LIKE"
grep -qx 'LOGO=wraindrock-logo-icon' "${os_release}" || die "failed to brand LOGO"
grep -qx 'DEFAULT_HOSTNAME="wraindrock"' "${os_release}" \
    || die "failed to brand DEFAULT_HOSTNAME"
grep -qx "VERSION_ID=${FEDORA_VERSION}" "${os_release}" \
    || die "branding changed VERSION_ID"
grep -qx "VARIANT_ID=${base_variant_id}" "${os_release}" \
    || die "branding changed VARIANT_ID"

# 3b. icons. LOGO names an icon theme entry (Settings -> About); GDM reads the
# wordmark by path from the gsettings override below.
install -D -m 0644 "${branding_dir}/wraindrock-logo-icon.svg" \
    /usr/share/icons/hicolor/scalable/apps/wraindrock-logo-icon.svg
install -D -m 0644 "${branding_dir}/wraindrock-gdm-logo.svg" \
    /usr/share/pixmaps/wraindrock-gdm-logo.svg
install -D -m 0644 "${branding_dir}/wraindrock-gdm-logo.png" \
    /usr/share/pixmaps/wraindrock-gdm-logo.png

# 3c. Wallpaper. Fedora ships 10_org.gnome.desktop.background.fedora.gschema
# override pointing at the f44 day/night images; our zz- override is merged
# later and therefore wins for new users and for the GDM greeter, which reads
# the same schema defaults.
install -D -m 0644 "${branding_dir}/wraindrock-wallpaper.png" \
    /usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png

# 3d. GDM logo and default wallpaper. Override files are merged in name order,
# so zz- wins over Fedora's 10_* override. The login screen stays legible on
# its own background - see docs/architecture.md for the known dark-background
# contrast caveat.
gschema_dir=/usr/share/glib-2.0/schemas
override="${gschema_dir}/zzzz-wraindrock.gschema.override"
cat > "${override}" <<'EOF'
[org.gnome.login-screen]
logo='/usr/share/pixmaps/wraindrock-gdm-logo.png'

[org.gnome.desktop.background]
picture-uri='file:///usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png'
picture-uri-dark='file:///usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png'
EOF
chmod 0644 "${override}"
command -v glib-compile-schemas >/dev/null 2>&1 \
    || die "glib-compile-schemas is required to apply the GDM logo"
glib-compile-schemas "${gschema_dir}"

# 3e. Plymouth boot splash. Fedora's theme plugins are all shipped in the base
# image, so the splash needs no package change: a two-step theme plus the
# daemon config is enough. plymouth's /usr/lib/plymouth/plymouth-populate-initrd
# reads this config when a deployment regenerates its initramfs and copies the
# selected theme into it.
plymouth_dir=/usr/share/plymouth/themes/wraindrock
install -d -m 0755 "${plymouth_dir}"
install -m 0644 "${branding_dir}/plymouth/wraindrock.plymouth" "${plymouth_dir}/"
install -m 0644 "${branding_dir}/plymouth/background.png" "${plymouth_dir}/"
install -m 0644 "${branding_dir}"/plymouth/animation-????.png "${plymouth_dir}/"
[[ -f ${plymouth_dir}/animation-0001.png && -f ${plymouth_dir}/animation-0030.png ]] \
    || die "Plymouth animation frames not installed"

cat > /etc/plymouth/plymouthd.conf <<'PLYMOUTHD'
# Wraindrock Linux boot splash. The theme itself is shipped in
# /usr/share/plymouth/themes/wraindrock; this file only selects it.
[Daemon]
Theme=wraindrock
PLYMOUTHD
chmod 0644 /etc/plymouth/plymouthd.conf
grep -qx 'Theme=wraindrock' /etc/plymouth/plymouthd.conf \
    || die "failed to select the Plymouth theme"

# 3f. GRUB boot menu theme (opt-in at runtime). bootc systems get their
# /boot/grub2/grub.cfg from bootupd as a static config during installation, so
# an image update cannot change the menu by itself. Ship the theme and a small
# helper; the helper copies it to /boot and uses bootupd's supported
# custom.cfg hook. See docs/architecture.md.
grub_theme_dir=/usr/share/grub/themes/wraindrock
install -d -m 0755 "${grub_theme_dir}"
install -m 0644 "${branding_dir}/grub/theme.txt" "${grub_theme_dir}/theme.txt"
install -m 0644 "${branding_dir}/grub/background.png" "${grub_theme_dir}/background.png"
[[ -f /usr/share/grub/unicode.pf2 ]] \
    || die "base image is missing /usr/share/grub/unicode.pf2"
install -D -m 0755 "${script_dir}/grub-theme/wraindrock-grub-theme" /usr/bin/wraindrock-grub-theme
[[ -x /usr/bin/wraindrock-grub-theme ]] || die "GRUB theme helper not installed"

# 3g. First-boot hostname seeding. bootc-image-builder's install path does not
# apply DEFAULT_HOSTNAME: the installed system inherits the base deployment's
# /etc, so a fresh install comes up as "fedora". Seed the hostname once, on the
# first boot, without touching a value the user already chose. The marker makes
# it idempotent and keeps later hostnamectl changes.
hostname_seed_dir="${script_dir}/hostname"
install -D -m 0755 "${hostname_seed_dir}/wraindrock-hostname-seed" /usr/libexec/wraindrock-hostname-seed
install -D -m 0644 "${hostname_seed_dir}/wraindrock-hostname-seed.service" \
    /usr/lib/systemd/system/wraindrock-hostname-seed.service
systemd_wants=/usr/lib/systemd/system/sysinit.target.wants
install -d -m 0755 "${systemd_wants}"
ln -sfn ../wraindrock-hostname-seed.service "${systemd_wants}/wraindrock-hostname-seed.service"
[[ -x /usr/libexec/wraindrock-hostname-seed && -f /usr/lib/systemd/system/wraindrock-hostname-seed.service ]] \
    || die "hostname seed unit or script not installed"
[[ -L ${systemd_wants}/wraindrock-hostname-seed.service ]] \
    || die "hostname seed unit is not enabled"
grep -q '^WantedBy=sysinit.target$' /usr/lib/systemd/system/wraindrock-hostname-seed.service \
    || die "hostname seed unit has the wrong target"

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

cat > /usr/share/wraindrock/delta.json <<EOF
{
  "schema": 1,
  "base_image": $(json_value "${BASE_IMAGE:-unknown}"),
  "base_digest": $(json_value "${BASE_DIGEST:-unknown}"),
  "os_release": {
    "changed": {
      "NAME": $(json_value "$(unquote "$(field NAME)")"),
      "PRETTY_NAME": $(json_value "$(unquote "$(field PRETTY_NAME)")"),
      "LOGO": $(json_value "$(unquote "$(field LOGO)")"),
      "DEFAULT_HOSTNAME": $(json_value "$(unquote "$(field DEFAULT_HOSTNAME)")"),
      "HOME_URL": $(json_value "$(unquote "$(field HOME_URL)")"),
      "DOCUMENTATION_URL": $(json_value "$(unquote "$(field DOCUMENTATION_URL)")"),
      "SUPPORT_URL": $(json_value "$(unquote "$(field SUPPORT_URL)")"),
      "BUG_REPORT_URL": $(json_value "$(unquote "$(field BUG_REPORT_URL)")")
    }
  },
  "files": {
    "modified": [
      "/usr/lib/os-release",
      "/usr/share/glib-2.0/schemas/gschemas.compiled",
      "/etc/plymouth/plymouthd.conf"
    ],
    "added": [
      "/usr/share/icons/hicolor/scalable/apps/wraindrock-logo-icon.svg",
      "/usr/share/pixmaps/wraindrock-gdm-logo.svg",
      "/usr/share/pixmaps/wraindrock-gdm-logo.png",
      "/usr/share/glib-2.0/schemas/zzzz-wraindrock.gschema.override",
      "/usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png",
      "/usr/share/plymouth/themes/wraindrock/wraindrock.plymouth",
      "/usr/share/plymouth/themes/wraindrock/background.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0001.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0002.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0003.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0004.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0005.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0006.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0007.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0008.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0009.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0010.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0011.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0012.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0013.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0014.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0015.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0016.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0017.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0018.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0019.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0020.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0021.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0022.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0023.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0024.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0025.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0026.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0027.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0028.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0029.png",
      "/usr/share/plymouth/themes/wraindrock/animation-0030.png",
      "/usr/share/grub/themes/wraindrock/theme.txt",
      "/usr/share/grub/themes/wraindrock/background.png",
      "/usr/bin/wraindrock-grub-theme",
      "/usr/libexec/wraindrock-hostname-seed",
      "/usr/lib/systemd/system/wraindrock-hostname-seed.service",
      "/usr/lib/systemd/system/sysinit.target.wants/wraindrock-hostname-seed.service",
      "/usr/share/wraindrock/base-os-release",
      "/usr/share/wraindrock/build-info.json",
      "/usr/share/wraindrock/delta.json"
    ]
  }
}
EOF
chmod 0644 /usr/share/wraindrock/delta.json

cat > /usr/share/wraindrock/build-info.json <<EOF
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
  "identity": "wraindrock",
  "parity": "bluefin-dx-${FEDORA_VERSION:-unknown}",
  "rpm_count": ${rpm_count},
  "rpm_set_sha256": "${rpm_set_sha256}"
}
EOF
chmod 0644 /usr/share/wraindrock/build-info.json

say "provenance written for ${IMAGE_NAME:-unknown} (${rpm_count} packages)"
say "base os-release preserved at /usr/share/wraindrock/base-os-release"
say "identity applied: $(unquote "$(field PRETTY_NAME)")"
say "boot splash installed: ${plymouth_dir} (theme: wraindrock)"
say "GRUB theme helper installed: /usr/bin/wraindrock-grub-theme (opt-in)"
say "delta manifest written to /usr/share/wraindrock/delta.json"
say "rpm database left byte-identical to the base"
