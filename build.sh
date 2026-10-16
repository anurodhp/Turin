#!/bin/bash
# Cross-builds Turin.app for the Pi (Darwin arm64) with the iokit repo's toolchain, exactly like naples' and milan's build.sh.
#
#   ./build.sh                 build; output lands in iokit's libc_build/gnustep/root
#   ./build.sh deploy          build, then copy Turin.app to the Pi (the Background pane needs a Milan that listens for the
#                              distributed MilanWallpaperChanged notification: deploy it from ../milan)
#
# IOKIT_DIR   the iokit checkout (default ../iokit next to this repo, else .. when this is iokit's third_party/turin)
# DEPLOY_HOST ssh target for "deploy" (default root@10.0.0.142)
# deploy stops Turin first: replacing a running app's files has taken the whole X session down on the Pi.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd -P)"
if [ -z "${IOKIT_DIR:-}" ]; then
    if [ -d "$HERE/../iokit/tools/userland_staging" ]; then IOKIT_DIR="$HERE/../iokit"; else IOKIT_DIR="$HERE/../.."; fi
fi
STAGING="$IOKIT_DIR/tools/userland_staging"
[ -x "$STAGING/build_turin.sh" ] || { echo "error: $STAGING/build_turin.sh not found; set IOKIT_DIR" >&2; exit 1; }

TURIN_SRC="$HERE" "$STAGING/build_turin.sh"

[ "${1:-}" = deploy ] || exit 0
HOST="${DEPLOY_HOST:-root@10.0.0.142}"
GSROOT="$(cd "$STAGING/libc_build/gnustep/root/usr/GNUstep/System" && pwd -P)"
tar -C "$GSROOT/Applications" -cf - Turin.app |
    ssh "$HOST" 'pkill -x Turin; sleep 1; rm -rf /Applications/Turin.app && tar -C /Applications -xf -'
echo "deployed Turin.app to $HOST"
