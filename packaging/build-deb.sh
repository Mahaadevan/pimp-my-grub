#!/bin/sh
# Builds pimp-my-grub_<ver>_<arch>.deb (Debian 13+, Ubuntu 24.04+, Mint 22+). Run after `cargo build --release`.
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
VER=$(sed -n 's/^version = "\(.*\)"/\1/p' "$HERE/Cargo.toml" | head -n1)
ARCH=$(dpkg --print-architecture)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
chmod 755 "$T"
sh "$HERE/packaging/install.sh" "$T" /usr
install -d "$T/DEBIAN"
SIZE=$(du -sk "$T/usr" | cut -f1)
cat > "$T/DEBIAN/control" <<C
Package: pimp-my-grub
Version: $VER
Section: utils
Priority: optional
Architecture: $ARCH
Installed-Size: $SIZE
Depends: libc6, libqt6quick6, libqt6gui6, libqt6qml6, libqt6core6, qml6-module-qtquick, qml6-module-qtquick-controls, qml6-module-qtquick-layouts, qml6-module-qtquick-dialogs, qml6-module-qtquick-templates, qml6-module-qtquick-window, qml6-module-qtqml-workerscript, polkitd | policykit-1
Recommends: grub-common, qml6-module-qt-labs-platform
Suggests: qqc2-desktop-style
Maintainer: Pimp my grub <dev@pimpmygrub.local>
Description: Native Qt 6 GRUB theme builder
 Visual editor, theme store and a reversible installer that shows every
 change and asks for confirmation before touching /boot or /etc.
C
dpkg-deb --root-owner-group --build "$T" "$HERE/pimp-my-grub_${VER}_${ARCH}.deb"
