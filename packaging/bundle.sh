#!/bin/sh
# Builds a self-contained, relocatable tree: the app plus the Qt 6 libraries, plugins and QML modules it needs and the C++
# runtime. The AppImage and the .deb are both made from it, so they run whatever Qt / libstdc++ the target system has.
# usage: sh packaging/bundle.sh APPDIR        (APPDIR is recreated; everything lands under APPDIR/usr)
#
# Layout:  usr/bin/{style-my-grub (launcher), style-my-grub-bin, qt.conf}   usr/lib   usr/plugins   usr/qml
#          usr/libexec/style-my-grub/style-my-grub-helper   usr/share/...
# Portability is decided by the machine that BUILDS this: the tree needs at least the glibc of the build machine, so build on
# the oldest system you want to support (CI does this on Ubuntu 20.04 with Qt from aqtinstall).
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd); cd "$HERE"
. "$HERE/packaging/lib.sh"
OUT=${1:-}; [ -n "$OUT" ] || die "usage: sh packaging/bundle.sh APPDIR"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
need_cmd curl "Install curl (apt install curl / dnf install curl)."
[ -x "$HERE/target/release/style-my-grub" ] || sh "$HERE/packaging/build-binary.sh"
QMAKE=${QMAKE:-$(command -v qmake6 || command -v qmake || true)}
[ -n "$QMAKE" ] || die "qmake6 not found (needed to locate Qt's plugins and QML modules). Run: sh packaging/build-binary.sh"
ARCH=$(uname -m); case "$ARCH" in x86_64|aarch64) ;; *) die "unsupported architecture $ARCH (x86_64 and aarch64 work)" ;; esac
export QMAKE QML_SOURCES_PATHS="$HERE/crates/app/qml" APPIMAGE_EXTRACT_AND_RUN=1 ARCH
export EXTRA_QT_MODULES="qml;quick;quickcontrols2"
QT_PLUGINS=$("$QMAKE" -query QT_INSTALL_PLUGINS 2>/dev/null || true)
# Wayland session support, when this Qt has it (otherwise the app still works through XWayland)
# Qt 6.8 merged the Wayland plugins into a single libqwayland.so; older releases have libqwayland-egl.so and
# libqwayland-generic.so. Without the Wayland plugin here the app runs through XWayland, where the desktop has no
# app_id to look its icon and name up by.
WL=
for p in libqwayland.so libqwayland-egl.so libqwayland-generic.so; do [ -f "$QT_PLUGINS/platforms/$p" ] && WL="${WL:+$WL;}$p"; done
[ -n "$WL" ] && export EXTRA_PLATFORM_PLUGINS="$WL"

TOOLS="$HERE/build/tools"; mkdir -p "$TOOLS"
fetch() {  # fetch <file> <url>
  [ -f "$TOOLS/$1" ] && return 0
  curl -fsSL --retry 3 -o "$TOOLS/$1.part" "$2" && mv "$TOOLS/$1.part" "$TOOLS/$1" && chmod +x "$TOOLS/$1"
}
LD_URL="https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$ARCH.AppImage"
LQ_URL="https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-$ARCH.AppImage"

