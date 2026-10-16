#!/bin/bash
# QEMU test of Turin: copies tests/turin_verify_guest.sh onto an iokit test image, boots it with iokit's
# tools/boot_test.py, runs it as root (see that script for the steps), then copies the screenshots and Turin's log back
# out as $OUT/turin_*.png / turin.log. The image needs Turin.app and the X/GNUstep stack injected first
# (iokit: tools/init_binary/inject_into_sd_image.sh <image>), plus x11_probe and xtest_type.
# Usage: tests/turin_qemu_test.sh <image> [out dir]      IOKIT_DIR defaults to ../iokit
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd -P)"
IOKIT_DIR="${IOKIT_DIR:-$HERE/../iokit}"
IMG="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
OUT="${2:-$HERE/tests/out}"
[ -f "$IMG" ] || { echo "error: $IMG not found" >&2; exit 1; }
mkdir -p "$OUT"

# with_root <command...>: attach $IMG, mount its HFS+ root (slice 2) as $MNT, run the command, detach (gsdm_qemu_test.sh's)
with_root() {
    local disk slice
    disk=$(hdiutil attach -nomount "$IMG" | awk 'NR==1{print $1}')
    [ -n "$disk" ] || { echo "error: hdiutil attach failed" >&2; exit 1; }
    slice="${disk}s2"
    if ! diskutil mount "$slice" >/dev/null; then
        fsck_hfs -fy "/dev/r${slice#/dev/}" >/dev/null
        diskutil mount "$slice" >/dev/null
    fi
    MNT=$(diskutil info "$slice" | awk -F': +' '/Mount Point/{print $2}')
    "$@" || { hdiutil detach "$disk" >/dev/null; return 1; }
    diskutil unmount "$slice" >/dev/null 2>&1 || true
    hdiutil detach "$disk" >/dev/null
}
put_script() {
    mkdir -p "$MNT/var/root"
    cp "$HERE/tests/turin_verify_guest.sh" "$MNT/var/root/turin_verify.sh"
    rm -rf "$MNT/var/root/turintest"
}
get_results() {
    local f n
    for f in "$MNT"/var/root/turintest/*.xwd; do
        [ -f "$f" ] || continue
        n=$(basename "$f" .xwd)
        python3 "$IOKIT_DIR/tools/xwd_to_png.py" "$f" "$OUT/turin_$n.png" | head -1
    done
    cp "$MNT/var/root/turintest/turin.log" "$OUT/turin.log" 2>/dev/null || true
}

with_root put_script
rc=0
(cd "$IOKIT_DIR" && SD_IMAGE="$IMG" tools/boot_test.py --timeout 2700 --login --log "$OUT/turin_boot.log" \
    --expect 'TURIN_TEST DONE' --expect-fail 'panic' \
    --cmd 'sh /var/root/turin_verify.sh 2>&1') || rc=$?
with_root get_results
ls "$OUT"/turin_*.png 2>/dev/null
exit $rc
