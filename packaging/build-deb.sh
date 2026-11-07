#!/bin/sh
# Builds pimp-my-grub_<ver>_<arch>.deb (Debian 13+, Ubuntu 24.04+, Mint 22+). Builds the binary first if it is missing.
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/packaging/lib.sh"
need_cmd dpkg-deb "This step runs on Debian/Ubuntu/Mint."
[ -x "$HERE/target/release/pimp-my-grub" ] || sh "$HERE/packaging/build-binary.sh"
VER=$(sed -n 's/^version = "\(.*\)"/\1/p' "$HERE/Cargo.toml" | head -n1)
ARCH=$(dpkg --print-architecture)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
chmod 755 "$T"
progress_init 4
step "Staging files"        env PB_QUIET=1 sh "$HERE/packaging/install.sh" "$T" /usr
# --- dependency versions: taken from the Qt/glibc this binary was built against, so apt refuses to install it on a system
# that is too old instead of letting it crash at startup.
up3() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null | sed 's/^[0-9]*://; s/^\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/'; }
QV=$(up3 libqt6core6t64); [ -n "$QV" ] || QV=$(up3 libqt6core6)
[ -n "$QV" ] || QV=$("${QMAKE:-qmake6}" -query QT_VERSION 2>/dev/null || true)
GV=$(dpkg-query -W -f='${Version}' libc6 2>/dev/null | sed 's/^[0-9]*://; s/^\([0-9]*\.[0-9]*\).*/\1/')
# Qt private API (used by ahead-of-time compiled QML) is only valid inside one minor release: pin to it.
PRIVATE=0; command -v readelf >/dev/null 2>&1 && readelf -V "$HERE/target/release/pimp-my-grub" 2>/dev/null | grep -q Qt_6_PRIVATE_API && PRIVATE=1
if [ -n "$QV" ]; then
  MAJ=${QV%%.*}; MIN=${QV#*.}; MIN=${MIN%%.*}; NEXT="$MAJ.$((MIN + 1))"
fi
dep() {  # dep <package>  ->  "pkg (>= QV)" or, for private-API builds, "pkg (>= QV), pkg (<< NEXT)"
  if [ -z "$QV" ]; then printf '%s' "$1"
  elif [ "$PRIVATE" = 1 ]; then printf '%s (>= %s), %s (<< %s)' "$1" "$QV" "$1" "$NEXT"
  else printf '%s (>= %s)' "$1" "$QV"; fi
}
write_control() {
  install -d "$T/DEBIAN"
  SIZE=$(du -sk "$T/usr" | cut -f1)
  LIBS=""
  for n in libqt6quick6 libqt6gui6 libqt6qml6 libqt6core6 qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-dialogs qml6-module-qtquick-templates qml6-module-qtquick-window qml6-module-qtqml-workerscript; do
    LIBS="$LIBS, $(dep "$n")"
  done
  LIBC=libc6; [ -n "$GV" ] && LIBC="libc6 (>= $GV)"
  cat > "$T/DEBIAN/control" <<C
Package: pimp-my-grub
Version: $VER
Section: utils
Priority: optional
Architecture: $ARCH
Installed-Size: $SIZE
Depends: $LIBC$LIBS, polkitd | policykit-1
Recommends: grub-common, qml6-module-qt-labs-platform
Suggests: qqc2-desktop-style
Maintainer: Pimp my grub <dev@pimpmygrub.local>
Description: Native Qt 6 GRUB theme builder
 Visual editor, theme store and a reversible installer that shows every
 change and asks for confirmation before touching /boot or /etc.
C
  echo "control Depends: $(sed -n 's/^Depends: //p' "$T/DEBIAN/control")"
}
step "Writing control file" write_control
step "Building the .deb"    dpkg-deb --root-owner-group --build "$T" "$HERE/pimp-my-grub_${VER}_${ARCH}.deb"
step "Checking the package" dpkg-deb --info "$HERE/pimp-my-grub_${VER}_${ARCH}.deb"
if [ "$PRIVATE" = 1 ]; then
  say "Note: this binary uses Qt private API, so the .deb is pinned to Qt ${QV%.*}.x and glibc >= ${GV:-?}."
  say "      It will refuse to install on other Qt minor versions. For other systems ship the AppImage."
else
  say "The .deb requires Qt >= ${QV:-?} and glibc >= ${GV:-?} (checked by apt at install time)."
fi
report_file "$HERE/pimp-my-grub_${VER}_${ARCH}.deb"
