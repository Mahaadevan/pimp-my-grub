# Shared helpers for the packaging scripts: a progress bar, step runner with log capture, and error reporting.
# Source it:  . "$(dirname "$0")/lib.sh"      then:  progress_init 5; step "Doing a thing" some command args
# Env: PB_QUIET=1 (no output, errors still reported) · NO_COLOR=1 · LOGFILE=path (default: a temp file)

PB_TOTAL=1; PB_N=0; PB_TTY=0
[ -t 2 ] && PB_TTY=1
if [ "$PB_TTY" = 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK=$(printf '\033[32m'); C_ERR=$(printf '\033[31m'); C_DIM=$(printf '\033[2m'); C_ACC=$(printf '\033[38;5;209m'); C_OFF=$(printf '\033[0m')
else
  C_OK=; C_ERR=; C_DIM=; C_ACC=; C_OFF=
fi
LOGFILE=${LOGFILE:-$(mktemp "${TMPDIR:-/tmp}/pimp-my-grub-build.XXXXXX")}
export LOGFILE
PB_PID=

say()  { [ "${PB_QUIET:-0}" = 1 ] || printf '%s\n' "$*" >&2; }
warn() { printf '%swarning:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; }
die()  { printf '\r\033[K%serror:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

progress_init() { PB_TOTAL=$1; PB_N=0; }

# _bar <completed-steps> <label> [suffix]
_bar() {
  [ "${PB_QUIET:-0}" = 1 ] && return 0
  w=28; done_n=$1; filled=$(( done_n * w / PB_TOTAL )); i=0; b=
  while [ "$i" -lt "$w" ]; do
    if [ "$i" -lt "$filled" ]; then b="$b#"; else b="$b-"; fi
    i=$((i + 1))
  done
  pct=$(( done_n * 100 / PB_TOTAL ))
  printf '\r\033[K%s[%s]%s %3d%% %s(%d/%d)%s %s %s' "$C_ACC" "$b" "$C_OFF" "$pct" "$C_DIM" "$PB_N" "$PB_TOTAL" "$C_OFF" "$2" "$3" >&2
}

_cleanup() { [ -n "$PB_PID" ] && kill "$PB_PID" 2>/dev/null; [ "$PB_TTY" = 1 ] && printf '\n' >&2; exit 130; }
trap _cleanup INT TERM

# step "label" command [args...]  — runs the command with output going to $LOGFILE; shows the bar; aborts with the log tail on failure.
step() {
  label=$1; shift
  PB_N=$((PB_N + 1))
  printf '\n### [%d/%d] %s\n' "$PB_N" "$PB_TOTAL" "$label" >>"$LOGFILE"
  if [ "${PB_QUIET:-0}" != 1 ] && [ "$PB_TTY" = 0 ]; then printf '[%d/%d] %s\n' "$PB_N" "$PB_TOTAL" "$label" >&2; fi
  "$@" >>"$LOGFILE" 2>&1 &
  PB_PID=$!
  start=$(date +%s); spin='|/-\'; k=0
  if [ "$PB_TTY" = 1 ]; then
    while kill -0 "$PB_PID" 2>/dev/null; do
      k=$(( (k + 1) % 4 )); ch=$(printf '%s' "$spin" | cut -c$((k + 1)))
      last=$(tail -n 1 "$LOGFILE" 2>/dev/null | tr -d '\r' | cut -c1-48)
      _bar $((PB_N - 1)) "$label" "$C_DIM$ch $(( $(date +%s) - start ))s  $last$C_OFF"
      sleep 0.2 2>/dev/null || sleep 1
    done
  fi
  rc=0; wait "$PB_PID" || rc=$?
  PB_PID=
  if [ "$rc" -ne 0 ]; then
    [ "$PB_TTY" = 1 ] && printf '\r\033[K' >&2
    printf '%s✗ failed:%s %s (exit %d)\n' "$C_ERR" "$C_OFF" "$label" "$rc" >&2
    printf '%s--- last lines of the log ---%s\n' "$C_DIM" "$C_OFF" >&2
    tail -n 30 "$LOGFILE" >&2
    printf '%sfull log: %s%s\n' "$C_DIM" "$LOGFILE" "$C_OFF" >&2
    [ -n "${STEP_HINT:-}" ] && printf '%shint:%s %s\n' "$C_ACC" "$C_OFF" "$STEP_HINT" >&2
    exit "$rc"
  fi
  if [ "$PB_TTY" = 1 ]; then _bar "$PB_N" "$label" "${C_OK}✓${C_OFF}"; [ "${PB_QUIET:-0}" = 1 ] || printf '\n' >&2; fi
  return 0
}

# need_cmd <command> <how to get it>
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found. $2"; }
