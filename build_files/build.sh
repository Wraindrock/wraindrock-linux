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
#   3. apply the Wrainrock identity: os-release display fields, the Wrainrock
#      logo icon, the GDM login logo, the default desktop/GDM wallpaper and
#      the Plymouth boot splash, then record every applied difference in
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

rpm_db_tmp="$(mktemp -d /tmp/wrainrock-rpmdb.XXXXXX)"
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
for asset in wrainrock-logo-icon.svg wrainrock-gdm-logo.svg \
    wrainrock-gdm-logo.png wrainrock-wallpaper.png \
    plymouth/wrainrock.plymouth plymouth/background.png \
    plymouth/animation-0001.png plymouth/animation-0030.png \
    grub/theme.txt grub/background.png; do
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

# 3c. Wallpaper. Fedora ships 10_org.gnome.desktop.background.fedora.gschema
# override pointing at the f44 day/night images; our zz- override is merged
# later and therefore wins for new users and for the GDM greeter, which reads
# the same schema defaults.
install -D -m 0644 "${branding_dir}/wrainrock-wallpaper.png" \
    /usr/share/backgrounds/wrainrock/wrainrock-wallpaper.png

# 3d. GDM logo and default wallpaper. Override files are merged in name order,
# so zz- wins over Fedora's 10_* override. The login screen stays legible on
# its own background - see docs/architecture.md for the known dark-background
# contrast caveat.
gschema_dir=/usr/share/glib-2.0/schemas
override="${gschema_dir}/zz-wrainrock.gschema.override"
cat > "${override}" <<'EOF'
[org.gnome.login-screen]
logo='/usr/share/pixmaps/wrainrock-gdm-logo.png'

[org.gnome.desktop.background]
picture-uri='file:///usr/share/backgrounds/wrainrock/wrainrock-wallpaper.png'
picture-uri-dark='file:///usr/share/backgrounds/wrainrock/wrainrock-wallpaper.png'
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
plymouth_dir=/usr/share/plymouth/themes/wrainrock
install -d -m 0755 "${plymouth_dir}"
install -m 0644 "${branding_dir}/plymouth/wrainrock.plymouth" "${plymouth_dir}/"
install -m 0644 "${branding_dir}/plymouth/background.png" "${plymouth_dir}/"
install -m 0644 "${branding_dir}"/plymouth/animation-????.png "${plymouth_dir}/"
[[ -f ${plymouth_dir}/animation-0001.png && -f ${plymouth_dir}/animation-0030.png ]] \
    || die "Plymouth animation frames not installed"

cat > /etc/plymouth/plymouthd.conf <<'PLYMOUTHD'
# Wrainrock Linux boot splash. The theme itself is shipped in
# /usr/share/plymouth/themes/wrainrock; this file only selects it.
[Daemon]
Theme=wrainrock
PLYMOUTHD
chmod 0644 /etc/plymouth/plymouthd.conf
grep -qx 'Theme=wrainrock' /etc/plymouth/plymouthd.conf \
    || die "failed to select the Plymouth theme"

# 3f. GRUB boot menu theme (opt-in at runtime). bootc systems get their
# /boot/grub2/grub.cfg from bootupd as a static config during installation, so
# an image update cannot change the menu by itself. Ship the theme and a small
# helper; the helper copies it to /boot and uses bootupd's supported
# custom.cfg hook. See docs/architecture.md.
grub_theme_dir=/usr/share/grub/themes/wrainrock
install -d -m 0755 "${grub_theme_dir}"
install -m 0644 "${branding_dir}/grub/theme.txt" "${grub_theme_dir}/theme.txt"
install -m 0644 "${branding_dir}/grub/background.png" "${grub_theme_dir}/background.png"
[[ -f /usr/share/grub/unicode.pf2 ]] \
    || die "base image is missing /usr/share/grub/unicode.pf2"
install -D -m 0755 "${script_dir}/grub-theme/wrainrock-grub-theme" /usr/bin/wrainrock-grub-theme
[[ -x /usr/bin/wrainrock-grub-theme ]] || die "GRUB theme helper not installed"

# 3g. First-boot hostname seeding. bootc-image-builder's install path does not
# apply DEFAULT_HOSTNAME: the installed system inherits the base deployment's
# /etc, so a fresh install comes up as "fedora". Seed the hostname once, on the
# first boot, without touching a value the user already chose. The marker makes
# it idempotent and keeps later hostnamectl changes.
hostname_seed_dir="${script_dir}/hostname"
install -D -m 0755 "${hostname_seed_dir}/wrainrock-hostname-seed" /usr/libexec/wrainrock-hostname-seed
install -D -m 0644 "${hostname_seed_dir}/wrainrock-hostname-seed.service" \
    /usr/lib/systemd/system/wrainrock-hostname-seed.service
systemd_wants=/usr/lib/systemd/system/sysinit.target.wants
install -d -m 0755 "${systemd_wants}"
ln -sfn ../wrainrock-hostname-seed.service "${systemd_wants}/wrainrock-hostname-seed.service"
[[ -x /usr/libexec/wrainrock-hostname-seed && -f /usr/lib/systemd/system/wrainrock-hostname-seed.service ]] \
    || die "hostname seed unit or script not installed"
[[ -L ${systemd_wants}/wrainrock-hostname-seed.service ]] \
    || die "hostname seed unit is not enabled"
grep -q '^WantedBy=sysinit.target$' /usr/lib/systemd/system/wrainrock-hostname-seed.service \
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
      "/usr/share/glib-2.0/schemas/gschemas.compiled",
      "/etc/plymouth/plymouthd.conf"
    ],
    "added": [
      "/usr/share/icons/hicolor/scalable/apps/wrainrock-logo-icon.svg",
      "/usr/share/pixmaps/wrainrock-gdm-logo.svg",
      "/usr/share/pixmaps/wrainrock-gdm-logo.png",
      "/usr/share/glib-2.0/schemas/zz-wrainrock.gschema.override",
      "/usr/share/backgrounds/wrainrock/wrainrock-wallpaper.png",
      "/usr/share/plymouth/themes/wrainrock/wrainrock.plymouth",
      "/usr/share/plymouth/themes/wrainrock/background.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0001.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0002.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0003.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0004.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0005.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0006.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0007.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0008.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0009.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0010.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0011.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0012.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0013.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0014.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0015.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0016.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0017.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0018.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0019.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0020.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0021.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0022.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0023.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0024.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0025.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0026.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0027.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0028.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0029.png",
      "/usr/share/plymouth/themes/wrainrock/animation-0030.png",
      "/usr/share/grub/themes/wrainrock/theme.txt",
      "/usr/share/grub/themes/wrainrock/background.png",
      "/usr/bin/wrainrock-grub-theme",
      "/usr/libexec/wrainrock-hostname-seed",
      "/usr/lib/systemd/system/wrainrock-hostname-seed.service",
      "/usr/lib/systemd/system/sysinit.target.wants/wrainrock-hostname-seed.service",
      "/usr/share/wrainrock/base-os-release",
      "/usr/share/wrainrock/build-info.json",
      "/usr/share/wrainrock/delta.json"
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
say "boot splash installed: ${plymouth_dir} (theme: wrainrock)"
say "GRUB theme helper installed: /usr/bin/wrainrock-grub-theme (opt-in)"
say "delta manifest written to /usr/share/wrainrock/delta.json"
say "rpm database left byte-identical to the base"
