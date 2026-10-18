#!/usr/bin/env bash
# Boot a Wraindrock disk artifact under QEMU and capture screenshots.
#
# This is the local half of the v0.3 disk verification: the CI workflow proves
# the artifacts are well-formed; this script proves the operating system inside
# them reaches a graphical login.
#
#   tests/vm-test.sh qcow2 PATH [--timeout 300]
#   tests/vm-test.sh iso   PATH [--timeout 1800] [--disk-size 30G]
#
# For an ISO the installer boots once, then the firmware boots the installed
# disk. The ISO menu defaults to the interactive installer, so the test presses
# Down+Enter to pick the explicit "erase first disk (unattended)" entry. The
# ISO mode does not trust serial output (Anaconda installs a system whose kernel
# may keep console=tty0), so it instead requires the installed system's
# graphical screen: the GNOME welcome screen (compared against
# tests/fixtures/gnome-initial-setup.png) or the Wraindrock GDM wallpaper.
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
expect_hostname="wraindrock"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
screen_ref="${script_dir}/fixtures/gnome-initial-setup.png"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout) timeout="$2"; shift 2 ;;
        --out) out_dir="$2"; shift 2 ;;
        --disk-size) disk_size="$2"; shift 2 ;;
        --expect-hostname) expect_hostname="$2"; shift 2 ;;
        --screen-ref) screen_ref="$2"; shift 2 ;;
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
    if [[ "${mode}" == iso ]]; then timeout=1800; else timeout=300; fi
fi
if [[ -z "${out_dir}" ]]; then
    out_dir="$(mktemp -d "${TMPDIR:-/tmp}/wraindrock-vm.XXXXXX")"
fi
mkdir -p "${out_dir}"
out_dir="$(cd "${out_dir}" && pwd)"

# The device node can be mode 0666 while the container's device cgroup still
# denies the O_RDWR open KVM needs, so probe by actually starting QEMU. A stale
# QMP socket from a failed KVM attempt would otherwise send the poll loop to
# sleep until the timeout.
accel=tcg
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    probe_qmp="${out_dir}/kvm-probe.sock"
    qemu-system-x86_64 -accel kvm -M none -display none -nodefaults -S \
        -qmp "unix:${probe_qmp},server=on,wait=off" >/dev/null 2>&1 &
    probe_pid=$!
    sleep 1
    if kill -0 "${probe_pid}" 2>/dev/null; then
        accel=kvm
    else
        echo "KVM is present but unusable (device cgroup?); using TCG"
    fi
    kill "${probe_pid}" 2>/dev/null || true
    wait "${probe_pid}" 2>/dev/null || true
    rm -f "${probe_qmp}"
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
)

workdir=""
if [[ "${mode}" == qcow2 ]]; then
    # A booted disk is written to (machine-id, logs, SSH host keys), so test a
    # copy: the artifact we publish must stay identical to its checksum.
    workdir=$(mktemp -d "${out_dir}/qcow2-boot.XXXXXX")
    boot_disk="${workdir}/disk.qcow2"
    cp --sparse=always -- "${artifact}" "${boot_disk}"
    qemu_args+=(-boot "order=c,menu=off" -drive "file=${boot_disk},if=virtio,format=qcow2")
else
    disk="${out_dir}/disk.qcow2"
    qemu-img create -f qcow2 "${disk}" "${disk_size}" >/dev/null
    # Boot the installer once; after its reboot the firmware falls back to the
    # disk, so the install is not repeated forever.
    qemu_args+=(
        -boot "once=d,menu=off"
        -drive "file=${artifact},media=cdrom,readonly=on"
        -drive "file=${disk},if=virtio,format=qcow2"
    )
fi

qemu_log="${out_dir}/qemu.log"
qemu-system-x86_64 "${qemu_args[@]}" >"${qemu_log}" 2>&1 &
qemu_pid=$!
trap 'kill "${qemu_pid}" 2>/dev/null || true; wait "${qemu_pid}" 2>/dev/null || true; [[ -z "${workdir}" ]] || rm -rf -- "${workdir}"' EXIT

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
f.write((json.dumps({'execute': 'screendump', 'arguments': {'filename': out, 'format': 'png'}}) + '\n').encode())
f.flush()
msg = recv()
if 'error' in msg:
    raise SystemExit('qmp screendump failed: %s' % msg['error'])
PY
}

# QMP key press, used to pick the unattended entry in the ISO boot menu.
send_key() {
    python3 - "${qmp}" "$@" <<'PY'
import json, socket, sys
sock_path, *keys = sys.argv[1:]
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
payload = {
    'execute': 'send-key',
    'arguments': {'keys': [{'type': 'qcode', 'data': key} for key in keys]},
}
f.write((json.dumps(payload) + '\n').encode()); f.flush()
msg = recv()
if 'error' in msg:
    raise SystemExit('qmp send-key failed: %s' % msg['error'])
PY
}

