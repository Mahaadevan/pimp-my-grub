#!/bin/sh
# AppImage: the app plus its own Qt 6, C++ runtime, plugins and fonts in one file (see bundle.sh). Runs on any x86_64 / aarch64
# Linux with a glibc at least as new as the machine that built it, whatever Qt the system has. The AppImage cannot ship the
# polkit policy, so the app falls back to `pkexec /bin/sh -c <helper>` (generic password prompt).
# For the widest reach build on an OLD system (CI uses Ubuntu 20.04, see .github/workflows/release.yml).
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd); cd "$HERE"
. "$HERE/packaging/lib.sh"
VER=$(sed -n 's/^version = "\(.*\)"/\1/p' "$HERE/Cargo.toml" | head -n1)
ARCH=$(uname -m)
APPDIR="$HERE/build/AppDir"
mkdir -p build
PB_NOREPORT=1 sh "$HERE/packaging/bundle.sh" "$APPDIR"
TOOLS="$HERE/build/tools"
progress_init 2
STEP_HINT="Download failed: check your internet connection, or put appimagetool-$ARCH.AppImage into build/tools/ yourself."
step "Downloading appimagetool" sh -c "[ -f '$TOOLS/appimagetool-$ARCH.AppImage' ] || { curl -fsSL --retry 3 -o '$TOOLS/appimagetool.part' 'https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage' && mv '$TOOLS/appimagetool.part' '$TOOLS/appimagetool-$ARCH.AppImage' && chmod +x '$TOOLS/appimagetool-$ARCH.AppImage'; }"
STEP_HINT=
OUTF="$HERE/build/pimp-my-grub-$VER-$ARCH.AppImage"
rm -f "$OUTF"
step "Packing the AppImage" env APPIMAGE_EXTRACT_AND_RUN=1 ARCH="$ARCH" "$TOOLS/appimagetool-$ARCH.AppImage" --no-appstream "$APPDIR" "$OUTF"
need=$(cat "$APPDIR/glibc-required.txt" 2>/dev/null || echo "?")
say "This AppImage needs glibc >= $need (the machine it was built on). Older systems need an AppImage built on an older machine."
report_file "$OUTF"
