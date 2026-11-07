#!/bin/sh
# Takes docs/screenshots/editor.png from the real app under a virtual X server. Needs: xvfb, imagemagick, a release build.
# The install-confirm shot needs a polkit/GRUB system and is still taken by hand.
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
BIN=${BIN:-$HERE/target/release/pimp-my-grub}
[ -x "$BIN" ] || { echo "build first: sh packaging/build-release.sh deb" >&2; exit 1; }
mkdir -p "$HERE/docs/screenshots"
xvfb-run -a -s "-screen 0 1280x800x24" sh -c '
  "$0" "$1" & PID=$!; sleep 6
  import -window root "$2"; kill $PID 2>/dev/null || true
' "$BIN" "$HERE/examples/midnight" "$HERE/docs/screenshots/editor.png"
echo "wrote docs/screenshots/editor.png"