for _ in $(seq 1 100); do
    [[ -S "${qmp}" ]] && break
    kill -0 "${qemu_pid}" 2>/dev/null || { echo "error: qemu exited early" >&2; cat "${qemu_log}" >&2; exit 1; }
    sleep 0.2
done
[[ -S "${qmp}" ]] || { echo "error: QMP socket never appeared" >&2; exit 1; }
kill -0 "${qemu_pid}" 2>/dev/null || {
    echo "error: QEMU exited during startup" >&2
    cat "${qemu_log}" >&2
    exit 1
}

# Give firmware and the bootloader time to hand over before the first frame.
if [[ "${mode}" == iso ]]; then
    # The default menu entry is the interactive installer; Down+Enter picks the
    # unattended entry below it. The GRUB menu timeout is 60 s, so both attempts
    # land inside it; a key press that arrives too early is simply ignored.
    sleep 15
    # Capture the menu for evidence/README before selecting the second entry.
    screendump "${out_dir}/boot-menu.png" 2>/dev/null || true
    send_key down ret || true
    sleep 15
    send_key down ret || true
    sleep 10
fi
sleep 20
start=$(date +%s)
best_file=""
best_size=0
count=0
install_finished=0
screen_hits=0
screen_ok=0
while :; do
    now=$(date +%s)
    elapsed=$((now - start))
    [[ "${elapsed}" -ge "${timeout}" ]] && break
    count=$((count + 1))
    frame="${out_dir}/frame-$(printf '%03d' "${count}").png"
    rm -f "${frame}"
    if screendump "${frame}" 2>/dev/null; then
        # QEMU's PNG writer is asynchronous; wait for the file to appear and
        # stop growing before sizing it.
        size=0
        for _ in $(seq 1 50); do
            now_size=$(stat -c %s "${frame}" 2>/dev/null || echo 0)
            if [[ "${now_size}" -gt 0 && "${now_size}" == "${size}" ]]; then
                break
            fi
            size=${now_size}
            sleep 0.1
        done
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
    if [[ "${install_finished}" == 0 ]] && grep -Fq 'Install finished' "${serial}" 2>/dev/null; then
        install_finished=${now}
        echo "installer finished at t=${elapsed}s; waiting for the installed system"
    fi
    if [[ "${mode}" == iso && -s "${frame}" ]]; then
        # The installed system may show the GNOME welcome screen (white) or the
        # GDM login screen (the Wraindrock wallpaper). Both prove that the
        # graphical stack came up; an Anaconda screen matches neither. The
        # serial marker is only a hint: some kickstarts cannot write to ttyS0
        # from the installed system, and waiting for it would hang until the
        # timeout even though the desktop is already up.
        blue=$(python3 "${script_dir}/png-stats.py" "${frame}" | sed 's/.*blue=//')
        diff=$(python3 "${script_dir}/png-stats.py" "${frame}" "${screen_ref}" | awk '{print $NF}')
        if python3 -c "import sys; sys.exit(0 if float('${blue}') >= 0.6 or float('${diff}') <= 25 else 1)" 2>/dev/null; then
            screen_hits=$((screen_hits + 1))
            echo "graphical screen after install (blue=${blue} diff=${diff}, hit ${screen_hits}/2)"
            if [[ "${screen_hits}" -ge 2 ]]; then
                screen_ok=1
                echo "detected the installed system's graphical screen; stopping"
                break
            fi
        else
            screen_hits=0
        fi
    fi
    sleep 20
    # A serial getty carries the kernel hostname even when nobody logs in; on
    # systems whose kernel keeps console=tty0 that is the end-to-end hostname
    # check. Break early instead of burning the whole timeout.
    if [[ "${mode}" == qcow2 ]] &&
       grep -Fq 'gdm.service' "${serial}" 2>/dev/null &&
       grep -Fq "${expect_hostname} login:" "${serial}" 2>/dev/null; then
        echo "detected a graphical login on ${expect_hostname}; stopping"
        break
    fi
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

if [[ "${mode}" == iso ]]; then
    if [[ "${screen_ok}" != 1 ]]; then
        echo "FAIL: the installed system never reached a graphical welcome/login screen" >&2
        exit 1
    fi
    echo "PASS: the ISO installer finished and the installed system reached its graphical screen"
    exit 0
fi

# A getty prompt carries the kernel hostname even when no user logs in. This is
# the end-to-end check that DEFAULT_HOSTNAME survived into the installed system;
# the screenshot alone cannot show it.
if [[ -n "${expect_hostname}" ]]; then
    if ! grep -Fq 'gdm.service' "${serial}" 2>/dev/null; then
        echo "FAIL: GDM never started (the installed system did not reach a login screen)" >&2
        exit 1
    fi
    if grep -Fq "${expect_hostname} login:" "${serial}" 2>/dev/null; then
        echo "PASS: serial getty reports hostname ${expect_hostname}"
    else
        echo "FAIL: serial getty did not report '${expect_hostname} login:'" >&2
        exit 1
    fi
fi
