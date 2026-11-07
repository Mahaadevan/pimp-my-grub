#!/bin/sh
# One-shot release build: compiles the binary (installing Rust/Qt libs if needed), then makes the packages this machine can.
# usage: sh packaging/build-release.sh [deb] [appimage] [rpm]     (no arguments = all of them)
# Outputs land in ./dist. Run on Ubuntu 24.04 (deb + AppImage) or Fedora (rpm); CI does both (.github/workflows/release.yml).
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd); cd "$HERE"
. "$HERE/packaging/lib.sh"
WANT=${*:-"deb appimage rpm"}
for w in $WANT; do case "$w" in deb|appimage|rpm) ;; *) die "unknown target '$w' (use deb, appimage, rpm)" ;; esac; done
VER=$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -n1)

say "== Step 1: compile the binary"
sh packaging/build-binary.sh
mkdir -p dist
say "== Step 2: packages ($WANT)"
for w in $WANT; do
  case "$w" in
    deb)
      PB_NOREPORT=1 sh packaging/build-deb.sh && mv -f ./*.deb dist/ ;;
    appimage)
      PB_NOREPORT=1 sh packaging/build-appimage.sh && mv -f build/*.AppImage dist/ ;;
    rpm)
      need_cmd rpmbuild "Fedora: sudo dnf install rpm-build"
      [ -z "$(git status --porcelain 2>/dev/null)" ] || warn "uncommitted changes: the rpm is built from the last commit (git archive HEAD). Commit first (git add -A && git commit)."
      T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
      mkdir -p "$T/SOURCES"
      progress_init 2
      step "Creating source tarball" git archive --format=tar.gz --prefix="pimp-my-grub-$VER/" -o "$T/SOURCES/pimp-my-grub-$VER.tar.gz" HEAD
      step "Building the rpm (compiles inside rpmbuild, takes a while)" rpmbuild -ba packaging/pimp-my-grub.spec --define "_topdir $T"
      cp "$T"/RPMS/*/*.rpm "$T"/SRPMS/*.rpm dist/ ;;
  esac
done
say ""
say "== Done. Release files:"
for f in dist/*; do [ -f "$f" ] && report_file "$f"; done
report_file target/release/pimp-my-grub
