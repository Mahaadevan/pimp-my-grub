#!/bin/sh
# Shared install step used by every package format.  usage: install.sh DESTDIR PREFIX
set -eu
D=${1:-}; P=${2:-/usr}
HERE=$(cd "$(dirname "$0")/.." && pwd)
install -Dm755 "$HERE/target/release/pimp-my-grub" "$D$P/bin/pimp-my-grub"
install -Dm755 "$HERE/helper/pimp-my-grub-helper.sh" "$D$P/libexec/pimp-my-grub/pimp-my-grub-helper"
install -Dm644 "$HERE/packaging/dev.pimpmygrub.policy" "$D$P/share/polkit-1/actions/dev.pimpmygrub.policy"
install -Dm644 "$HERE/packaging/dev.pimpmygrub.PimpMyGrub.desktop" "$D$P/share/applications/dev.pimpmygrub.PimpMyGrub.desktop"
install -Dm644 "$HERE/packaging/dev.pimpmygrub.PimpMyGrub.metainfo.xml" "$D$P/share/metainfo/dev.pimpmygrub.PimpMyGrub.metainfo.xml"
install -Dm644 "$HERE/packaging/pimp-my-grub.png" "$D$P/share/icons/hicolor/512x512/apps/pimp-my-grub.png"
for S in 256 128 64 48 32; do
  install -Dm644 "$HERE/packaging/icons/pimp-my-grub-$S.png" "$D$P/share/icons/hicolor/${S}x${S}/apps/pimp-my-grub.png"
done
