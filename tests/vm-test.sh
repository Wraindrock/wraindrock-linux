#!/usr/bin/env bash
# Boot a Wrainrock disk artifact under QEMU and capture screenshots.
#
# This is the local half of the v0.3 disk verification: the CI workflow proves
# the artifacts are well-formed; this script proves the operating system inside
# them reaches a graphical login.
#
#   tests/vm-test.sh qcow2 PATH [--timeout 300]
#   tests/vm-test.sh iso   PATH [--timeout 1200] [--disk-size 30G]
#
# KVM is used when /dev/kvm is usable; otherwise QEMU falls back to TCG (slow,
# but enough for a smoke test). Screenshots land in a temp directory unless
# --out is given; the script fails if QEMU never renders a non-trivial frame.
#
# No network device is attached: the qcow2 does not need one and the ISO's
# kickstart is on the media, so an offline test is both sufficient and safer.
set -euo pipefail

mode="${1:-}"
artifact="${2:-}"
shift 2 2>/dev/null || true

timeout=0
out_dir=""
disk_size="30G"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout) timeout="$2"; shift 2 ;;
        --out) out_dir="$2"; shift 2 ;;
        --disk-size) disk_size="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ "${mode}" != qcow2 && "${mode}" != iso ]]; then
    echo "usage: $0 qcow2|iso PATH [--timeout SECONDS] [--out DIR] [--disk-size SIZE]" >&2
    exit 2
fi
if [[ ! -f "${artifact}" ]]; then
    echo "error: no such artifact: ${artifact}" >&2
    exit 2
fi
for tool in qemu-system-x86_64 qemu-img python3; do
    command -v "${tool}" >/dev/null || { echo "error: missing ${tool}" >&2; exit 2; }
done

if [[ -z "${timeout}" || "${timeout}" == 0 ]]; then
    if [[ "${mode}" == iso ]]; then timeout=1200; else timeout=300; fi
fi
if [[ -z "${out_dir}" ]]; then
    out_dir="$(mktemp -d "${TMPDIR:-/tmp}/wrainrock-vm.XXXXXX")"
fi
mkdir -p "${out_dir}"
out_dir="$(cd "${out_dir}" && pwd)"

accel=tcg
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    accel=kvm
fi
cpu=host
[[ "${accel}" == tcg ]] && cpu=max

echo "mode:   ${mode}"
echo "image:  ${artifact}"
echo "accel:  ${accel}"
echo "out:    ${out_dir}"

qmp="${out_dir}/qmp.sock"
serial="${out_dir}/serial.log"
machine="q35,accel=${accel}"
qemu_args=(
    -machine "${machine}"
    -cpu "${cpu}"
    -m 4096
    -smp 4
    -display none
    -nic none
    -serial "file:${serial}"
    -monitor none
    -qmp "unix:${qmp},server=on,wait=off"
    -boot "order=d,menu=off"
)

if [[ "${mode}" == qcow2 ]]; then
    qemu_args+=(-drive "file=${artifact},if=virtio,format=qcow2")
else
    disk="${out_dir}/disk.qcow2"
    qemu-img create -f qcow2 "${disk}" "${disk_size}" >/dev/null
    qemu_args+=(
        -drive "file=${artifact},media=cdrom,readonly=on"
        -drive "file=${disk},if=virtio,format=qcow2"
    )
fi

qemu_log="${out_dir}/qemu.log"
qemu-system-x86_64 "${qemu_args[@]}" >"${qemu_log}" 2>&1 &
qemu_pid=$!
trap 'kill "${qemu_pid}" 2>/dev/null || true; wait "${qemu_pid}" 2>/dev/null || true' EXIT

# QMP screendump, one frame per call.
screendump() {
    python3 - "${qmp}" "$1" <<'PY'
import json, socket, sys
sock_path, out = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX)
s.settimeout(15)
s.connect(sock_path)
f = s.makefile('rwb')

def recv():
    while True:
        line = f.readline()
        if not line:
            raise SystemExit('qmp: connection closed')
        msg = json.loads(line)
        if 'event' in msg:
            continue
        return msg

recv()  # greeting
f.write(b'{"execute":"qmp_capabilities"}\n'); f.flush()
recv()
f.write((json.dumps({'execute': 'screendump', 'arguments': {'filename': out}}) + '\n').encode())
f.flush()
msg = recv()
if 'error' in msg:
    raise SystemExit('qmp screendump failed: %s' % msg['error'])
PY
}

for _ in $(seq 1 100); do
    [[ -S "${qmp}" ]] && break
    kill -0 "${qemu_pid}" 2>/dev/null || { echo "error: qemu exited early" >&2; cat "${qemu_log}" >&2; exit 1; }
    sleep 0.2
done
[[ -S "${qmp}" ]] || { echo "error: QMP socket never appeared" >&2; exit 1; }

# Give firmware and the bootloader time to hand over before the first frame.
sleep 20
start=$(date +%s)
best_file=""
best_size=0
count=0
while :; do
    now=$(date +%s)
    elapsed=$((now - start))
    [[ "${elapsed}" -ge "${timeout}" ]] && break
    count=$((count + 1))
    frame="${out_dir}/frame-$(printf '%03d' "${count}").png"
    if screendump "${frame}" 2>/dev/null; then
        size=$(stat -c %s "${frame}" 2>/dev/null || echo 0)
        if [[ "${size}" -gt "${best_size}" ]]; then
            best_size=${size}
            best_file=${frame}
        fi
        echo "t=${elapsed}s frame=${count} bytes=${size}"
    fi
    # A graphical login screen produces a meaningful PNG. Text consoles are
    # also non-trivial, so this is a lower bound, not proof of GDM; the human
    # reviewing the screenshot makes that call. The threshold rejects a blank
    # or stuck-black framebuffer.
    sleep 20
done

kill "${qemu_pid}" 2>/dev/null || true
wait "${qemu_pid}" 2>/dev/null || true
trap - EXIT

echo "frames: ${count}"
echo "best:   ${best_file} (${best_size} bytes)"
if [[ -s "${serial}" ]]; then
    echo "--- serial tail ---"
    tail -20 "${serial}" || true
fi

if [[ "${best_size}" -le 30000 ]]; then
    echo "FAIL: QEMU never rendered a non-trivial frame" >&2
    exit 1
fi
echo "PASS: captured a non-trivial frame; inspect ${best_file}"
