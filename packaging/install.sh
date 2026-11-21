#!/bin/sh
# Shared install step used by every package format.  usage: install.sh DESTDIR PREFIX
# Shows a progress bar on a terminal; set PB_QUIET=1 to silence it (build-deb.sh does).
set -eu
D=${1:-}; P=${2:-/usr}
HERE=$(cd "$(dirname "$0")/.." && pwd)
. "$HERE/packaging/lib.sh"
[ -x "$HERE/target/release/style-my-grub" ] || die "target/release/style-my-grub is missing. Run: sh packaging/build-binary.sh"
progress_init 9
step "Installing binary"             install -Dm755 "$HERE/target/release/style-my-grub" "$D$P/libexec/style-my-grub/style-my-grub-bin"
step "Installing launcher"           install -Dm755 "$HERE/helper/style-my-grub-launcher.sh" "$D$P/bin/style-my-grub"
step "Installing root helper"        install -Dm755 "$HERE/helper/style-my-grub-helper.sh" "$D$P/libexec/style-my-grub/style-my-grub-helper"
step "Installing polkit policy"      install -Dm644 "$HERE/packaging/dev.stylemygrub.policy" "$D$P/share/polkit-1/actions/dev.stylemygrub.policy"
step "Installing desktop entry"      install -Dm644 "$HERE/packaging/dev.stylemygrub.StyleMyGrub.desktop" "$D$P/share/applications/dev.stylemygrub.StyleMyGrub.desktop"
step "Installing app metadata"       install -Dm644 "$HERE/packaging/dev.stylemygrub.StyleMyGrub.metainfo.xml" "$D$P/share/metainfo/dev.stylemygrub.StyleMyGrub.metainfo.xml"
# The icon is installed under the application ID, not under the package name: KDE's icon loader, when a name is not
# found, retries without its last -separated word, so "style-my-grub" resolved to a theme's own "style" icon before the
# exact match in hicolor was reached. A dotted, hyphen-free name cannot collide with a themed icon.
step "Installing icon (512 px)"      install -Dm644 "$HERE/packaging/style-my-grub.png" "$D$P/share/icons/hicolor/512x512/apps/dev.stylemygrub.StyleMyGrub.png"
icons() { for S in 256 128 64 48 32; do install -Dm644 "$HERE/packaging/icons/style-my-grub-$S.png" "$D$P/share/icons/hicolor/${S}x${S}/apps/dev.stylemygrub.StyleMyGrub.png"; done; }
step "Installing smaller icon sizes" icons
step "Verifying installed files"     test -x "$D$P/bin/style-my-grub" -a -f "$D$P/share/icons/hicolor/32x32/apps/dev.stylemygrub.StyleMyGrub.png"
