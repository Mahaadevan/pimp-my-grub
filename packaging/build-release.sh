#!/bin/sh
# One-shot release build: compiles the binary first, then makes whichever packages this machine can.
# usage: sh packaging/build-release.sh [deb] [appimage] [rpm]     (no arguments = all of them)
# Outputs land in ./dist. Run on Ubuntu 24.04 (deb + AppImage) or Fedora (rpm); CI does both (see .github/workflows/release.yml).
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd); cd "$HERE"
WANT=${*:-"deb appimage rpm"}
VER=$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -n1)

need() { command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' not found. $2" >&2; exit 1; }; }
need cargo "Install Rust: https://rustup.rs"
QMAKE=${QMAKE:-$(command -v qmake6 || command -v qmake || true)}
[ -n "$QMAKE" ] || { echo "error: qmake6 not found. Debian/Ubuntu: sudo apt install qt6-base-dev qt6-declarative-dev clang libclang-dev; Fedora: sudo dnf install qt6-qtbase-devel qt6-qtdeclarative-devel clang-devel gcc-c++" >&2; exit 1; }
export QMAKE

echo "==> building target/release/pimp-my-grub (Qt: $QMAKE)"
cargo build --release --locked -p pimp-my-grub
[ -x target/release/pimp-my-grub ] || { echo "error: cargo finished but target/release/pimp-my-grub is missing" >&2; exit 1; }

mkdir -p dist
for w in $WANT; do
  case "$w" in
    deb)
      need dpkg-deb "Run this step on Debian/Ubuntu."
      sh packaging/build-deb.sh && mv -f ./*.deb dist/ ;;
    appimage)
      sh packaging/build-appimage.sh && mv -f build/*.AppImage dist/ ;;
    rpm)
      need rpmbuild "Fedora: sudo dnf install rpm-build"
      T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
      mkdir -p "$T/SOURCES"
      git archive --format=tar.gz --prefix="pimp-my-grub-$VER/" -o "$T/SOURCES/pimp-my-grub-$VER.tar.gz" HEAD
      rpmbuild -ba packaging/pimp-my-grub.spec --define "_topdir $T"
      cp "$T"/RPMS/*/*.rpm "$T"/SRPMS/*.rpm dist/ ;;
    *) echo "unknown target '$w' (use deb, appimage, rpm)" >&2; exit 2 ;;
  esac
done
echo "==> done:"; ls -lh dist
