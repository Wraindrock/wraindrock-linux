#!/usr/bin/env bash
# Capture the interactive installer's screens from a Wraindrock ISO.
#
# The disk workflow boots the ISO once for the unattended install. This script
# boots the same ISO a second time through the default, interactive entry and
# drives Anaconda with QMP mouse/key events:
#
#   boot menu -> installation summary -> destination dialog -> manual
#   partitioning
#
# Every state is matched against a fixture in tests/fixtures first, so a click
# that lands on the wrong widget fails instead of saving a misleading picture.
# Screenshots are written to OUT as interactive-{hub,destination,partitioning}.png.
#
#   tests/iso-interactive-shots.sh ISO OUT [--timeout 1800]
set -euo pipefail

iso="${1:-}"
out_dir="${2:-}"
shift 2 2>/dev/null || true
timeout=1800
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout) timeout="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[[ -f "${iso}" ]] || { echo "usage: $0 ISO OUT [--timeout SECONDS]" >&2; exit 2; }
[[ -n "${out_dir}" ]] || { echo "usage: $0 ISO OUT [--timeout SECONDS]" >&2; exit 2; }
for tool in qemu-system-x86_64 qemu-img python3; do
    command -v "${tool}" >/dev/null || { echo "error: missing ${tool}" >&2; exit 2; }
done
fixtures="${script_dir}/fixtures"
for fixture in boot-menu.png anaconda-hub.png anaconda-destination.png anaconda-partitioning.png; do
    [[ -f "${fixtures}/${fixture}" ]] || { echo "error: missing fixture ${fixtures}/${fixture}" >&2; exit 2; }
done

mkdir -p "${out_dir}"
out_dir="$(cd "${out_dir}" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/wraindrock-interactive.XXXXXX")"
qemu_pid=""
cleanup() {
    if [[ -n "${qemu_pid}" ]]; then
        kill "${qemu_pid}" 2>/dev/null || true
        wait "${qemu_pid}" 2>/dev/null || true
    fi
    rm -rf -- "${work}"
}
trap cleanup EXIT

accel=tcg
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    probe_qmp="${work}/kvm-probe.sock"
    qemu-system-x86_64 -accel kvm -M none -display none -nodefaults -S \
        -qmp "unix:${probe_qmp},server=on,wait=off" >/dev/null 2>&1 &
    probe_pid=$!
    sleep 1
    if kill -0 "${probe_pid}" 2>/dev/null; then
        accel=kvm
        kill "${probe_pid}" 2>/dev/null || true
    fi
    wait "${probe_pid}" 2>/dev/null || true
fi
echo "accelerator: ${accel}"

qemu-img create -f qcow2 "${work}/disk.qcow2" 30G >/dev/null
qmp="${work}/qmp.sock"
qemu-system-x86_64 -machine q35,accel="${accel}" -cpu max -m 4096 -smp 2 \
    -display none -nic none -serial "file:${work}/serial.log" -monitor none \
    -qmp "unix:${qmp},server=on,wait=off" -boot "once=d,menu=off" \
    -drive "file=${work}/disk.qcow2,if=virtio,format=qcow2" \
    -device qemu-xhci -device usb-tablet -cdrom "${iso}" \
    >"${work}/qemu.log" 2>&1 &
qemu_pid=$!

python3 - "${qmp}" "${fixtures}" "${out_dir}" "${work}" "${timeout}" "${script_dir}/png-stats.py" <<'PY'
import json
import os
import re
import socket
import subprocess
import sys
import time

qmp_path, fixtures, out_dir, work, timeout, stats = sys.argv[1:]
timeout = int(timeout)


def connect():
    deadline = time.time() + 60
    while time.time() < deadline:
        try:
            sock = socket.socket(socket.AF_UNIX)
            sock.settimeout(30)
            sock.connect(qmp_path)
            return sock.makefile("rwb")
        except OSError:
            time.sleep(1)
    raise SystemExit("error: QMP socket never appeared")


def command(stream, **payload):
    stream.write((json.dumps(payload) + "\n").encode())
    stream.flush()
    while True:
        line = stream.readline()
        if not line:
            raise SystemExit("error: QMP connection closed")
        message = json.loads(line)
        if "event" not in message:
            return message


stream = connect()
command(stream, execute="qmp_capabilities")
frame = os.path.join(work, "frame.png")


def screendump(path):
    command(stream, execute="screendump", arguments={"filename": path, "format": "png"})
    # QEMU writes the PNG asynchronously; wait for the file to stop growing.
    previous = -1
    for _ in range(40):
        time.sleep(0.25)
        try:
            size = os.path.getsize(path)
        except OSError:
            continue
        if size == previous and size > 0:
            return
        previous = size
    raise SystemExit("error: screendump never finished")


def difference(path, reference):
    if not os.path.exists(path):
        return 9999.0
    result = subprocess.run(
        [sys.executable, stats, path, reference], capture_output=True, text=True
    )
    if result.returncode != 0:
        return 9999.0
    match = re.search(r"mean abs diff ([0-9.]+)", result.stdout)
    return float(match.group(1)) if match else 9999.0


def wait_for(reference, label, seconds, maximum=12.0):
    deadline = time.time() + seconds
    while time.time() < deadline:
        screendump(frame)
        score = difference(frame, reference)
        if score <= maximum:
            print("found %s (diff %.2f)" % (label, score), flush=True)
            return frame
        time.sleep(3)
    raise SystemExit("error: %s did not appear within %ds" % (label, seconds))


def key(name):
    command(
        stream,
        execute="send-key",
        arguments={"keys": [{"type": "qcode", "data": name}]},
    )


def click(x, y):
    events = [
        {"type": "abs", "data": {"axis": "x", "value": x * 32767 // 1280}},
        {"type": "abs", "data": {"axis": "y", "value": y * 32767 // 800}},
    ]
    command(stream, execute="input-send-event", arguments={"events": events})
    time.sleep(0.3)
    command(
        stream,
        execute="input-send-event",
        arguments={"events": [{"type": "btn", "data": {"down": True, "button": "left"}}]},
    )
    time.sleep(0.15)
    command(
        stream,
        execute="input-send-event",
        arguments={"events": [{"type": "btn", "data": {"down": False, "button": "left"}}]},
    )
    time.sleep(0.6)


def save(source, name):
    target = os.path.join(out_dir, name)
    with open(source, "rb") as src, open(target, "wb") as dst:
        dst.write(src.read())
    print("saved %s" % target, flush=True)


menu = wait_for(os.path.join(fixtures, "boot-menu.png"), "boot menu", 300)
key("ret")

hub = wait_for(os.path.join(fixtures, "anaconda-hub.png"), "installer summary", timeout)
save(hub, "interactive-hub.png")

click(600, 369)  # Installation Destination
destination = wait_for(
    os.path.join(fixtures, "anaconda-destination.png"), "destination dialog", 300
)
save(destination, "interactive-destination.png")

click(640, 240)  # select the 30 GiB disk
click(246, 483)  # Custom partitioning
click(46, 48)  # Done
partitioning = wait_for(
    os.path.join(fixtures, "anaconda-partitioning.png"), "manual partitioning", 600
)
save(partitioning, "interactive-partitioning.png")
PY

kill "${qemu_pid}" 2>/dev/null || true
wait "${qemu_pid}" 2>/dev/null || true
qemu_pid=""

for shot in interactive-hub.png interactive-destination.png interactive-partitioning.png; do
    [[ -s "${out_dir}/${shot}" ]] || { echo "error: ${shot} was not captured" >&2; exit 1; }
done
echo "interactive installer screens captured in ${out_dir}"
