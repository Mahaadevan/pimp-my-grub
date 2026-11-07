#!/bin/sh
# Compiles target/release/pimp-my-grub, installing Rust and the Qt 6 build libraries first when they are missing.
# usage: sh packaging/build-binary.sh [--no-install] [--clean] [--debug]
#   --no-install  only check; never install anything (prints what is missing and exits)
#   --clean       cargo clean the app crate first (use after switching Qt installs)
# Supports apt (Debian/Ubuntu/Mint), dnf (Fedora/RHEL), pacman (Arch), zypper (openSUSE). Needs sudo for system packages.
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd); cd "$HERE"
. "$HERE/packaging/lib.sh"

INSTALL=1; CLEAN=0; PROFILE=release
for a in "$@"; do case "$a" in
  --no-install) INSTALL=0 ;; --clean) CLEAN=1 ;; --debug) PROFILE=debug ;;
  -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
  *) die "unknown option '$a' (try --help)" ;;
esac; done

# ---------------------------------------------------------------- detect the system
OSID=; OSLIKE=
[ -r /etc/os-release ] && . /etc/os-release && { OSID=${ID:-}; OSLIKE=${ID_LIKE:-}; }
PM=
case " $OSID $OSLIKE " in
  *" debian "*|*" ubuntu "*) PM=apt ;;
  *" fedora "*|*" rhel "*|*" centos "*) PM=dnf ;;
  *" arch "*) PM=pacman ;;
  *" suse "*|*" opensuse "*) PM=zypper ;;
esac
if [ -z "$PM" ]; then
  for pair in apt-get:apt dnf:dnf pacman:pacman zypper:zypper; do
    if command -v "${pair%%:*}" >/dev/null 2>&1; then PM=${pair##*:}; break; fi
  done
fi

SUDO=
if [ "$(id -u)" -ne 0 ]; then command -v sudo >/dev/null 2>&1 && SUDO=sudo || SUDO=none; fi

# ---------------------------------------------------------------- what is missing?
find_qmake() {
  [ -n "${QMAKE:-}" ] && [ -x "$QMAKE" ] && { echo "$QMAKE"; return; }
  for c in /usr/bin/qmake6 /usr/lib64/qt6/bin/qmake /usr/lib/qt6/bin/qmake "$(command -v qmake6 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    case "$c" in *conda*|*anaconda*|*miniforge*|*mamba*) continue ;; esac   # a conda Qt usually has no dev files
    echo "$c"; return
  done
}
qt_ok() {
  q=$(find_qmake); [ -n "$q" ] || return 1
  l=$("$q" -query QT_INSTALL_LIBS 2>/dev/null) || return 1
  [ -f "$l/libQt6QuickControls2.prl" ] && [ -f "$l/libQt6Quick.prl" ]
}
tools_ok() {
  command -v curl >/dev/null 2>&1 && command -v clang >/dev/null 2>&1 && { command -v c++ >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1; } && command -v pkg-config >/dev/null 2>&1
}
rust_ok() { command -v cargo >/dev/null 2>&1; }
[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

need_libs=0; need_rust=0
qt_ok && tools_ok || need_libs=1
rust_ok || need_rust=1

if [ "$INSTALL" = 0 ]; then
  [ "$need_libs" = 1 ] && warn "missing: Qt 6 development libraries and/or clang, a C++ compiler, curl, pkg-config"
  [ "$need_rust" = 1 ] && warn "missing: cargo (Rust)"
  [ "$need_libs$need_rust" = 00 ] && { say "everything needed is already installed"; exit 0; }
  exit 1
fi

# ---------------------------------------------------------------- plan the steps for the progress bar
total=3                                   # check, build, verify
[ "$need_libs" = 1 ] && total=$((total + 1))
[ "$need_rust" = 1 ] && total=$((total + 1))
[ "$CLEAN" = 1 ] && total=$((total + 1))
progress_init "$total"

# sudo up front, so the background steps below never wait for a hidden password prompt
if [ "$need_libs" = 1 ]; then
  [ "$PM" != "" ] || die "could not tell which package manager this system uses. Install manually: Qt 6 base + declarative dev packages (with QuickControls2), clang/libclang, a C++ compiler, curl, pkg-config."
  [ "$SUDO" != none ] || die "system packages are missing and 'sudo' is not available. Run as root or install sudo."
  if [ -n "$SUDO" ]; then say "Installing system libraries needs your password once:"; sudo -v || die "sudo authentication failed"; fi
fi

pkg_install() {
  case "$PM" in
    apt)    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update && \
            $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential pkg-config curl git clang libclang-dev \
              qt6-base-dev qt6-declarative-dev qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts \
              qml6-module-qtquick-dialogs qml6-module-qtquick-templates qml6-module-qtquick-window qml6-module-qtqml-workerscript ;;
    dnf)    $SUDO dnf install -y gcc-c++ make pkgconf-pkg-config curl git clang clang-devel qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtdeclarative ;;
    pacman) $SUDO pacman -Sy --needed --noconfirm base-devel pkgconf curl git clang qt6-base qt6-declarative ;;
    zypper) $SUDO zypper --non-interactive install gcc-c++ make pkg-config curl git clang clang-devel qt6-base-devel qt6-declarative-devel ;;
  esac
}
rustup_install() {
  command -v curl >/dev/null 2>&1 || exit 127
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o "${TMPDIR:-/tmp}/rustup-init.sh" && sh "${TMPDIR:-/tmp}/rustup-init.sh" -y --profile minimal --default-toolchain stable
}

