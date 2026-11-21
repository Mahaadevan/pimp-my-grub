#!/bin/sh
# Launcher installed as `style-my-grub`. It starts the real binary and, if that dies right at startup, recovers or explains
# instead of failing silently when started from the app menu. From a terminal it just runs the binary, so errors print as usual.
#
# Two layouts are supported:
#  * a bundle (AppImage, the .deb): bin/ lib/ plugins/ qml/ side by side. The app brings its own Qt, and this script makes sure
#    ONLY those are used, whatever Qt versions the system has (mixing them gives errors such as
#    "undefined symbol: _ZNK11QQmlProperty..."). The bundled C++ runtime (lib/cxx) is used only if the system's is older.
#  * a system install (.rpm, Arch): the binary sits in ../libexec and uses the distribution's Qt.
#
# Normal mode uses Qt's own graphics stack (EGL on Wayland, GLX/EGL on X11). Safe mode - software drawing over X11 - is switched on
# automatically when the first start crashes within a few seconds and the second, safe start works. Force it with STYLEMYGRUB_SAFE=1;
# undo with STYLEMYGRUB_SAFE=0 or by deleting ~/.cache/style-my-grub/safe-mode.
D=$(dirname "$(readlink -f "$0")")
ROOT=$(cd "$D/.." && pwd)
BIN="$D/style-my-grub-bin"
[ -x "$BIN" ] || BIN="$ROOT/libexec/style-my-grub/style-my-grub-bin"
[ -x "$BIN" ] || { echo "style-my-grub: binary not found next to $0" >&2; exit 127; }
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/style-my-grub
LOG=$CACHE/last-run.log
SAFE_MARK=$CACHE/safe-mode

# newest GLIBCXX_3.4.N of the system's libstdc++ (prints N, or 0 if none can be found)
host_glibcxx() {
  f=""
  for c in "${STYLEMYGRUB_HOST_LIBSTDCXX:-}" $( { /sbin/ldconfig -p || ldconfig -p; } 2>/dev/null | awk '/libstdc\+\+\.so\.6 /{print $NF}') \
           /usr/lib64/libstdc++.so.6 /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /usr/lib/aarch64-linux-gnu/libstdc++.so.6 /usr/lib/libstdc++.so.6 /lib64/libstdc++.so.6; do
    if [ -n "$c" ] && [ -r "$c" ]; then f=$c; break; fi
  done
  [ -n "$f" ] || { echo 0; return; }
  n=$(LC_ALL=C grep -a -o 'GLIBCXX_3\.4\.[0-9][0-9]*' "$f" 2>/dev/null | sed 's/.*\.//' | sort -n | tail -n1)
  echo "${n:-0}"
}

if [ -e "$ROOT/lib/libQt6Core.so.6" ]; then
  LDP="$ROOT/lib"
  if [ -d "$ROOT/lib/cxx" ]; then
    need=$(cat "$ROOT/lib/cxx/required-glibcxx" 2>/dev/null || echo 0)
    have=$(host_glibcxx)
    if [ "${have:-0}" -lt "${need:-0}" ] 2>/dev/null; then LDP="$ROOT/lib/cxx:$LDP"; fi
  fi
  export LD_LIBRARY_PATH="$LDP${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export QT_PLUGIN_PATH="$ROOT/plugins"
  export QT_QPA_PLATFORM_PLUGIN_PATH="$ROOT/plugins/platforms"
  export QML2_IMPORT_PATH="$ROOT/qml" QML_IMPORT_PATH="$ROOT/qml"
  unset QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE QML_DISABLE_DISK_CACHE
fi
if [ "${STYLEMYGRUB_PRINT_ENV:-}" = 1 ]; then echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"; exit 0; fi   # for diagnosis

safe_env() {   # last resort: no GPU context, and X11 (through XWayland) instead of Wayland
  export QT_QUICK_BACKEND=software
  [ -n "${DISPLAY:-}" ] && export QT_QPA_PLATFORM=xcb
}
SAFE=0
if [ "${STYLEMYGRUB_SAFE:-}" = 1 ] || { [ -e "$SAFE_MARK" ] && [ "${STYLEMYGRUB_SAFE:-}" != 0 ]; }; then SAFE=1; safe_env; fi
export RUST_BACKTRACE=${RUST_BACKTRACE:-1}

if [ -t 2 ]; then exec "$BIN" "$@"; fi

