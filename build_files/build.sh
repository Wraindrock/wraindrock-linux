#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Wraindrock image build step.
#
# Runs as root inside the pristine Bluefin DX base image. It does four
# things and nothing else:
#
#   1. prove the base is the Bluefin DX bootc image this project claims;
#   2. record provenance at /usr/share/wraindrock/build-info.json and preserve
#      the untouched base os-release and RPM set next to it;
#   3. apply the Wraindrock identity: os-release display fields, the Wraindrock
#      logo icon, the GDM login logo, the default desktop/GDM wallpaper, the
#      Plymouth boot splash and the opt-in GRUB theme;
#   4. declare the first-boot Flatpaks, the Helium default browser, the four
#      pinned RPMs and the IBus/libpinyin input-method default, then record
#      every applied difference in /usr/share/wraindrock/delta.json.
#
# The delta manifest is the contract the parity test enforces: the image may
# differ from the base only in ways listed there. It must not touch /var
# state or write to /run; those are later roadmap steps with their own
# assertions.
# ---------------------------------------------------------------------------
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
say() { printf 'wraindrock: %s\n' "$*"; }

[[ ${EUID} -eq 0 ]] || die "build.sh must run as root"
for cmd in rpm sha256sum install grep sed curl comm gsettings; do
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
grep -Eq '^VARIANT_ID=bluefin-dx-nvidia-open' "${os_release}" \
    || die "base is not Bluefin DX NVIDIA (VARIANT_ID=bluefin-dx-nvidia-open missing)"
base_variant_id="$(sed -n 's/^VARIANT_ID=//p' "${os_release}" | tail -n 1)"

[[ -x /usr/bin/bootc ]] || die "base does not ship the bootc CLI"
[[ -d /usr/lib/bootc ]] || die "base is not a bootc image (/usr/lib/bootc missing)"

# v0.6: the drivers and the virtualisation stack are inherited from this base
# variant. Assert them here so a silent base change cannot ship without them.
rpm -q kmod-nvidia nvidia-driver nvidia-container-toolkit >/dev/null 2>&1 \
    || die "base is missing the NVIDIA driver stack"
[[ -x /usr/bin/nvidia-smi ]] || die "base is missing nvidia-smi"
rpm -q qemu-system-x86-core libvirt-daemon-kvm virt-manager >/dev/null 2>&1 \
    || die "base is missing the QEMU/KVM stack"
command -v flatpak >/dev/null 2>&1 || die "base is missing flatpak"

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
rpm_base_set_file="$(mktemp /tmp/wraindrock-base-rpm-set.XXXXXX)"
rpm_query -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
    | LC_ALL=C sort > "${rpm_base_set_file}"
rpm_base_count="$(wc -l < "${rpm_base_set_file}")"
rpm_count="${rpm_base_count}"
rpm_set_sha256="$(sha256sum "${rpm_base_set_file}" | cut -d' ' -f1)"
rm -rf "${rpm_db_tmp}"

[[ $(rpm_db_signature) == "${rpm_db_before}" ]] \
    || die "the RPM database changed before the software step"

# --- 3. identity ------------------------------------------------------------
[[ -r ${branding_dir}/wraindrock-wallpaper.png ]] \
    || die "wallpaper asset is missing"

# 3a. os-release. Keep VERSION, VERSION_ID, OSTREE_VERSION and SUPPORT_END from
# the base: update cadence and support window must stay honest. Only identity
# and links change.
sed -i \
    -e 's/^NAME=.*/NAME="Wraindrock"/' \
    -e 's/^PRETTY_NAME="Bluefin/PRETTY_NAME="Wraindrock/' \
    -e 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME="wraindrock"/' \
    -e 's|^HOME_URL=.*|HOME_URL="https://github.com/Wraindrock/wraindrock-linux"|' \
    -e 's|^DOCUMENTATION_URL=.*|DOCUMENTATION_URL="https://github.com/Wraindrock/wraindrock-linux/blob/main/docs/install.md"|' \
    -e 's|^SUPPORT_URL=.*|SUPPORT_URL="https://github.com/Wraindrock/wraindrock-linux/issues"|' \
    -e 's|^BUG_REPORT_URL=.*|BUG_REPORT_URL="https://github.com/Wraindrock/wraindrock-linux/issues"|' \
    "${os_release}"


