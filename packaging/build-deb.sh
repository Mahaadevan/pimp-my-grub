#!/bin/sh
# Builds style-my-grub_<ver>_<arch>.deb for Debian, Ubuntu, Mint and relatives. The package is SELF-CONTAINED: it installs the
# app together with its own Qt 6 into /usr/lib/style-my-grub (see bundle.sh), so it does not depend on the distribution's Qt
# version, only on a glibc at least as new as the machine that built it. For the widest reach build on an old system.
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd); cd "$HERE"
. "$HERE/packaging/lib.sh"
need_cmd dpkg-deb "This step runs on Debian/Ubuntu/Mint."
VER=$(sed -n 's/^version = "\(.*\)"/\1/p' "$HERE/Cargo.toml" | head -n1)
ARCH=$(dpkg --print-architecture)
APPDIR="$HERE/build/AppDir-deb"
mkdir -p build
PB_NOREPORT=1 sh "$HERE/packaging/bundle.sh" "$APPDIR"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
chmod 755 "$T"
LIB="$T/usr/lib/style-my-grub"
progress_init 3
layout() {
  install -d "$LIB" "$T/usr/bin" "$T/usr/libexec" "$T/usr/share"
  cp -a "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/plugins" "$APPDIR/usr/qml" "$LIB/"
  cp -a "$APPDIR/usr/libexec/style-my-grub" "$T/usr/libexec/"
  for d in applications icons metainfo polkit-1; do cp -a "$APPDIR/usr/share/$d" "$T/usr/share/"; done
  ln -s ../lib/style-my-grub/bin/style-my-grub "$T/usr/bin/style-my-grub"
  find "$LIB" -type f \( -name '*.so*' -o -perm -u+x \) -exec chmod u+w {} + 2>/dev/null || true
}
step "Laying out the package" layout
# --- dependencies: only what is NOT bundled. Taken from the libraries the bundle really loads (so nothing is guessed), minus
# libc, whose version is the highest GLIBC symbol the bundle uses. Packages renamed to "...t64" on newer distros also accept the old name.
write_control() {
  install -d "$T/DEBIAN"
  SIZE=$(du -sk "$T/usr" | cut -f1)
  GL=$(cat "$APPDIR/glibc-required.txt" 2>/dev/null); case "$GL" in [0-9]*) ;; *) GL=2.31 ;; esac
  files="$LIB/bin/style-my-grub-bin $(find "$LIB/plugins" "$LIB/qml" -name '*.so')"
  # shellcheck disable=SC2086
  libs=$(LD_LIBRARY_PATH="$LIB/lib" ldd $files 2>/dev/null | awk '/=> \// {print $3}' | sort -u | grep -v "^$LIB" || true)
  pkgs=
  for l in $libs; do
    p=$(dpkg -S "$(readlink -f "$l")" 2>/dev/null | head -n1 | cut -d: -f1)
    [ -n "$p" ] && pkgs="$pkgs $p"
  done
  deps="libc6 (>= $GL)"
  for p in $(printf '%s\n' $pkgs | sort -u); do
    case "$p" in
      libc6|libc6-dev) ;;
      *t64) deps="$deps, $p | ${p%t64}" ;;
      *)    deps="$deps, $p" ;;
    esac
  done
  # loaded at run time, not linked: the GL stack and a PolicyKit agent for the password prompt
  deps="$deps, libgl1, libegl1, polkitd | policykit-1"
  cat > "$T/DEBIAN/control" <<C
Package: style-my-grub
Version: $VER
Section: utils
Priority: optional
Architecture: $ARCH
Installed-Size: $SIZE
Depends: $deps
Recommends: grub-common, zenity | kdialog
Maintainer: Style My GRUB <dev@stylemygrub.local>
Description: Native Qt 6 GRUB theme builder
 Visual editor, theme store and a reversible installer that shows every
 change and asks for confirmation before touching /boot or /etc.
 This package carries its own Qt 6, so it does not depend on the Qt version
 of your distribution.
C
  echo "control Depends: $deps"
  # The pre-rename install left its own desktop entry, icons, AppStream data and polkit action behind. No package this one
  # replaces owns them, so nothing removes them and the application menu keeps a second, stale "Pimp My GRUB" entry with
  # its own icon. Retire them on install and on upgrade (dpkg runs this in both cases).
  cat > "$T/DEBIAN/postinst" <<'P'
#!/bin/sh
# DPKG_ROOT is set by dpkg when it installs into another root; it is empty for a normal install.
set -e
R="${DPKG_ROOT:-}"
rm -f "$R/usr/share/applications/dev.pimpmygrub.PimpMyGrub.desktop" \
      "$R/usr/share/metainfo/dev.pimpmygrub.PimpMyGrub.metainfo.xml" \
      "$R/usr/share/polkit-1/actions/dev.pimpmygrub.policy"
rm -f "$R"/usr/share/icons/hicolor/*/apps/pimp-my-grub.png
exit 0
P
  chmod 755 "$T/DEBIAN/postinst"
}
step "Writing control file" write_control
step "Building the .deb"    dpkg-deb -Zxz --root-owner-group --build "$T" "$HERE/style-my-grub_${VER}_${ARCH}.deb"
say "This .deb needs glibc >= $(cat "$APPDIR/glibc-required.txt" 2>/dev/null) (the machine it was built on) and brings its own Qt 6."
report_file "$HERE/style-my-grub_${VER}_${ARCH}.deb"
