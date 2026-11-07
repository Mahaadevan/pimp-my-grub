#!/bin/sh
# Shared install step used by every package format.  usage: install.sh DESTDIR PREFIX
# Shows a progress bar on a terminal; set PB_QUIET=1 to silence it (build-deb.sh does).
set -eu
D=${1:-}; P=${2:-/usr}
HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/packaging/lib.sh"
[ -x "$HERE/target/release/pimp-my-grub" ] || die "target/release/pimp-my-grub is missing. Run: sh packaging/build-binary.sh"
progress_init 9
step "Installing binary"             install -Dm755 "$HERE/target/release/pimp-my-grub" "$D$P/libexec/pimp-my-grub/pimp-my-grub-bin"
step "Installing launcher"           install -Dm755 "$HERE/helper/pimp-my-grub-launcher.sh" "$D$P/bin/pimp-my-grub"
step "Installing root helper"        install -Dm755 "$HERE/helper/pimp-my-grub-helper.sh" "$D$P/libexec/pimp-my-grub/pimp-my-grub-helper"
step "Installing polkit policy"      install -Dm644 "$HERE/packaging/dev.pimpmygrub.policy" "$D$P/share/polkit-1/actions/dev.pimpmygrub.policy"
step "Installing desktop entry"      install -Dm644 "$HERE/packaging/dev.pimpmygrub.PimpMyGrub.desktop" "$D$P/share/applications/dev.pimpmygrub.PimpMyGrub.desktop"
step "Installing app metadata"       install -Dm644 "$HERE/packaging/dev.pimpmygrub.PimpMyGrub.metainfo.xml" "$D$P/share/metainfo/dev.pimpmygrub.PimpMyGrub.metainfo.xml"
step "Installing icon (512 px)"      install -Dm644 "$HERE/packaging/pimp-my-grub.png" "$D$P/share/icons/hicolor/512x512/apps/pimp-my-grub.png"
icons() { for S in 256 128 64 48 32; do install -Dm644 "$HERE/packaging/icons/pimp-my-grub-$S.png" "$D$P/share/icons/hicolor/${S}x${S}/apps/pimp-my-grub.png"; done; }
step "Installing smaller icon sizes" icons
step "Verifying installed files"     test -x "$D$P/bin/pimp-my-grub" -a -f "$D$P/share/icons/hicolor/32x32/apps/pimp-my-grub.png"
