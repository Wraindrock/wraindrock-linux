#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Smoke test: the built image has to boot. A bootc image that builds but does
# not reach a running systemd is not a distribution - the build succeeding
# proves nothing about PID 1.
#
#   tests/smoke.sh localhost/wraindrock-linux:44
#
# Needs an engine where rootless systemd containers work (stock cgroup v2 host).
# ---------------------------------------------------------------------------
set -euo pipefail

IMAGE="${1:-}"
[[ -n ${IMAGE} ]] || { echo "usage: tests/smoke.sh <image>" >&2; exit 2; }

ENGINE="${WR_ENGINE:-podman}"
command -v "${ENGINE}" >/dev/null 2>&1 || {
    echo "${ENGINE} is required" >&2
    exit 1
}

NAME="${WR_SMOKE_NAME:-wraindrock-smoke}"
TIMEOUT="${WR_SMOKE_TIMEOUT:-180}"

cleanup() { "${ENGINE}" rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

echo "smoke test: ${IMAGE}"
# Booting a real systemd inside a container needs the full capability set of
# the sandbox user namespace: journald, dbus and logind set up mount
# namespaces, and without CAP_SYS_ADMIN they exit with EPERM. This is a
# property of the harness, not of the image; the disk VM tests boot the same
# image on real (virtual) hardware.
"${ENGINE}" run --systemd=always --privileged --name "${NAME}" -d "${IMAGE}" >/dev/null

status="unknown"
deadline=$((SECONDS + TIMEOUT))
while (( SECONDS < deadline )); do
    status="$("${ENGINE}" exec "${NAME}" systemctl is-system-running 2>/dev/null || true)"
    case "${status}" in
        running|degraded) break ;;
    esac
    sleep 3
done

if [[ ${status} != running && ${status} != degraded ]]; then
    echo "  fail systemd did not come up within ${TIMEOUT}s (state: ${status:-empty})" >&2
    "${ENGINE}" logs "${NAME}" 2>&1 | tail -40 >&2 || true
    exit 1
fi
printf '  ok   systemd reached state: %s\n' "${status}"

# A desktop image inside a container will usually have a few units that cannot
# start (no real seat, no bootloader). Report them; do not fail the build for
# them. The assertion that matters is that PID 1 is alive and responding.
failed="$("${ENGINE}" exec "${NAME}" systemctl list-units --failed --no-legend --plain 2>/dev/null || true)"
if [[ -n ${failed} ]]; then
    printf '  note failed units in container (expected for a desktop image):\n'
    printf '%s\n' "${failed}" | sed 's/^/       /'
fi

if "${ENGINE}" exec "${NAME}" systemctl is-active --quiet systemd-journald; then
    printf '  ok   systemd-journald is active\n'
else
    echo "  fail systemd-journald is not active" >&2
    {
        echo "  -- journald diagnostics --"
        "${ENGINE}" exec "${NAME}" systemctl status systemd-journald --no-pager -l 2>&1 | tail -20 || true
        echo "  -- dbus-broker diagnostics --"
        "${ENGINE}" exec "${NAME}" systemctl status dbus-broker --no-pager -l 2>&1 | tail -20 || true
        echo "  -- filesystem and account state --"
        "${ENGINE}" exec "${NAME}" ls -ld /etc/machine-id /run/log /run/log/journal /var/log/journal 2>&1 || true
        "${ENGINE}" exec "${NAME}" sh -c 'grep -v "^#" /etc/systemd/journald.conf 2>/dev/null; id systemd-journal 2>&1; id dbus 2>&1' || true
        echo "  -- journald stderr (transient drop-in) --"
        "${ENGINE}" exec "${NAME}" sh -c '
            mkdir -p /etc/systemd/system/systemd-journald.service.d
            printf "[Service]\nStandardOutput=file:/tmp/journald.out\nStandardError=file:/tmp/journald.err\n" > /etc/systemd/system/systemd-journald.service.d/zz-debug.conf
            systemctl daemon-reload
            systemctl restart systemd-journald 2>/dev/null || true
            sleep 2
            echo "--- status after restart ---"
            systemctl is-active systemd-journald 2>&1 || true
            echo "--- stderr ---"
            cat /tmp/journald.err 2>&1 || true
            echo "--- stdout ---"
            cat /tmp/journald.out 2>&1 || true
            echo "--- pid1 capabilities ---"
            grep -E "^(CapEff|NoNewPrivs|Seccomp):" /proc/1/status 2>&1 || true
        ' 2>&1 || true
    } >&2
    exit 1
fi

if "${ENGINE}" exec "${NAME}" test -f /usr/lib/os-release; then
    printf '  ok   /usr/lib/os-release is present in the booted system\n'
else
    echo "  fail /usr/lib/os-release is missing in the booted system" >&2
    exit 1
fi

echo "smoke test passed"
