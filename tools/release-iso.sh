#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Turn an installer ISO into a split, self-extracting release:
#
#   tools/release-iso.sh artifacts/iso/Wraindrock-Live.iso 44.20261019T132911Z.55 \
#       artifacts/release
#
# Produces, in the output directory:
#   Wraindrock-Live-<version>.zip.part-NN         split parts (< 2 GiB each)
#   Wraindrock-Live-<version>-extract.sh          self-extracting verifier
#   SHA256SUMS                                    hashes of every file above
#
# The extractor checks every part, concatenates them back into the zip, unpacks
# the ISO and verifies its sha256. On Windows, `copy /b` the parts in order and
# open the result with PeaZip, 7-Zip or WinRAR.
# ---------------------------------------------------------------------------
set -euo pipefail

die() { printf 'release-iso: %s\n' "$*" >&2; exit 1; }

iso="${1:-}"
version="${2:-}"
out="${3:-artifacts/release}"
volume="${4:-1850M}"

[[ -f ${iso} ]] || die "usage: $0 ISO VERSION [OUTDIR] [VOLUME_SIZE]"
[[ -n ${version} ]] || die "version is required (used in the file names)"
[[ ${version} =~ ^[A-Za-z0-9._-]+$ ]] || die "unsafe version string: ${version}"
command -v zip >/dev/null || die "zip is required"
command -v unzip >/dev/null || die "unzip is required"
command -v sha256sum >/dev/null || die "sha256sum is required"

iso_name="$(basename "${iso}")"
iso_sha="$(sha256sum "${iso}" | awk '{print $1}')"
iso_size="$(stat -c %s "${iso}")"
base="Wraindrock-Live-${version}"
out_abs="$(realpath -m "${out}")"
iso_dir="$(dirname "$(realpath "${iso}")")"

mkdir -p "${out_abs}"
rm -f "${out_abs}/${base}".z?? "${out_abs}/${base}.zip" \
      "${out_abs}/${base}.zip.part-"* "${out_abs}/${base}-extract.sh" \
      "${out_abs}/SHA256SUMS"

printf 'compressing %s (%s bytes) and splitting into %s parts …\n' \
    "${iso_name}" "${iso_size}" "${volume}"
# Deterministic archive: fixed mtime and no host-specific extra fields, so a
# rebuilt release from the same ISO has the same bytes and hashes.
touch -d @0 "${iso}"
(
    cd "${iso_dir}"
    TZ=UTC zip -q -6 -X "${out_abs}/${base}.zip" "${iso_name}"
)
split -b "${volume}" -d -a 2 "${out_abs}/${base}.zip" "${out_abs}/${base}.zip.part-"
rm -f "${out_abs}/${base}.zip"

mapfile -t parts < <(
    find "${out_abs}" -maxdepth 1 -type f \
        -name "${base}.zip.part-*" -printf '%f\n' | LC_ALL=C sort
)
(( ${#parts[@]} > 0 )) || die "no parts were produced"

extractor="${out_abs}/${base}-extract.sh"
{
    cat <<EOF
#!/usr/bin/env bash
# Self-extracting installer for the Wraindrock ISO. Keep this script next to
# all ${base}.z* volumes, then run: bash $(basename "${extractor}")
set -euo pipefail

here="\$(cd "\$(dirname "\$0")" && pwd)"
tmp="\$(mktemp -d "\${here}/.wraindrock-extract.XXXXXX")"
trap 'rm -rf "\${tmp}"' EXIT

verify() {
    local hash="\$1" file="\$2"
    printf '%s  %s\n' "\${hash}" "\${file}" | sha256sum -c --status - \\
        || { printf 'checksum failed: %s\n' "\${file}" >&2; exit 1; }
}

command -v zip >/dev/null || { echo 'zip is required (install zip/unzip)' >&2; exit 1; }
command -v unzip >/dev/null || { echo 'unzip is required' >&2; exit 1; }
EOF
    for part in "${parts[@]}"; do
        hash="$(sha256sum "${out_abs}/${part}" | awk '{print $1}')"
        printf 'verify %q "%s"\n' "${hash}" "${part}"
    done
    cat <<EOF

echo 'joining parts …'
cat "\${here}/${base}.zip.part-"* > "\${tmp}/${base}.zip"
echo 'extracting …'
unzip -o -q "\${tmp}/${base}.zip" -d "\${here}"
verify '${iso_sha}' "\${here}/${iso_name}"
echo
echo "ready: \${here}/${iso_name} (sha256 ${iso_sha})"
EOF
} > "${extractor}"
chmod 0755 "${extractor}"

(
    cd "${out_abs}"
    sha256sum "${parts[@]}" "$(basename "${extractor}")" > SHA256SUMS
)

echo
printf 'parts:\n'
ls -l "${out_abs}" | sed 's/^/  /'
printf '\nISO sha256: %s\n' "${iso_sha}"
