#!/bin/sh
# AppImage for distros without a native package (uses linuxdeploy + its Qt plugin; run on Ubuntu 22.04/24.04 or in CI).
# The AppImage cannot ship the polkit policy, so the app falls back to `pkexec /bin/sh -c <helper>` (generic password prompt).
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd); cd "$HERE"
. "$HERE/packaging/lib.sh"
need_cmd curl "Install curl (apt install curl / dnf install curl)."
[ -x "$HERE/target/release/pimp-my-grub" ] || sh "$HERE/packaging/build-binary.sh"
QMAKE=${QMAKE:-$(command -v qmake6 || command -v qmake || true)}
[ -n "$QMAKE" ] || die "qmake6 not found (needed by the linuxdeploy Qt plugin). Run: sh packaging/build-binary.sh"
export QMAKE QML_SOURCES_PATHS="$HERE/crates/app/qml" EXTRA_QT_MODULES="qml;quick;quickcontrols2"
export APPIMAGE_EXTRACT_AND_RUN=${APPIMAGE_EXTRACT_AND_RUN:-1}   # works without FUSE
mkdir -p build && cd build
progress_init 5
fetch() {  # fetch <file> <url...>
  f=$1; shift
  [ -f "$f" ] && return 0
  for u in "$@"; do curl -fsSL --retry 3 -o "$f" "$u" && chmod +x "$f" && return 0; done
  return 1
}
STEP_HINT="Download failed: check your internet connection, or place linuxdeploy-x86_64.AppImage and linuxdeploy-plugin-qt-x86_64.AppImage in build/ yourself."
step "Downloading linuxdeploy"            fetch linuxdeploy-x86_64.AppImage "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage"
step "Downloading linuxdeploy Qt plugin"  fetch linuxdeploy-plugin-qt-x86_64.AppImage "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage"
STEP_HINT=
step "Staging AppDir"                     sh -c 'rm -rf AppDir && PB_QUIET=1 sh ../packaging/install.sh "$PWD/AppDir" /usr'
STEP_HINT="linuxdeploy needs the Qt QML modules installed system-wide (run: sh packaging/build-binary.sh)."
step "Bundling Qt and creating the AppImage" ./linuxdeploy-x86_64.AppImage --appdir AppDir --plugin qt --output appimage \
  -d AppDir/usr/share/applications/dev.pimpmygrub.PimpMyGrub.desktop -i AppDir/usr/share/icons/hicolor/512x512/apps/pimp-my-grub.png
STEP_HINT=
step "Checking the result" sh -c 'ls ./*.AppImage'
say "Wrote build/$(ls *.AppImage | head -n1)"
