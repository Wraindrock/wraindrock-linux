#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Fetch the newest Wraindrock live ISO from GitHub Releases, verify it and
# unpack it. No GitHub account is needed.
#
#   curl -fsSL https://raw.githubusercontent.com/Wraindrock/wraindrock-linux/main/tools/get-live-iso.sh | bash
#
# Options:
#   --out DIR    where to download/extract (default: current directory)
#   --dry-run    print the resolved release tag and asset names, download nothing
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
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) die "unknown argument: ${1}" ;;
    esac
done

command -v curl >/dev/null 2>&1 || die "curl is required"

# /releases/latest redirects to /releases/tag/<tag>; no API call, no rate limit.
tag="$(curl -fsSIL -o /dev/null -w '%{url_effective}' \
    "https://github.com/${repo}/releases/latest" \
    | sed -n 's#.*/releases/tag/##p')"
[[ -n ${tag} ]] || die "could not resolve the latest release tag"

base="https://github.com/${repo}/releases/download/${tag}"
parts=()
index=0
while :; do
    name="Wraindrock-Live-${tag}.zip.part-$(printf '%02d' "${index}")"
    code="$(curl -sIL -o /dev/null -w '%{http_code}' "${base}/${name}" || true)"
    [[ ${code} == 200 ]] || break
    parts+=("${name}")
    index=$(( index + 1 ))
done
(( ${#parts[@]} > 0 )) || die "no archive parts found for release ${tag}"
assets=("${parts[@]}" "Wraindrock-Live-${tag}-extract.sh" "SHA256SUMS")

if (( dry_run )); then
    printf '%s\n' "${tag}" "${assets[@]}"
    exit 0
fi

mkdir -p "${out}"
cd "${out}"
for asset in "${assets[@]}"; do
    printf 'downloading %s\n' "${asset}"
    curl -fL --retry 3 --retry-delay 2 -o "${asset}" "${base}/${asset}"
done
chmod +x "Wraindrock-Live-${tag}-extract.sh"
"./Wraindrock-Live-${tag}-extract.sh"
printf 'ISO ready: %s/Wraindrock-Live.iso\n' "$PWD"
printf 'sha256: %s\n' "$(sha256sum Wraindrock-Live.iso | cut -d' ' -f1)"
