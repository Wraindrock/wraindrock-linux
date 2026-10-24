#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Wraindrock image build step.
#
# Runs as root inside the pristine uBlue Silverblue base image. It does four
# things and nothing else:
#
#   1. prove the base is the uBlue Silverblue bootc image this project claims;
#   2. record provenance at /usr/share/wraindrock/build-info.json and preserve
#      the untouched base os-release and RPM set next to it;
#   3. apply the Wraindrock identity (os-release display fields,
#      dock, input method), restore the NVIDIA stack and the Bluefin desktop
#      extras (GNOME extensions, Docker, Incus, libvirt/QEMU, distrobox);
#   4. declare the first-boot Flatpaks, the Helium default browser, the pinned
#      RPMs and the IBus/libpinyin input-method default, then record every
#      applied difference in /usr/share/wraindrock/delta.json.
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
    || die "base is not uBlue Silverblue (VARIANT_ID=silverblue missing)"
base_variant_id="$(sed -n 's/^VARIANT_ID=//p' "${os_release}" | tail -n 1)"

[[ -x /usr/bin/bootc ]] || die "base does not ship the bootc CLI"
[[ -d /usr/lib/bootc ]] || die "base is not a bootc image (/usr/lib/bootc missing)"
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

# 3a. os-release. Keep VERSION, VERSION_ID, OSTREE_VERSION and SUPPORT_END from
# the base: update cadence and support window must stay honest. Only identity
# and links change.
sed -i \
    -e 's/^NAME=.*/NAME="Wraindrock"/' \
    -e 's/^PRETTY_NAME="Fedora Linux /PRETTY_NAME="Wraindrock /' \
    -e 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME="wraindrock"/' \
    -e 's|^HOME_URL=.*|HOME_URL="https://github.com/Wraindrock/wraindrock-linux"|' \
    -e 's|^DOCUMENTATION_URL=.*|DOCUMENTATION_URL="https://github.com/Wraindrock/wraindrock-linux/blob/main/docs/install.md"|' \
    -e 's|^SUPPORT_URL=.*|SUPPORT_URL="https://github.com/Wraindrock/wraindrock-linux/issues"|' \
    -e 's|^BUG_REPORT_URL=.*|BUG_REPORT_URL="https://github.com/Wraindrock/wraindrock-linux/issues"|' \
    "${os_release}"


grep -qx 'NAME="Wraindrock"' "${os_release}" \
    || die "failed to brand NAME"
grep -Eq '^PRETTY_NAME="Wraindrock [0-9]' "${os_release}" \
    || die "failed to brand PRETTY_NAME"
grep -qx 'ID=fedora' "${os_release}" || die "branding changed ID"
grep -qx 'CPE_NAME="cpe:/o:fedoraproject:fedora:44"' "${os_release}" \
    || die "branding changed CPE_NAME"
grep -qx 'DEFAULT_HOSTNAME="wraindrock"' "${os_release}" \
    || die "failed to brand DEFAULT_HOSTNAME"
grep -qx "VERSION_ID=${FEDORA_VERSION}" "${os_release}" \
    || die "branding changed VERSION_ID"
grep -qx "VARIANT_ID=${base_variant_id}" "${os_release}" \
    || die "branding changed VARIANT_ID"

