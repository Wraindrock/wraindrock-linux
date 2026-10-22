#!/usr/bin/env bash
# Run a command with a disk-backed scratch directory that is removed on exit.
#
# /tmp inside the development container is tmpfs: every byte written there is
# RAM, and large downloads or image layers push the host into swap. Use this
# wrapper (or export TMPDIR yourself) for anything bigger than a few megabytes:
#
#   tools/scratch.sh bash -c 'curl -o "$TMPDIR/big.iso" ...; work "$TMPDIR/big.iso"'
#
# WR_SCRATCH_ROOT overrides where scratch directories are created (default
# ./.scratch, which is gitignored). The directory is removed even when the
# command fails; on SIGKILL it may survive, but it lives on disk rather than
# consuming RAM.
set -euo pipefail

root="${WR_SCRATCH_ROOT:-${PWD}/.scratch}"
mkdir -p "${root}"
scratch="$(mktemp -d "${root}/wraindrock-scratch.XXXXXX")"
# shellcheck disable=SC2317  # invoked by trap
cleanup() { rm -rf -- "${scratch}"; rmdir -- "${root}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

if [[ $# -eq 0 ]]; then
    echo "usage: scratch.sh <command> [args...]" >&2
    exit 2
fi

export TMPDIR="${scratch}"
status=0
"$@" || status=$?
exit "${status}"
