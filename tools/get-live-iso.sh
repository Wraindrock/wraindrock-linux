#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Fetch the newest Wraindrock live ISO from GitHub Releases, verify it and
# unpack it. No GitHub account is needed. Re-running the same command resumes
# parts that are already partially downloaded.
#
#   curl -fsSL https://raw.githubusercontent.com/Wraindrock/wraindrock-linux/main/tools/get-live-iso.sh | bash
#
# Options:
#   --out DIR    where to download/extract (default: current directory)
#   --dry-run    print the resolved release tag and asset names, download nothing
#   --help       show this help
# ---------------------------------------------------------------------------
set -euo pipefail

die() { printf 'get-live-iso: %s\n' "$*" >&2; exit 1; }

repo="Wraindrock/wraindrock-linux"
out="."
dry_run=0
while (( $# )); do
    case "$1" in
        --out) [[ $# -ge 2 ]] || die "--out needs a directory"; out="$2"; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) die "unknown argument: ${1}" ;;
    esac
done

command -v curl >/dev/null 2>&1 || die "curl is required"

# /releases/latest redirects to /releases/tag/<tag>; no API call, no rate limit.
tag="$(curl -fsSIL --retry 3 --retry-all-errors -o /dev/null -w '%{url_effective}' \
    "https://github.com/${repo}/releases/latest" \
    | sed -n 's#.*/releases/tag/##p')"
[[ -n ${tag} ]] || die "could not resolve the latest release tag"

base="https://github.com/${repo}/releases/download/${tag}"
parts=()
index=0
while :; do
    name="Wraindrock-Live-${tag}.zip.part-$(printf '%02d' "${index}")"
    code="$(curl -sIL --retry 2 --retry-all-errors -o /dev/null -w '%{http_code}' "${base}/${name}" || true)"
    [[ ${code} == 200 ]] || break
    parts+=("${name}")
    index=$(( index + 1 ))
done
(( ${#parts[@]} > 0 )) || die "no archive parts found for release ${tag}"
extract="Wraindrock-Live-${tag}-extract.sh"
assets=("${parts[@]}" "${extract}" "SHA256SUMS")

if (( dry_run )); then
    printf '%s\n' "${tag}" "${assets[@]}"
    exit 0
fi

mkdir -p "${out}"
cd "${out}"

# One asset, resumed where a previous run stopped. A release CDN may reset a
# TLS connection mid-transfer; retry with backoff and fall back to HTTP/1.1.
# The partial file is always kept, so a later rerun continues from it.
fetch() {
    local name=$1 attempt
    for attempt in 1 2 3 4 5; do
        if curl -fL --retry 3 --retry-delay 2 --retry-all-errors \
                --continue-at - -o "${name}" "${base}/${name}"; then
            return 0
        fi
        printf 'get-live-iso: %s failed (attempt %d); retrying\n' "${name}" "${attempt}" >&2
        if [[ ${attempt} -ge 3 ]]; then
            if curl -fL --http1.1 --retry 3 --retry-delay 2 --retry-all-errors \
                    --continue-at - -o "${name}" "${base}/${name}"; then
                return 0
            fi
        fi
        sleep $(( attempt * 3 ))
    done
    die "could not download ${name}; the partial file is kept, rerun to resume"
}

# Check an asset that is already on disk against the release checksums; the
# exit status means "this asset is complete and correct".
have_asset() {
    grep " $1\$" SHA256SUMS | sha256sum --check --strict - >/dev/null 2>&1
}

# Checksums first: they are small and let us verify every part before extracting.
# Never resume these two: a stale SHA256SUMS from another release would poison
# every later comparison, so always replace them with this release's copies.
fetch_fresh() {
    local name=$1
    rm -f "${name}"
    fetch "${name}"
}
fetch_fresh "SHA256SUMS"
grep -q "Wraindrock-Live-${tag}.zip.part-00" SHA256SUMS \
    || die "SHA256SUMS does not describe release ${tag}"
fetch_fresh "${extract}"
for asset in "${parts[@]}"; do
    if have_asset "${asset}"; then
        printf '%s already complete\n' "${asset}"
        continue
    fi
    printf 'downloading %s\n' "${asset}"
    fetch "${asset}"
    have_asset "${asset}" || die "checksum mismatch for ${asset}; delete it and rerun"
done
have_asset "${extract}" || die "checksum mismatch for ${extract}"

chmod +x "${extract}"
"./${extract}"
printf 'ISO ready: %s/Wraindrock-Live.iso\n' "$PWD"
printf 'sha256: %s\n' "$(sha256sum Wraindrock-Live.iso | cut -d' ' -f1)"
