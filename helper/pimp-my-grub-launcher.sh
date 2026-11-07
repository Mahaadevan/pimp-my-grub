#!/bin/sh
# Launcher installed as `pimp-my-grub`. It starts the real binary and, if that dies right at startup
# (typically: this build needs a newer Qt 6 than the system has), tells the user instead of failing silently
# when started from the app menu. From a terminal it just runs the binary, so errors print as usual.
D=$(dirname "$(readlink -f "$0")")
BIN="$D/../libexec/pimp-my-grub/pimp-my-grub-bin"
[ -x "$BIN" ] || BIN="$D/pimp-my-grub-bin"
[ -x "$BIN" ] || { echo "pimp-my-grub: binary not found next to $0" >&2; exit 127; }

if [ -t 2 ]; then exec "$BIN" "$@"; fi

LOGDIR=${XDG_CACHE_HOME:-$HOME/.cache}/pimp-my-grub
mkdir -p "$LOGDIR" 2>/dev/null; LOG=$LOGDIR/last-run.log
start=$(date +%s)
"$BIN" "$@" 2>"$LOG"
rc=$?
[ "$rc" -eq 0 ] && exit 0
[ $(( $(date +%s) - start )) -gt 10 ] && exit "$rc"     # it ran for a while: a crash later, not a startup failure

msg="Pimp my grub could not start (exit code $rc)."
if grep -qE "is not installed|QML module" "$LOG" 2>/dev/null; then
  msg="$msg

A Qt 6 QML module is missing. On Debian/Ubuntu install:
  sudo apt install qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-dialogs \\
    qml6-module-qtquick-templates qml6-module-qtquick-window qml6-module-qtqml-workerscript
On other distros install the full qt6-declarative package, or use the AppImage."
elif grep -qE "undefined symbol|version .Qt_6|cannot open shared object|GLIBC_" "$LOG" 2>/dev/null; then
  msg="$msg

This build was made for a different Qt 6 / system library version than the one installed here.
Use the AppImage, or a package built for your distribution."
fi
msg="$msg

Details: $(tail -n 3 "$LOG" 2>/dev/null | cut -c1-200)
Full log: $LOG"
if   command -v zenity   >/dev/null 2>&1; then zenity --error --title="Pimp my grub" --no-markup --text="$msg" 2>/dev/null
elif command -v kdialog  >/dev/null 2>&1; then kdialog --error "$msg" --title "Pimp my grub" 2>/dev/null
elif command -v notify-send >/dev/null 2>&1; then notify-send -u critical "Pimp my grub could not start" "$msg"
elif command -v xmessage >/dev/null 2>&1; then xmessage -center "$msg"
fi
exit "$rc"