# 3d. Default dock and input sources. Override files merge in name order,
# so zz- wins over Fedora's 10_* override.
gschema_dir=/usr/share/glib-2.0/schemas
override="${gschema_dir}/zzzz-wraindrock.gschema.override"
cat > "${override}" <<'EOF'
# Default dock: the user's working set, in this order. Left and right are the
# same list; a user's own favorite-apps setting always wins.
[org.gnome.shell]
favorite-apps=['helium.desktop', 'com.github.flxzt.rnote.desktop', 'com.ranfdev.DistroShelf.desktop', 'org.gnome.Nautilus.desktop', 'io.github.kolunmi.Bazaar.desktop', 'io.missioncenter.MissionCenter.desktop', 'org.gnome.Ptyxis.desktop']
enabled-extensions=['appindicatorsupport@rgcjonas.gmail.com', 'bazaar-integration@kolunmi.github.io', 'blur-my-shell@aunetx', 'dash-to-dock@micxgx.gmail.com', 'gradia-integration@alexandervanhee.github.io', 'logomenu@aryan_k', 'search-light@icedman.github.com']

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
expected_dock="['helium.desktop', 'com.github.flxzt.rnote.desktop', 'com.ranfdev.DistroShelf.desktop', 'org.gnome.Nautilus.desktop', 'io.github.kolunmi.Bazaar.desktop', 'io.missioncenter.MissionCenter.desktop', 'org.gnome.Ptyxis.desktop']"
actual_dock="$(GSETTINGS_BACKEND=memory gsettings get org.gnome.shell favorite-apps)"
[[ ${actual_dock} == "${expected_dock}" ]] \
    || die "the compiled schemas do not report the dock defaults: ${actual_dock}"
rpm -q ibus ibus-libpinyin google-noto-sans-cjk-fonts >/dev/null 2>&1 \
    || die "IBus, libpinyin or the CJK fonts are missing from the base"
if rpm -q fcitx5 >/dev/null 2>&1; then
    die "fcitx5 is installed; the default must stay IBus"
fi

# 3d-bis. GNOME extensions and their dconf presets. The uBlue Silverblue base
# ships Fedora's standard shell extensions; the Bluefin DX set (blur,
# Logo Menu, Search Light, AppIndicator support, Bazaar/Gradia integration,
# Dash to Dock, Caffeine) is vendored under software/gnome-extensions.
install -d /usr/share/gnome-shell/extensions
cp -a "${script_dir}/gnome-extensions/." /usr/share/gnome-shell/extensions/
for ext in appindicatorsupport@rgcjonas.gmail.com bazaar-integration@kolunmi.github.io \
    blur-my-shell@aunetx caffeine@patapon.info dash-to-dock@micxgx.gmail.com \
    gradia-integration@alexandervanhee.github.io \
    logomenu@aryan_k search-light@icedman.github.com; do
    [[ -r "/usr/share/gnome-shell/extensions/${ext}/metadata.json" ]] \
        || die "extension ${ext} is missing"