progress_init 7
STEP_HINT="Download failed: check your internet connection, or put linuxdeploy-$ARCH.AppImage and linuxdeploy-plugin-qt-$ARCH.AppImage into build/tools/ yourself."
step "Downloading linuxdeploy"           fetch "linuxdeploy-$ARCH.AppImage" "$LD_URL"
step "Downloading its Qt plugin"         fetch "linuxdeploy-plugin-qt-$ARCH.AppImage" "$LQ_URL"
STEP_HINT=
stage() {
  rm -rf "$OUT"; PB_QUIET=1 sh "$HERE/packaging/install.sh" "$OUT" /usr
  # the binary must sit in usr/bin: its library path ($ORIGIN/../lib) and qt.conf are relative to it
  mv "$OUT/usr/libexec/style-my-grub/style-my-grub-bin" "$OUT/usr/bin/style-my-grub-bin"
}
step "Staging the files"                 stage
# linuxdeploy looks the plugin up by name on PATH
PATH="$TOOLS:$PATH"; export PATH
deploy() {
  cd "$TOOLS"
  "./linuxdeploy-$ARCH.AppImage" --appdir "$OUT" --executable "$OUT/usr/bin/style-my-grub-bin" --plugin qt \
    -d "$OUT/usr/share/applications/dev.stylemygrub.StyleMyGrub.desktop" -i "$OUT/usr/share/icons/hicolor/512x512/apps/dev.stylemygrub.StyleMyGrub.png"
}
STEP_HINT="linuxdeploy needs the Qt QML modules of the Qt used to build (QML_SOURCES_PATHS is set for you). Check that qmake is the one from your Qt 6."
step "Bundling Qt (libraries, plugins, QML)" deploy
STEP_HINT=
cxxrt() {
  # The C++ runtime is not bundled by linuxdeploy (it is on its exclude list), but a binary built with a recent GCC needs a
  # recent libstdc++ and an older system has a too-old one. So we carry ours in lib/cxx, and the launcher uses it ONLY when the
  # system's is older than what the bundle needs. A newer system copy must win: the host's graphics drivers (Mesa) are built
  # against it, and forcing an older one on them makes the driver fail to load, after which Qt aborts with a fatal error.
  mkdir -p "$OUT/usr/lib/cxx"
  for l in libstdc++.so.6 libgcc_s.so.1; do
    p=$(LD_LIBRARY_PATH="$OUT/usr/lib" ldd "$OUT/usr/bin/style-my-grub-bin" | awk -v l="$l" '$1==l && $3 ~ /^\// {print $3; exit}')
    [ -n "$p" ] && [ -e "$p" ] && cp -L "$p" "$OUT/usr/lib/cxx/$l"
  done
  # the newest GLIBCXX version anything in the bundle asks for
  req=$(for f in "$OUT/usr/bin/style-my-grub-bin" $(find "$OUT/usr/lib" -maxdepth 1 -name '*.so*') $(find "$OUT/usr/plugins" "$OUT/usr/qml" -name '*.so'); do objdump -T "$f" 2>/dev/null; done \
        | grep -oE 'GLIBCXX_3\.4\.[0-9]+' | sed 's/.*\.//' | sort -n | tail -n1)
  echo "${req:-0}" > "$OUT/usr/lib/cxx/required-glibcxx"
  # relative library path, so the binary finds its Qt even without the launcher (the launcher also sets LD_LIBRARY_PATH)
  if command -v patchelf >/dev/null 2>&1; then patchelf --set-rpath '$ORIGIN/../lib' "$OUT/usr/bin/style-my-grub-bin"; fi
  # QML modules that are only loaded by Qt's built-in file dialog (the fallback when no system chooser exists): the scanner
  # does not see them, and without them Qt crashes when that dialog opens
  QMLDIR=$("$QMAKE" -query QT_INSTALL_QML 2>/dev/null || true)
  QTLIBS=$("$QMAKE" -query QT_INSTALL_LIBS 2>/dev/null || true)
  for l in "$QTLIBS"/libQt6LabsFolderListModel.so.6* "$QTLIBS"/libQt6LabsSettings.so.6*; do [ -e "$l" ] && cp -aL "$l" "$OUT/usr/lib/"; done
  for m in Qt/labs/folderlistmodel Qt/labs/settings; do
    if [ -d "$QMLDIR/$m" ]; then
      mkdir -p "$OUT/usr/qml/$m" && cp -a "$QMLDIR/$m/." "$OUT/usr/qml/$m/"
      if command -v patchelf >/dev/null 2>&1; then
        for so in "$OUT/usr/qml/$m"/*.so; do [ -f "$so" ] && patchelf --set-rpath '$ORIGIN/../../../../lib' "$so"; done
      fi
    fi
  done
  # Wayland: the platform plugin alone is not enough. Qt looks for its graphics ("client buffer") integration in a plugin folder of its
  # own; without it Qt Quick cannot create an OpenGL context and aborts at start ("Failed to load client buffer integration:
  # wayland-egl ... Available client buffer integrations: ()"). linuxdeploy does not copy these folders, so we do.
  wl_platform=no
  for p in libqwayland.so libqwayland-egl.so libqwayland-generic.so; do [ -f "$OUT/usr/plugins/platforms/$p" ] && wl_platform=yes; done
  for d in wayland-graphics-integration-client wayland-decoration-client wayland-shell-integration; do
    if [ -d "$QT_PLUGINS/$d" ] && [ "$wl_platform" = yes ]; then
      mkdir -p "$OUT/usr/plugins/$d"
      for so in "$QT_PLUGINS/$d"/*.so; do
        [ -f "$so" ] || continue
        cp -L "$so" "$OUT/usr/plugins/$d/"
        if command -v patchelf >/dev/null 2>&1; then patchelf --set-rpath '$ORIGIN/../../lib' "$OUT/usr/plugins/$d/$(basename "$so")"; fi
      done
    fi
  done
  rm -rf "$OUT/usr/translations"
}
step "Adding the C++ runtime"            cxxrt
verify() {
  # Resolve every library of the binary, of all plugins and of all QML plugins with NO help from the environment: anything Qt-related that is
  # found outside the bundle, or not found at all, is a bug in the bundle.
  bad=0
  for f in "$OUT/usr/bin/style-my-grub-bin" $(find "$OUT/usr/plugins" "$OUT/usr/qml" -name '*.so'); do
    out=$(env -u LD_LIBRARY_PATH ldd "$f" 2>&1 || true)
    miss=$(echo "$out" | grep "not found" | head -3 | tr '\n' ' ')
    leak=$(echo "$out" | grep -E 'libQt6[A-Za-z0-9]*\.so' | grep -v "$OUT" | head -2 | tr '\n' ' ')
    [ -n "$miss" ] && { echo "$f: missing: $miss"; bad=1; }
    [ -n "$leak" ] && { echo "$f: resolves Qt outside the bundle: $leak"; bad=1; }
  done
  # a Wayland platform plugin without its graphics integration compiles fine but aborts at start on Wayland (Failed to create RHI)
  if ls "$OUT"/usr/plugins/platforms/libqwayland*.so >/dev/null 2>&1 && ! ls "$OUT"/usr/plugins/wayland-graphics-integration-client/libqt-plugin-wayland-egl.so >/dev/null 2>&1; then
    echo "Wayland support is bundled without wayland-graphics-integration-client (the app would abort on Wayland)"; bad=1
  fi
  [ -f "$OUT/usr/bin/qt.conf" ] && [ -f "$OUT/usr/lib/libQt6Core.so.6" ] && [ -d "$OUT/usr/qml/QtQuick/Controls" ] || { echo "bundle is incomplete (qt.conf / libQt6Core / QML modules)"; bad=1; }
  [ "$bad" = 0 ]
}
step "Checking nothing leaks to the system's Qt" verify
glibc_need() {
  for f in "$OUT/usr/bin/style-my-grub-bin" $(find "$OUT/usr/lib" "$OUT/usr/plugins" -name '*.so*' -type f); do objdump -T "$f" 2>/dev/null; done \
    | grep -oE 'GLIBC_[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/GLIBC_//' | sort -uV | tail -n1
}
GL=$(glibc_need)
step "Measuring the glibc requirement" true
printf '%s\n' "${GL:-unknown}" > "$OUT/glibc-required.txt"
say "Bundle ready: $OUT  (needs glibc >= ${GL:-?}, Qt $("$QMAKE" -query QT_VERSION 2>/dev/null))"