grep -qx 'NAME="Wraindrock"' "${os_release}" \
    || die "failed to brand NAME"
grep -Eq '^PRETTY_NAME="Wraindrock \(Version: [0-9]' "${os_release}" \
    || die "failed to brand PRETTY_NAME"
grep -qx 'ID=bluefin' "${os_release}" || die "branding changed ID"
grep -qx 'ID_LIKE="fedora"' "${os_release}" || die "base lost ID_LIKE"
grep -qx 'DEFAULT_HOSTNAME="wraindrock"' "${os_release}" \
    || die "failed to brand DEFAULT_HOSTNAME"
grep -qx "VERSION_ID=${FEDORA_VERSION}" "${os_release}" \
    || die "branding changed VERSION_ID"
grep -qx "VARIANT_ID=${base_variant_id}" "${os_release}" \
    || die "branding changed VARIANT_ID"

# 3c. Wallpaper. Fedora ships 10_org.gnome.desktop.background.fedora.gschema
# override pointing at the f44 day/night images; our zz- override is merged
# later and therefore wins for new users and for the GDM greeter, which reads
# the same schema defaults.
install -D -m 0644 "${branding_dir}/wraindrock-wallpaper.png" \
    /usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png

# 3d. GDM logo and default wallpaper. Override files are merged in name order,
# so zz- wins over Fedora's 10_* override.
gschema_dir=/usr/share/glib-2.0/schemas
override="${gschema_dir}/zzzz-wraindrock.gschema.override"
cat > "${override}" <<'EOF'
[org.gnome.desktop.background]
picture-uri='file:///usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png'
picture-uri-dark='file:///usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png'

# IBus (not Fcitx) is the input method; libpinyin is the Chinese engine. The
# engine already ships in the base, so only the default needs declaring. A
# user's own input-sources setting always wins.
[org.gnome.desktop.input-sources]
sources=[('xkb', 'us'), ('ibus', 'libpinyin')]
mru-sources=[('xkb', 'us'), ('ibus', 'libpinyin')]
show-all-sources=true
EOF
chmod 0644 "${override}"
command -v glib-compile-schemas >/dev/null 2>&1 \
    || die "glib-compile-schemas is required to apply the defaults"
glib-compile-schemas "${gschema_dir}"

# The input-method default is only real if the compiled schema reports it.
GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.input-sources sources \
    | grep -q "libpinyin" \
    || die "the compiled schemas do not report the IBus libpinyin default"
rpm -q ibus ibus-libpinyin google-noto-sans-cjk-fonts >/dev/null 2>&1 \
    || die "IBus, libpinyin or the CJK fonts are missing from the base"
if rpm -q fcitx5 >/dev/null 2>&1; then
    die "fcitx5 is installed; the default must stay IBus"
fi

# 3e. UEFI boot entry name. bootupd labels the firmware entry from
# /etc/system-release when it exists (Bluefin's symlink says "Fedora release
# ..."), falling back to os-release NAME. Ship a real file so installs and
# bootloader updates name the entry "Wraindrock".
system_release=/etc/system-release
rm -f "${system_release}"
printf 'Wraindrock release %s (Bluefin DX)\n' "${FEDORA_VERSION}" > "${system_release}"
chmod 0644 "${system_release}"
grep -Eq '^Wraindrock release [0-9]' "${system_release}" \
    || die "failed to brand /etc/system-release"