# ---------------------------------------------------------------- run
STEP_HINT=
step "Checking the system ($OSID, package manager: ${PM:-unknown})" true

if [ "$need_libs" = 1 ]; then
  STEP_HINT="Install by hand if this keeps failing: Qt 6 base+declarative dev packages (must include libQt6QuickControls2.prl), clang, libclang, curl, a C++ compiler."
  step "Installing Qt 6, clang and build tools via $PM" pkg_install
  qt_ok || die "Qt packages installed but libQt6QuickControls2.prl is still not found for $(find_qmake). Set QMAKE=/path/to/qmake6 from a full system Qt install."
fi

if [ "$need_rust" = 1 ]; then
  STEP_HINT="Install Rust yourself from https://rustup.rs, then re-run this script."
  step "Installing Rust (cargo) with rustup" rustup_install
  [ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
  rust_ok || die "rustup finished but cargo is not on PATH. Run:  . \"\$HOME/.cargo/env\"  and retry."
fi
STEP_HINT=

QMAKE=$(find_qmake); [ -n "$QMAKE" ] || die "qmake6 not found"; export QMAKE

if [ "$CLEAN" = 1 ]; then step "Cleaning previous build" cargo clean -p pimp-my-grub; fi

STEP_HINT="Open the full log above. 'prl path for Qt module' means the Qt dev package is missing or QMAKE points at the wrong Qt (now using: $QMAKE); re-run with --clean after fixing. Missing 'libclang' means install clang/libclang."
if [ "$PROFILE" = release ]; then
  step "Compiling pimp-my-grub (release; the first build takes several minutes)" cargo build --release --locked -p pimp-my-grub
else
  step "Compiling pimp-my-grub (debug)" cargo build --locked -p pimp-my-grub
fi
STEP_HINT=

BIN=target/$PROFILE/pimp-my-grub
verify() { [ -x "$BIN" ]; }   # do not run it: the app has no --version and would open a window
step "Verifying $BIN" verify
if command -v readelf >/dev/null 2>&1 && readelf -V "$BIN" 2>/dev/null | grep -q Qt_6_PRIVATE_API; then
  warn "this binary uses Qt private API (QML compiled ahead of time). It only runs on the same Qt 6 minor version it was built with ($("$QMAKE" -query QT_VERSION 2>/dev/null)); package it with the AppImage (bundles Qt) or build on the oldest Qt you support."
fi
report_file "$HERE/$BIN"
