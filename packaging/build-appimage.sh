#!/bin/sh
# AppImage for distros without a native package (uses linuxdeploy + its Qt plugin; run in CI on Ubuntu 22.04/24.04).
# The AppImage cannot ship the polkit policy, so the app falls back to `pkexec /bin/sh -c <helper>` (generic password prompt).
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd); cd "$HERE"
[ -x "$HERE/target/release/pimp-my-grub" ] || { echo "error: target/release/pimp-my-grub not built yet. Run: sh packaging/build-release.sh   (or: QMAKE=$(command -v qmake6) cargo build --release -p pimp-my-grub)" >&2; exit 1; }
mkdir -p build && cd build
for f in linuxdeploy-x86_64.AppImage linuxdeploy-plugin-qt-x86_64.AppImage; do
  [ -f "$f" ] || { curl -fsSLO "https://github.com/linuxdeploy/${f%-x86_64.AppImage}/releases/download/continuous/$f" || curl -fsSLO "https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/$f"; chmod +x "$f"; }
done
rm -rf AppDir; sh ../packaging/install.sh "$PWD/AppDir" /usr
export QMAKE=${QMAKE:-$(command -v qmake6 || command -v qmake)} QML_SOURCES_PATHS="$HERE/crates/app/qml" EXTRA_QT_MODULES="qml;quick;quickcontrols2"
./linuxdeploy-x86_64.AppImage --appdir AppDir --plugin qt --output appimage \
  -d AppDir/usr/share/applications/dev.pimpmygrub.PimpMyGrub.desktop -i AppDir/usr/share/icons/hicolor/512x512/apps/pimp-my-grub.png