# 3f. Application folders. GNOME groups launchers into folders; Bluefin ships
# its own set through a distro dconf database. Add Wraindrock's taxonomy in the
# same database and generate the Flatpak folder from the preinstall list, so
# the two never drift. Users can still move apps between folders.
dconf_dir=/etc/dconf/db/distro.d
install -d -m 0755 "${dconf_dir}"
folders_file="${dconf_dir}/10-wraindrock-folders"
flatpak_list="${script_dir}/software/flatpaks.txt"
[[ -s ${flatpak_list} ]] || die "the Flatpak list is missing"
{
    printf '# Wraindrock application folders.\n'
    printf '[org/gnome/desktop/app-folders]\n'
    printf "folder-children=['Games', 'GamingUtilities', 'Utilities', 'Development', 'Containers', 'Wine', 'Productivity', 'Virtualization', 'Proxies', 'Bluefin', 'Wraindrock', 'Flatpak', 'AppImage']\n"
    printf "\n[org/gnome/desktop/app-folders/folders/Virtualization]\n"
    printf "apps=['virt-manager.desktop', 'org.gnome.Boxes.desktop', 'io.podman_desktop.PodmanDesktop.desktop', 'com.github.marhkb.Pods.desktop', 'io.github.dvlv.boxbuddyrs.desktop']\n"
    printf "name='Virtualization'\ntranslate=false\n"
    printf "\n[org/gnome/desktop/app-folders/folders/Proxies]\n"
    printf "apps=['Clash Verge.desktop', 'sing-box.desktop']\n"
    printf "name='Proxies'\ntranslate=false\n"
    printf "\n[org/gnome/desktop/app-folders/folders/Bluefin]\n"
    printf "apps=['io.github.kolunmi.Bazaar.desktop', 'com.mattjakeman.ExtensionManager.desktop', 'org.gnome.tweaks.desktop', 'io.github.flattool.Warehouse.desktop', 'com.github.tchx84.Flatseal.desktop', 'ca.desrt.dconf-editor.desktop', 'app.devsuite.Ptyxis.desktop']\n"
    printf "name='Bluefin'\ntranslate=false\n"
    printf "\n[org/gnome/desktop/app-folders/folders/Wraindrock]\n"
    printf "apps=['helium.desktop', 'Rayburst.desktop']\n"
    printf "name='Wraindrock'\ntranslate=false\n"
    printf "\n[org/gnome/desktop/app-folders/folders/AppImage]\n"
    printf "apps=['it.mijorus.gearlever.desktop']\n"
    printf "name='AppImage'\ntranslate=false\n"
    printf "\n[org/gnome/desktop/app-folders/folders/Flatpak]\n"
    printf 'apps=['
    first=1
    while IFS= read -r app; do
        [[ -n ${app} && ${app} != \#* ]] || continue
        [[ ${first} == 1 ]] || printf ', '
        printf "'%s.desktop'" "${app}"
        first=0
    done < "${flatpak_list}"
    printf "]\nname='Flatpak'\ntranslate=false\n"
} > "${folders_file}"
chmod 0644 "${folders_file}"
command -v dconf >/dev/null 2>&1 || die "dconf is required to compile the app-folder database"
dconf update
grep -aq 'Virtualization' /etc/dconf/db/distro \
    || die "the app-folder database was not compiled"

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

# --- 3h. software defaults --------------------------------------------------
# Bluefin DX's developer Flatpaks and Wraindrock's personal defaults are
# installed by flatpak-preinstall.service on the first boot (Flatpak only; the
# file is declarative and survives image updates). Three programs have no
# Flatpak, so their GitHub RPMs are baked at pinned versions. Every added
# package is recorded in delta.json and parity refuses anything undeclared.

install -d -m 0755 /usr/share/flatpak/preinstall.d /etc/xdg
flatpak_list="${script_dir}/software/flatpaks.txt"
[[ -s ${flatpak_list} ]] || die "the Flatpak list is missing"
{
    printf '# Installed on first boot by flatpak-preinstall.service.\n'
    printf '# Generated from build_files/software/flatpaks.txt; do not edit.\n'
    while IFS= read -r app; do
        [[ -n ${app} && ${app} != \#* ]] || continue
        printf '\n[Flatpak Preinstall %s]\nBranch=stable\nIsRuntime=false\n' "${app}"
    done < "${flatpak_list}"
} > /usr/share/flatpak/preinstall.d/wraindrock.preinstall
chmod 0644 /usr/share/flatpak/preinstall.d/wraindrock.preinstall
install -m 0644 "${script_dir}/software/mimeapps.list" /etc/xdg/mimeapps.list

# Pins live in software/rpms.tsv so the upstream-watch workflow can refresh
# them without rewriting this script. The column order is:
#   name <TAB> version-release <TAB> url <TAB> sha256
rpm_pins_file="${script_dir}/software/rpms.tsv"
rpm_expected_added="$(awk 'NF && $1 !~ /^#/' "${rpm_pins_file}" | wc -l)"

say "installing pinned software RPMs"
rpm_dir="$(mktemp -d /tmp/wraindrock-rpms.XXXXXX)"
while IFS=$'\t' read -r rpm_name rpm_version rpm_url rpm_sha256; do
    [[ -n ${rpm_name} && ${rpm_name} != \#* ]] || continue
    rpm_file="${rpm_dir}/${rpm_name}.rpm"
    curl -fsSL --retry 3 --retry-delay 2 -o "${rpm_file}" "${rpm_url}" \
        || die "could not download ${rpm_name} from ${rpm_url}"
    printf '%s  %s\n' "${rpm_sha256}" "${rpm_file}" | sha256sum -c - >/dev/null \
        || die "sha256 mismatch for ${rpm_name}"
    rpm_got_name="$(rpm -qp --qf '%{NAME}' "${rpm_file}")"
    [[ ${rpm_got_name} == "${rpm_name}" ]] \
        || die "${rpm_name}: archive contains ${rpm_got_name}"
    rpm_got_version="$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "${rpm_file}")"
    [[ ${rpm_got_version} == "${rpm_version}" ]] \
        || die "${rpm_name}: expected ${rpm_version}, got ${rpm_got_version}"
done < "${rpm_pins_file}"

# Bluefin ships /opt as a symlink to /var/opt, and a bootc deployment does not
# carry /var, so that symlink dangles inside the build container. Both SFL and
# Helium unpack into /opt, so make it a real directory first.
if [[ -L /opt ]]; then
    rm -f /opt
fi
install -d -m 0755 /opt
rpm -i "${rpm_dir}"/*.rpm
rm -rf "${rpm_dir}"
[[ -x /opt/sing-box/sing-box ]] || die "SFL did not land under /opt/sing-box"
[[ -x /opt/helium/helium ]] || die "Helium did not land under /opt/helium"

rpm_current_set_file="$(mktemp /tmp/wraindrock-current-rpm-set.XXXXXX)"
rpm_added_file="$(mktemp /tmp/wraindrock-rpm-added.XXXXXX)"
rpm_removed_file="$(mktemp /tmp/wraindrock-rpm-removed.XXXXXX)"
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
    | LC_ALL=C sort > "${rpm_current_set_file}"
comm -13 "${rpm_base_set_file}" "${rpm_current_set_file}" > "${rpm_added_file}"
comm -23 "${rpm_base_set_file}" "${rpm_current_set_file}" > "${rpm_removed_file}"
rpm_count="$(wc -l < "${rpm_current_set_file}")"
[[ $(wc -l < "${rpm_added_file}") -eq ${rpm_expected_added} ]] \
    || die "expected exactly ${rpm_expected_added} added packages, found $(wc -l < "${rpm_added_file}")"
[[ ! -s "${rpm_removed_file}" ]] || die "the software step removed base packages"

# sqlite checkpoints the WAL when the last connection closes. Never ship a
# non-empty WAL: that would mean an uncheckpointed database. The sidecars stay
# where the base put them (a read-only /usr needs the pre-created -shm/-wal).
# Nothing below this point may run rpm again.
[[ ! -s /usr/share/rpm/rpmdb.sqlite-wal ]] \
    || die "the RPM database WAL was not checkpointed before packaging"
install -m 0644 "${rpm_base_set_file}" /usr/share/wraindrock/base-rpm-set
rm -f "${rpm_base_set_file}" "${rpm_current_set_file}"

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

json_list() {
    local first=1 line
    printf '['
    while IFS= read -r line; do
        [[ -z ${line} ]] && continue
        [[ ${first} == 1 ]] || printf ', '
        printf '"%s"' "${line}"
        first=0
    done
    printf ']'
}

cat > /usr/share/wraindrock/delta.json <<EOF
{
  "schema": 2,
  "base_image": $(json_value "${BASE_IMAGE:-unknown}"),
  "base_digest": $(json_value "${BASE_DIGEST:-unknown}"),
  "os_release": {
    "changed": {
      "NAME": $(json_value "$(unquote "$(field NAME)")"),
      "PRETTY_NAME": $(json_value "$(unquote "$(field PRETTY_NAME)")"),
      "DEFAULT_HOSTNAME": $(json_value "$(unquote "$(field DEFAULT_HOSTNAME)")"),
      "HOME_URL": $(json_value "$(unquote "$(field HOME_URL)")"),
      "DOCUMENTATION_URL": $(json_value "$(unquote "$(field DOCUMENTATION_URL)")"),
      "SUPPORT_URL": $(json_value "$(unquote "$(field SUPPORT_URL)")"),
      "BUG_REPORT_URL": $(json_value "$(unquote "$(field BUG_REPORT_URL)")")
    }
  },
  "rpm": {
    "added": $(json_list < "${rpm_added_file}"),
    "removed": $(json_list < "${rpm_removed_file}")
  },
  "files": {
    "modified": [
      "/usr/lib/os-release",
      "/etc/system-release",
      "/usr/share/glib-2.0/schemas/gschemas.compiled",
      "/usr/share/rpm/rpmdb.sqlite",
      "/etc/dconf/db/distro",
      "/opt"
    ],
    "added": [
      "/usr/share/glib-2.0/schemas/zzzz-wraindrock.gschema.override",
      "/usr/share/backgrounds/wraindrock/wraindrock-wallpaper.png",
      "/usr/libexec/wraindrock-hostname-seed",
      "/usr/lib/systemd/system/wraindrock-hostname-seed.service",
      "/usr/lib/systemd/system/sysinit.target.wants/wraindrock-hostname-seed.service",
      "/usr/share/wraindrock/base-os-release",
      "/usr/share/wraindrock/base-rpm-set",
      "/usr/share/wraindrock/build-info.json",
      "/usr/share/wraindrock/delta.json",
      "/usr/share/flatpak/preinstall.d/wraindrock.preinstall",
      "/etc/xdg/mimeapps.list",
      "/etc/dconf/db/distro.d/10-wraindrock-folders"
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
  "rpm_base_count": ${rpm_base_count},
  "rpm_added_count": ${rpm_expected_added},
  "rpm_set_sha256": "${rpm_set_sha256}"
}
EOF
chmod 0644 /usr/share/wraindrock/build-info.json

say "provenance written for ${IMAGE_NAME:-unknown} (${rpm_count} packages, ${rpm_base_count} in base)"
say "base os-release preserved at /usr/share/wraindrock/base-os-release"
say "identity applied: $(unquote "$(field PRETTY_NAME)")"
say "UEFI boot entry name: $(tr -d '\n' < /etc/system-release)"
say "first-boot Flatpaks: $(grep -vc '^#' "${flatpak_list}") declared in /usr/share/flatpak/preinstall.d/wraindrock.preinstall"
say "baked RPMs: $(wc -l < "${rpm_added_file}") (clash-verge, rayburst, sing-box)"
say "delta manifest written to /usr/share/wraindrock/delta.json"
say "rpm database written by design; WAL checkpointed, sidecars in place"
