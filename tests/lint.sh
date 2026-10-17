#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Repository self check. Runs on every pull request and locally via
# `just check`. Deliberately dependency-light: bash, grep and coreutils, with
# optional shellcheck / actionlint upgrades when they are installed.
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")/.."

failures=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  fail %s\n' "$1"; failures=$((failures + 1)); }

echo "shell syntax"
shell_files=()
while IFS= read -r file; do shell_files+=("$file"); done < <(
    find . -path ./.git -prune -o -type f -name '*.sh' -print | sort
)
for file in "${shell_files[@]}"; do
    if bash -n "${file}"; then
        pass "${file}"
    else
        fail "${file} (bash -n)"
    fi
done

echo "executable bits"
for file in "${shell_files[@]}" Justfile; do
    if [[ -x ${file} || ${file} == Justfile ]]; then
        pass "${file}"
    else
        fail "${file} is not executable"
    fi
done

echo "image.env"
env_file=./image.env
if [[ -r ${env_file} ]]; then
    pass "${env_file} exists"
    # shellcheck disable=SC1090
    . "${env_file}"
    required=(IMAGE_NAME REPO_ORGANIZATION IMAGE_DESC IMAGE_LICENSE
              FEDORA_VERSION BASE_IMAGE DEFAULT_TAG)
    for key in "${required[@]}"; do
        if [[ -n ${!key:-} ]]; then
            pass "${key}=${!key}"
        else
            fail "${key} is empty or unset"
        fi
    done
    if [[ -z ${IMAGE_NAME:-} || ${IMAGE_NAME} =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
        pass "IMAGE_NAME is a valid image name"
    else
        fail "IMAGE_NAME must be lowercase [a-z0-9._-]"
    fi
    if [[ ${BASE_IMAGE:-} == *"silverblue:${FEDORA_VERSION:-}"* ]]; then
        pass "BASE_IMAGE tracks Fedora ${FEDORA_VERSION}"
    else
        fail "BASE_IMAGE (${BASE_IMAGE:-}) does not match FEDORA_VERSION (${FEDORA_VERSION:-})"
    fi
    if [[ ${DEFAULT_TAG:-} == "${FEDORA_VERSION:-}" ]]; then
        pass "DEFAULT_TAG is the Fedora channel tag"
    else
        fail "DEFAULT_TAG (${DEFAULT_TAG:-}) must equal FEDORA_VERSION (${FEDORA_VERSION:-})"
    fi
    # The workflow sources this file; an unquoted value with spaces would be
    # parsed as a command. Every assignment must be quoted.
    if grep -Eq '^[A-Z_]+=[^"#]' "${env_file}"; then
        fail "image.env has an unquoted assignment"
    else
        pass "image.env assignments are quoted"
    fi
else
    fail "${env_file} is missing"
fi

echo "Containerfile"
containerfile=./Containerfile
if [[ -r ${containerfile} ]]; then
    pass "${containerfile} exists"
    for needle in \
        'FROM ${BASE_REF}' \
        'RUN bootc container lint' \
        'CMD ["/sbin/init"]' \
        'org.opencontainers.image.source=' \
        'org.wrainrock.base.image='; do
        if grep -Fq "${needle}" "${containerfile}"; then
            pass "Containerfile contains ${needle}"
        else
            fail "Containerfile is missing ${needle}"
        fi
    done
else
    fail "${containerfile} is missing"
fi

echo "branding"
for asset in \
    build_files/branding/wrainrock-logo-icon.svg \
    build_files/branding/wrainrock-gdm-logo.svg \
    build_files/branding/wrainrock-gdm-logo.png \
    build_files/branding/wrainrock-wallpaper.svg \
    build_files/branding/wrainrock-wallpaper.png; do
    if [[ -s ${asset} ]]; then
        pass "${asset} exists"
    else
        fail "${asset} is missing"
    fi
done
for svg in \
    build_files/branding/wrainrock-logo-icon.svg \
    build_files/branding/wrainrock-gdm-logo.svg \
    build_files/branding/wrainrock-wallpaper.svg; do
    if grep -q '<text' "${svg}"; then
        fail "${svg} renders text at runtime (use outlines instead)"
    else
        pass "${svg} is font-independent"
    fi
done
if grep -Fiq '#3C6EB4' build_files/branding/wrainrock-logo-icon.svg &&
   grep -Fiq '#3C6EB4' build_files/branding/wrainrock-gdm-logo.svg &&
   grep -Fiq '#3C6EB4' build_files/branding/wrainrock-wallpaper.svg; then
    pass "branding assets use the documented Wrainrock blue"
else
    fail "branding assets lost the Wrainrock blue outline"
fi
if python3 - <<'PY'
import struct

with open("build_files/branding/wrainrock-wallpaper.png", "rb") as handle:
    data = handle.read(24)
assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
width, height = struct.unpack(">II", data[16:24])
assert (width, height) == (3840, 2160), f"wallpaper is {width}x{height}"
PY
then
    pass "wallpaper is a 3840x2160 PNG"
else
    fail "wallpaper is not a 3840x2160 PNG"
fi

echo "build invariants"
for needle in 'base-os-release' 'delta.json' 'zz-wrainrock.gschema.override' \
              'wrainrock-wallpaper.png'; do
    if grep -Fq "${needle}" build_files/build.sh; then
        pass "build.sh handles ${needle}"
    else
        fail "build.sh does not handle ${needle}"
    fi
done
if grep -Eq 'dnf[[:space:]]+(install|remove|upgrade|groupinstall)|rpm[[:space:]]+-[iUe]' \
        build_files/build.sh; then
    fail "build.sh changes the RPM set; v0.2 must keep it identical to the base"
else
    pass "build.sh does not change the RPM set"
fi
if grep -Fq 'delta' tests/parity.sh; then
    pass "parity.sh enforces the delta manifest"
else
    fail "parity.sh does not check the delta manifest"
fi

echo "documentation"
for doc in README.md docs/architecture.md docs/install.md docs/roadmap.md \
           docs/rollback.md SECURITY.md CHANGELOG.md; do
    if [[ -s ${doc} ]]; then
        pass "${doc} exists"
    else
        fail "${doc} is missing or empty"
    fi
done
if grep -Fq "bootc switch" docs/install.md &&
   grep -Fq "ghcr.io/wraindrock/wrainrock-linux" docs/install.md; then
    pass "install doc documents the switch command"
else
    fail "docs/install.md does not document a bootc switch command"
fi
if grep -Fq 'delta.json' docs/architecture.md &&
   grep -Fq 'delta.json' docs/install.md; then
    pass "docs document the delta manifest"
else
    fail "docs do not describe /usr/share/wrainrock/delta.json"
fi
if grep -Fq 'wrainrock-wallpaper' docs/architecture.md; then
    pass "architecture doc describes the wallpaper override"
else
    fail "docs/architecture.md does not describe the wallpaper"
fi

echo "workflow"
if [[ -r .github/workflows/build.yml ]]; then
    pass "build workflow exists"
    for needle in 'packages: write' 'id-token: write' 'cosign sign' \
                  'bootc container lint' 'Anonymous pull check'; do
        if grep -Fq "${needle}" .github/workflows/build.yml; then
            pass "workflow contains ${needle}"
        else
            fail "workflow is missing ${needle}"
        fi
    done
else
    fail ".github/workflows/build.yml is missing"
fi

echo "secrets"
if grep -rInE 'gh[pousr]_[A-Za-z0-9]{20,}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY' \
        --exclude-dir=.git . >/dev/null 2>&1; then
    fail "a credential-looking string is committed"
else
    pass "no credential-looking strings"
fi

echo "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck --severity=warning --external-sources "${shell_files[@]}"; then
        pass "shellcheck"
    else
        fail "shellcheck (see diagnostics above)"
    fi
else
    pass "shellcheck not installed, skipped"
fi

echo "actionlint"
if command -v actionlint >/dev/null 2>&1; then
    if actionlint .github/workflows/*.yml; then
        pass "actionlint"
    else
        fail "actionlint (see diagnostics above)"
    fi
else
    pass "actionlint not installed, skipped"
fi

echo
if [[ ${failures} -ne 0 ]]; then
    printf '%s check(s) failed\n' "${failures}" >&2
    exit 1
fi
printf 'all checks passed\n'