done
# GNOME launches ESM extensions from the system directory, but their settings
# schemas must live in the system schema directory. Bluefin built them that
# way; vendored extensions ship schemas/ next to their code. The per-extension
# gschemas.compiled is generated here (it is gitignored): Extension Manager and
# the shell's settings helper open <extension>/schemas/gschemas.compiled
# directly, so shipping only the XML is not enough.
for schemas_dir in /usr/share/gnome-shell/extensions/*/schemas; do
    [[ -d ${schemas_dir} ]] || continue
    compgen -G "${schemas_dir}/*.gschema.xml" >/dev/null || continue
    glib-compile-schemas "${schemas_dir}"
    [[ -s ${schemas_dir}/gschemas.compiled ]] \
        || die "could not compile extension schemas in ${schemas_dir}"
done
for schema in "${script_dir}"/gnome-extensions/*/schemas/*.xml; do
    [[ -e ${schema} ]] || continue
    install -m 0644 "${schema}" /usr/share/glib-2.0/schemas/
done
glib-compile-schemas /usr/share/glib-2.0/schemas
GSETTINGS_BACKEND=memory gsettings get org.gnome.shell.extensions.logo-menu symbolic-icon >/dev/null \
    || die "the official Logo Menu schema did not install"
install -d /etc/dconf/db/distro.d
for preset in "${script_dir}"/dconf/*; do
    install -m 0644 "${preset}" "/etc/dconf/db/distro.d/$(basename "${preset}")"
done

# Fedora 44 repositories and the Docker CE repository. The uBlue base ships no
# repo configuration, and both the NVIDIA dependency resolution and the DX
# stack below need one.
cat > /etc/yum.repos.d/wraindrock-fedora.repo <<'EOF'
[fedora-wraindrock]
name=Fedora $releasever - $basearch
baseurl=https://mirrors.kernel.org/fedora/releases/44/Everything/x86_64/os/
enabled=1
gpgcheck=0
countme=0

[fedora-wraindrock-updates]
name=Fedora $releasever updates
baseurl=https://mirrors.kernel.org/fedora/updates/44/Everything/x86_64/
enabled=1
gpgcheck=0
countme=0
EOF
# 3d-ter. NVIDIA driver stack. The uBlue base is driver-neutral, so CI stages
# the matching akmods-nvidia-open RPMs (kernel modules + userland) under
# software/nvidia-rpms before the build; install them exactly as shipped.
nvidia_dir="${script_dir}/nvidia-rpms"
[[ -d ${nvidia_dir} ]] || die "NVIDIA RPMs were not staged (CI must download akmods-nvidia-open)"
mapfile -d '' nvidia_rpms < <(find "${nvidia_dir}/kmods" "${nvidia_dir}/nvidia" \
    -type f -name '*.rpm' ! -name '*.i686.rpm' -print0)
[[ ${#nvidia_rpms[@]} -gt 0 ]] || die "no x86_64 NVIDIA RPMs were staged"
# The addons package supplies the NVIDIA repo definitions; installing the
# driver itself needs the EGL/OpenCL/Xorg pieces those repos provide.
rpm -i "${nvidia_dir}"/ublue-os/ublue-os-nvidia-addons-*.rpm
dnf5 -y config-manager setopt 'fedora-nvidia*.enabled=1' 'nvidia-container-toolkit.enabled=1'
dnf5 -y install --setopt=install_weak_deps=False \
    xorg-x11-server-Xorg opencl-filesystem egl-gbm egl-x11 egl-wayland2 \
    nvidia-driver-selinux nvidia-container-toolkit
rpm -i "${nvidia_rpms[@]}"
rpm -q kmod-nvidia nvidia-driver >/dev/null 2>&1 || die "NVIDIA driver stack did not install"
[[ -x /usr/bin/nvidia-smi ]] || die "nvidia-smi is missing"
nvidia_kver="$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}')"
[[ -d "/usr/lib/modules/${nvidia_kver}/extra/nvidia" ]] \
    || die "NVIDIA modules are missing for kernel ${nvidia_kver}"

# 3e. UEFI boot entry name. bootupd labels the firmware entry from
# /etc/system-release when it exists (Bluefin's symlink says "Fedora release
# ..."), falling back to os-release NAME. Ship a real file so installs and
# bootloader updates name the entry "Wraindrock".
system_release=/etc/system-release
rm -f "${system_release}"
printf 'Wraindrock release %s (Silverblue)\n' "${FEDORA_VERSION}" > "${system_release}"
chmod 0644 "${system_release}"
grep -Eq '^Wraindrock release [0-9]' "${system_release}" \
    || die "failed to brand /etc/system-release"

# 3f. Application folders. Bluefin ships seven folders through a distro dconf
# database. Our drop-in only adds the Wraindrock folders and excludes the apps
# we re-home from Bluefin's folders, so every app appears in exactly one place.
dconf_dir=/etc/dconf/db/distro.d
install -d -m 0755 "${dconf_dir}"
folders_file="${dconf_dir}/10-wraindrock-folders"
install -m 0644 "${script_dir}/software/app-folders" "${folders_file}"
directories_dir=/usr/share/desktop-directories
install -d -m 0755 "${directories_dir}"
for name in accessories system hp tools development; do
    install -m 0644 "${script_dir}/software/wraindrock-${name}.directory" \
        "${directories_dir}/wraindrock-${name}.directory"
done
command -v dconf >/dev/null 2>&1 || die "dconf is required to compile the app-folder database"
dconf update
for folder in Accessories System HP Tools Development; do
    grep -Eq "folder-children=.*'${folder}'" "${folders_file}" \
        || die "the folder-children list is missing ${folder}"
done
for name in accessories system hp tools development; do
    grep -Fq "name='wraindrock-${name}.directory'" "${folders_file}" \
        || die "the ${name} folder does not use its localized directory file"
    [[ -s ${directories_dir}/wraindrock-${name}.directory ]] \
        || die "the ${name} directory file is missing"
done
grep -aq 'wraindrock-accessories.directory' /etc/dconf/db/distro \
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

# Scanner stack inherited from Bluefin. sane-airscan drives eSCL/WSD
# scanners without vendor plugins; assert it stays in the base.
rpm -q sane-airscan sane-backends-drivers-scanners >/dev/null \
    || die "the base lost sane-airscan or the scanner drivers"

# --- 3g-bis. Selected system tools -----------------------------------------
# The uBlue Silverblue base has no Fedora repository configuration, so add the
# repositories above and install only the stack this system actually uses:
# virtualization (KVM/libvirt/virt-manager, Incus, Distrobox), the development
# toolchain, extra fonts, LXC and cockpit. Docker and VS Code are deliberately
# not installed.
dnf5 -y install --setopt=install_weak_deps=False \
    incus incus-client distrobox \
    virt-manager virt-install libvirt-daemon-kvm libvirt-client libvirt-daemon-config-network \
    qemu-system-x86-core qemu-img libsane-hpaio \
    firewall-config input-remapper sysprof \
    gcc gcc-c++ clang llvm make cmake ninja-build meson autoconf automake \
    libtool pkgconf-pkg-config binutils bison flex gdb strace patch diffutils \
    python3-devel python3-pip rpm-build redhat-rpm-config \
    jetbrains-mono-fonts jetbrains-mono-nl-fonts cascadia-code-fonts \
    adwaita-fonts-all rsms-inter-fonts \
    lxc lxc-libs lxc-templates lxcfs \
    cockpit-bridge cockpit-system cockpit-machines cockpit-networkmanager \
    cockpit-podman cockpit-storaged cockpit-selinux \
    libayatana-appindicator-gtk3 libXScrnSaver webkit2gtk4.1 \
    openssl nss polkit xdg-utils at-spi2-core libnotify libXtst libuuid \
    qpdf zstd
command -v incus >/dev/null || die "Incus did not install"
command -v virt-manager >/dev/null || die "virt-manager did not install"
command -v distrobox >/dev/null || die "distrobox did not install"
command -v gcc >/dev/null || die "the development toolchain did not install"
rpm -q lxc cockpit-system >/dev/null || die "LXC or cockpit did not install"
[[ ! -e /usr/bin/docker ]] || die "Docker must not be installed"
[[ ! -e /usr/bin/code ]] || die "VS Code must not be installed"

# The uBlue base ships flatpak but neither the Flathub remote nor the Bazaar
# override that lets the store manage system Flatpaks, so provide both.
flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

# Install the declared Flatpaks into the image itself, so a machine without
# network still has them after install. The first-boot preinstall service
# remains as a fallback for anything that failed to download here.
mapfile -t baked_flatpaks < <(grep -v '^#' "${script_dir}/software/flatpaks.txt" | sed '/^[[:space:]]*$/d')
# Some app manifests use apply_extra, which runs bubblewrap. The build
# container exposes /proc/sys read-only, so bwrap cannot start there; bake
# what works and let the first-boot service fill in the rest when online.
for flatpak_app in "${baked_flatpaks[@]}"; do
    if flatpak install --system --noninteractive -y --app flathub "${flatpak_app}"; then
        say "baked Flatpak ${flatpak_app}"
    else
        say "warning: ${flatpak_app} cannot be baked here; the first-boot service will install it"
    fi
done
flatpak list --system --app --columns=application | LC_ALL=C sort > /tmp/baked-flatpaks
for flatpak_app in io.github.kolunmi.Bazaar io.podman_desktop.PodmanDesktop; do
    grep -Fxq "${flatpak_app}" /tmp/baked-flatpaks \
        || die "Flatpak ${flatpak_app} was not baked into the image"
done
install -d /usr/share/ublue-os/flatpak-overrides
install -m 0644 "${script_dir}/software/flatpak-overrides/io.github.kolunmi.Bazaar" \
    /usr/share/ublue-os/flatpak-overrides/io.github.kolunmi.Bazaar
install -m 0644 "${script_dir}/software/bazaar-flatpak.conf" \
    /usr/lib/tmpfiles.d/bazaar-flatpak.conf

# --- 3g-quater. ipp-duplexd (upstream ships .deb only) ----------------------
# A dependency-free Rust daemon; upstream publishes Arch and Debian packages,
# so take the pinned .deb, verify it and install its small file set.
ipp_pin="${script_dir}/software/ipp-duplexd.tsv"
IFS=$'\t' read -r ipp_name ipp_version ipp_url ipp_sha256 < "${ipp_pin}"
[[ -n ${ipp_name} && ${ipp_name} != \#* ]] || die "ipp-duplexd pin is missing"
ipp_tmp="$(mktemp -d /tmp/wraindrock-ipp.XXXXXX)"
curl -fsSL --retry 3 --retry-delay 2 -o "${ipp_tmp}/ipp.deb" "${ipp_url}" \
    || die "could not download ${ipp_name}"
printf '%s  %s\n' "${ipp_sha256}" "${ipp_tmp}/ipp.deb" | sha256sum -c - >/dev/null \
    || die "sha256 mismatch for ${ipp_name}"
python3 - "${ipp_tmp}/ipp.deb" "${ipp_tmp}" <<'PYIPP'
import sys

data = open(sys.argv[1], "rb").read()
assert data[:8] == b"!<arch>\n", "not a Debian archive"
pos = 8
found = False
while pos < len(data):
    header = data[pos:pos + 60]
    name = header[:16].decode().strip()
    size = int(header[48:58].decode().strip())
    body = data[pos + 60:pos + 60 + size]
    if name.startswith("data.tar"):
        open(sys.argv[2] + "/data.tar.zst", "wb").write(body)
        found = True
    pos += 60 + size + (size % 2)
assert found, "data.tar member is missing"
PYIPP
mkdir -p "${ipp_tmp}/root"
tar --zstd -x -f "${ipp_tmp}/data.tar.zst" -C "${ipp_tmp}/root"
install -D -m 0755 "${ipp_tmp}/root/usr/bin/ipp-duplexd" /usr/bin/ipp-duplexd
install -D -m 0755 "${ipp_tmp}/root/usr/bin/ipp-duplexd-setup" /usr/bin/ipp-duplexd-setup
install -D -m 0644 "${ipp_tmp}/root/usr/lib/systemd/user/ipp-duplexd.service" \
    /usr/lib/systemd/user/ipp-duplexd.service
install -d /usr/share/doc/ipp-duplexd
for doc in README.md changelog.gz copyright ipp-duplexd.conf.example; do
    install -m 0644 "${ipp_tmp}/root/usr/share/doc/ipp-duplexd/${doc}" \
        "/usr/share/doc/ipp-duplexd/${doc}"
done
[[ -x /usr/bin/ipp-duplexd && -x /usr/bin/ipp-duplexd-setup ]] \
    || die "ipp-duplexd binaries are missing"
[[ -r /usr/lib/systemd/user/ipp-duplexd.service ]] \
    || die "ipp-duplexd user unit is missing"
ipp_help="$(/usr/bin/ipp-duplexd --help 2>&1 || true)"
grep -Fq -- '--printer' <<<"${ipp_help}" || die "ipp-duplexd did not run"
say "installed ipp-duplexd ${ipp_version}"
rm -rf "${ipp_tmp}"

# --- 3h. software defaults --------------------------------------------------
# The pinned set now also carries the full HPLIP GUI stack and TuxTalk; the
# hplip-gui row is selected by matching the inherited hplip core version.
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

# Bluefin's preinstall service gives up after three attempts, before a laptop
# has joined Wi-Fi. A timer retries our wrapper until the preinstall file's
# hash is recorded, so a fresh install finishes installing Flatpaks minutes
# after the network comes up.
install -d -m 0755 /usr/libexec /etc/systemd/system/timers.target.wants
install -m 0755 "${script_dir}/software/wraindrock-flatpak-preinstall" \
    /usr/libexec/wraindrock-flatpak-preinstall
install -m 0644 "${script_dir}/software/wraindrock-flatpak-preinstall.service" \
    /usr/lib/systemd/system/wraindrock-flatpak-preinstall.service
install -m 0644 "${script_dir}/software/wraindrock-flatpak-preinstall.timer" \
    /usr/lib/systemd/system/wraindrock-flatpak-preinstall.timer
ln -sfn /usr/lib/systemd/system/wraindrock-flatpak-preinstall.timer \
    /etc/systemd/system/timers.target.wants/wraindrock-flatpak-preinstall.timer
[[ -e /etc/systemd/system/timers.target.wants/wraindrock-flatpak-preinstall.timer ]] \
    || die "the Flatpak preinstall timer is not enabled"

# Dell G15/G16 control center: the upstream installer writes to /var/opt and
# starts a daemon, so it runs on the first boot of matching hardware instead of
# at image build time. The wrapper pins a commit and the tarball's sha256.
install -m 0755 "${script_dir}/software/wraindrock-g15-install" \
    /usr/libexec/wraindrock-g15-install
install -m 0644 "${script_dir}/software/wraindrock-g15-install.service" \
    /usr/lib/systemd/system/wraindrock-g15-install.service
ln -sfn /usr/lib/systemd/system/wraindrock-g15-install.service \
    /etc/systemd/system/multi-user.target.wants/wraindrock-g15-install.service
[[ -x /usr/libexec/wraindrock-g15-install ]] \
    || die "the G15 installer is not executable"
[[ -e /etc/systemd/system/multi-user.target.wants/wraindrock-g15-install.service ]] \
    || die "the G15 installer service is not enabled"

# Pins live in software/rpms.tsv so the upstream-watch workflow can refresh
# them without rewriting this script. The column order is:
#   name <TAB> version-release <TAB> url <TAB> sha256 [<TAB> name=version-release]
# The optional condition selects a row only when the base ships that exact
# version (for example, a GUI package that must match an inherited core).
rpm_pins_file="${script_dir}/software/rpms.tsv"
rpm_active_pins="$(mktemp /tmp/wraindrock-active-pins.XXXXXX)"
rpm_pin_active() {
    local condition="$1" want_name want_version have_version
    [[ -n ${condition} ]] || return 0
    want_name="${condition%%=*}"
    want_version="${condition#*=}"
    have_version="$(rpm -q --qf '%{VERSION}-%{RELEASE}' "${want_name}" 2>/dev/null)" || return 1
    [[ ${have_version} == "${want_version}" ]]
}
while IFS=$'\t' read -r rpm_name rpm_version rpm_url rpm_sha256 rpm_condition; do
    [[ -n ${rpm_name} && ${rpm_name} != \#* ]] || continue
    rpm_pin_active "${rpm_condition:-}" || continue
    printf '%s\t%s\t%s\t%s\n' "${rpm_name}" "${rpm_version}" "${rpm_url}" "${rpm_sha256}" \
        >> "${rpm_active_pins}"
done < "${rpm_pins_file}"
rpm_expected_added="$(wc -l < "${rpm_active_pins}")"
[[ ${rpm_expected_added} -gt 0 ]] || die "no RPM pin matches this base image"

say "installing pinned software RPMs"
rpm_dir="$(mktemp -d /tmp/wraindrock-rpms.XXXXXX)"
while IFS=$'\t' read -r rpm_name rpm_version rpm_url rpm_sha256; do
    [[ -n ${rpm_name} ]] || continue
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
done < "${rpm_active_pins}"

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
[[ -x /usr/bin/hp-setup ]] || die "HPLIP did not install /usr/bin/hp-setup"
[[ -x /usr/bin/hp-toolbox ]] || die "hplip-gui did not install /usr/bin/hp-toolbox"
[[ -e /usr/share/applications/hplip.desktop ]] || die "hplip-gui did not install its desktop entry"
[[ -x /usr/bin/tuxtalk ]] || die "TuxTalk did not install /usr/bin/tuxtalk"
[[ -e /usr/share/applications/io.github.ronb1964.TuxTalk.desktop ]] \
    || die "TuxTalk did not install its desktop entry"
[[ -x /usr/lib/cups/backend/hp ]] || die "HPLIP did not install the CUPS backend"
[[ -e /usr/lib64/sane/libsane-hpaio.so.1 ]] || die "HPLIP did not install the SANE backend"

# Remove the two stock Silverblue applications that Bluefin (and Wraindrock)
# replace with Bazaar and Helium, plus the Fedora browser config that only
# existed for Firefox.
removed_apps=(firefox firefox-langpacks gnome-software fedora-bookmarks
    fedora-chromium-config fedora-chromium-config-gnome yelp)
dnf5 remove -y --no-autoremove "${removed_apps[@]}"
for app in firefox gnome-software; do
    rpm -q "${app}" >/dev/null 2>&1 && die "${app} is still installed"
done
[[ ! -e /usr/share/applications/firefox.desktop ]] || die "Firefox desktop entry is still present"
[[ ! -e /usr/share/applications/org.gnome.Software.desktop ]] || die "GNOME Software desktop entry is still present"

rpm_current_set_file="$(mktemp /tmp/wraindrock-current-rpm-set.XXXXXX)"
rpm_added_file="$(mktemp /tmp/wraindrock-rpm-added.XXXXXX)"
rpm_removed_file="$(mktemp /tmp/wraindrock-rpm-removed.XXXXXX)"
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
    | LC_ALL=C sort > "${rpm_current_set_file}"
comm -13 "${rpm_base_set_file}" "${rpm_current_set_file}" > "${rpm_added_file}"
comm -23 "${rpm_base_set_file}" "${rpm_current_set_file}" > "${rpm_removed_file}"
rpm_count="$(wc -l < "${rpm_current_set_file}")"
rpm_added_count="$(wc -l < "${rpm_added_file}")"
while IFS=$'\t' read -r pin_name pin_version _pin_url _pin_sha; do
    [[ -n ${pin_name} ]] || continue
    installed_version="$(rpm -q --qf '%{VERSION}-%{RELEASE}' "${pin_name}" 2>/dev/null)" \
        || die "pinned package ${pin_name} is not installed"
    [[ ${installed_version} == "${pin_version}" ]] \
        || die "${pin_name}: expected ${pin_version}, installed ${installed_version}"
done < "${rpm_active_pins}"
[[ $(wc -l < "${rpm_removed_file}") -eq ${#removed_apps[@]} ]] \
    || die "unexpected package removals: $(paste -sd' ' "${rpm_removed_file}")"
while IFS= read -r gone; do
    [[ -n ${gone} ]] || continue
    rpm -q "${gone}" >/dev/null 2>&1 && die "expected ${gone} to be removed"
done < "${rpm_removed_file}"
for gone in "${removed_apps[@]}"; do
    rpm -q "${gone}" >/dev/null 2>&1 && die "expected ${gone} to be removed"
done

# sqlite checkpoints the WAL when the last connection closes. Never ship a
# non-empty WAL: that would mean an uncheckpointed database. The sidecars stay
# where the base put them (a read-only /usr needs the pre-created -shm/-wal).
# Nothing below this point may run rpm again.
[[ ! -s /usr/share/rpm/rpmdb.sqlite-wal ]] \
    || die "the RPM database WAL was not checkpointed before packaging"
install -m 0644 "${rpm_base_set_file}" /usr/share/wraindrock/base-rpm-set
# The pins were verified above; ship them so parity can compare what rpm
# actually installed against what we asked for, without carrying the TSV.
awk -F'\t' '{ printf "%s\t%s\n", $1, $2 }' "${rpm_active_pins}" \
    > /usr/share/wraindrock/rpm-pins
rm -f "${rpm_active_pins}"
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
      "/usr/libexec/wraindrock-hostname-seed",
      "/usr/lib/systemd/system/wraindrock-hostname-seed.service",
      "/usr/lib/systemd/system/sysinit.target.wants/wraindrock-hostname-seed.service",
      "/usr/share/wraindrock/base-os-release",
      "/usr/share/wraindrock/base-rpm-set",
      "/usr/share/wraindrock/rpm-pins",
      "/usr/share/wraindrock/build-info.json",
      "/usr/share/wraindrock/delta.json",
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
      "/usr/share/desktop-directories/wraindrock-development.directory",
      "/usr/share/desktop-directories/wraindrock-tools.directory",
      "/usr/share/desktop-directories/wraindrock-hp.directory",
      "/usr/share/desktop-directories/wraindrock-system.directory",
      "/usr/share/desktop-directories/wraindrock-accessories.directory",
      "/usr/share/gnome-shell/extensions/appindicatorsupport@rgcjonas.gmail.com",
      "/usr/share/gnome-shell/extensions/bazaar-integration@kolunmi.github.io",
      "/usr/share/gnome-shell/extensions/blur-my-shell@aunetx",
      "/usr/share/gnome-shell/extensions/caffeine@patapon.info",
      "/usr/share/gnome-shell/extensions/dash-to-dock@micxgx.gmail.com",
      "/usr/share/gnome-shell/extensions/gradia-integration@alexandervanhee.github.io",
      "/usr/share/gnome-shell/extensions/logomenu@aryan_k",
      "/usr/share/gnome-shell/extensions/search-light@icedman.github.com",
      "/etc/dconf/db/distro.d/20-wraindrock-keybindings",
      "/etc/dconf/db/distro.d/21-wraindrock-logomenu",
      "/etc/dconf/db/distro.d/22-wraindrock-searchlight",
      "/etc/dconf/db/distro.d/23-wraindrock-blur",
      "/usr/share/ublue-os/flatpak-overrides/io.github.kolunmi.Bazaar",
      "/usr/lib/tmpfiles.d/bazaar-flatpak.conf",
      "/etc/flatpak/remotes.d/flathub.flatpakrepo",
      "/usr/bin/ipp-duplexd",
      "/usr/bin/ipp-duplexd-setup",
      "/usr/lib/systemd/user/ipp-duplexd.service",
      "/usr/share/doc/ipp-duplexd/README.md",
      "/usr/share/doc/ipp-duplexd/changelog.gz",
      "/usr/share/doc/ipp-duplexd/copyright",
      "/usr/share/doc/ipp-duplexd/ipp-duplexd.conf.example",
      "/usr/bin/hp-toolbox",
      "/usr/share/applications/hplip.desktop",
      "/usr/bin/tuxtalk",
      "/usr/bin/talktype",
      "/usr/share/applications/io.github.ronb1964.TuxTalk.desktop",
      "/usr/share/icons/hicolor/scalable/apps/io.github.ronb1964.TuxTalk.svg",
      "/usr/share/pixmaps/io.github.ronb1964.TuxTalk.png",
      "/usr/share/licenses/tuxtalk/LICENSE",
      "/usr/share/licenses/tuxtalk/THIRD_PARTY_LICENSES.md",
      "/opt/talktype"
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
  "parity": "silverblue-${FEDORA_VERSION:-unknown}",
  "rpm_count": ${rpm_count},
  "rpm_base_count": ${rpm_base_count},
  "rpm_added_count": ${rpm_added_count},
  "rpm_pinned_count": ${rpm_expected_added},
  "rpm_set_sha256": "${rpm_set_sha256}"
}
EOF
chmod 0644 /usr/share/wraindrock/build-info.json

say "provenance written for ${IMAGE_NAME:-unknown} (${rpm_count} packages, ${rpm_base_count} in base)"
say "base os-release preserved at /usr/share/wraindrock/base-os-release"
say "identity applied: $(unquote "$(field PRETTY_NAME)")"
say "UEFI boot entry name: $(tr -d '\n' < /etc/system-release)"
say "first-boot Flatpaks: $(grep -vc '^#' "${flatpak_list}") declared in /usr/share/flatpak/preinstall.d/wraindrock.preinstall"
say "baked RPMs: $(wc -l < "${rpm_added_file}") (pinned in software/rpms.tsv)"
say "delta manifest written to /usr/share/wraindrock/delta.json"
say "rpm database written by design; WAL checkpointed, sidecars in place"