mkdir -p "$CACHE" 2>/dev/null
run_once() {   # sets rc and secs; stderr goes to the log
  t0=$(date +%s)
  "$BIN" "$@" 2>"$LOG"
  rc=$?
  secs=$(( $(date +%s) - t0 ))
}
looks_like_graphics_problem() {
  grep -qiE "could not load the qt platform plugin|failed to create|could not initialize|rhi|egl|opengl|glx|wayland|xdg|xcb|libGL|GLIBCXX" "$LOG" 2>/dev/null
}

# exit codes that mean "the program crashed": SIGILL 132, SIGTRAP 133, SIGABRT 134, SIGBUS 135, SIGFPE 136, SIGSEGV 139.
# A program that was simply stopped (SIGHUP 129, SIGINT 130, SIGTERM 143, SIGPIPE 141) is not a crash and must not be restarted.
is_crash() { case "$1" in 132|133|134|135|136|139) return 0;; esac; return 1; }
stopped_by_user() { case "$1" in 129|130|141|143) return 0;; esac; return 1; }

run_once "$@"
[ "$rc" -eq 0 ] && exit 0
stopped_by_user "$rc" && exit "$rc"
[ "$secs" -gt 15 ] && exit "$rc"     # it ran for a while: not a startup failure (only a note below if it crashed)

# a crash (killed by a signal) or a graphics / window-system error in the first seconds: try again in safe mode
if [ "$SAFE" -eq 0 ] && { is_crash "$rc" || looks_like_graphics_problem; } && ! grep -qE "is not installed|QML module" "$LOG" 2>/dev/null; then
  cp "$LOG" "$CACHE/first-attempt.log" 2>/dev/null
  safe_env
  run_once "$@"
  if [ "$rc" -eq 0 ] || [ "$secs" -gt 15 ]; then
    : > "$SAFE_MARK"      # safe mode works here: use it from now on (delete the file to try normal mode again)
    exit 0
  fi
  cp "$CACHE/first-attempt.log" "$CACHE/first-attempt.keep" 2>/dev/null
fi

msg="Style My GRUB could not start (exit code $rc)."
if grep -qE "GLIBC_[0-9.]+' not found|GLIBCXX_|CXXABI_" "$LOG" 2>/dev/null && ! grep -q "egl\|EGL" "$LOG" 2>/dev/null; then
  msg="$msg

This build needs a newer C library (glibc) than this system has ($(getconf GNU_LIBC_VERSION 2>/dev/null | cut -d' ' -f2)).
Download the \"portable\" (older-system) build from the project's releases page, or build from source."
elif grep -qE "is not installed|QML module" "$LOG" 2>/dev/null; then
  msg="$msg

A Qt 6 QML module is missing. On Debian/Ubuntu install:
  sudo apt install qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-dialogs \\
    qml6-module-qtquick-templates qml6-module-qtquick-window qml6-module-qtqml-workerscript
On other distros install the full qt6-declarative package, or use the AppImage / .deb from the releases page (they bring their own Qt)."
elif grep -qE "undefined symbol|version .Qt_6|cannot open shared object" "$LOG" 2>/dev/null; then
  msg="$msg

A system library does not match this build (see the details below).
If you installed from a package built for another distribution, use the AppImage or the .deb from the releases page: they carry their own Qt."
elif is_crash "$rc" || looks_like_graphics_problem; then
  msg="$msg

The program crashed while starting, also in safe mode (software drawing, X11). This is usually a graphics-driver or window-system problem.
Please send the files in $CACHE (last-run.log, first-attempt.keep, crash.log) together with your distribution, desktop and
the output of:  echo \$XDG_SESSION_TYPE  and  glxinfo -B  (or  eglinfo -B )."
fi
msg="$msg

Details: $(tail -n 3 "$LOG" 2>/dev/null | cut -c1-200)
Full log: $LOG"
if   command -v zenity   >/dev/null 2>&1; then zenity --error --title="Style My GRUB" --no-markup --text="$msg" 2>/dev/null
elif command -v kdialog  >/dev/null 2>&1; then kdialog --error "$msg" --title "Style My GRUB" 2>/dev/null
elif command -v notify-send >/dev/null 2>&1; then notify-send -u critical "Style My GRUB could not start" "$msg"
elif command -v xmessage >/dev/null 2>&1; then xmessage -center "$msg"
fi
exit "$rc"
