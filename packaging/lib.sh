# Shared helpers for the packaging scripts: a nala-style progress display, step runner with log capture, error reporting.
# Source it:  . "$(dirname "$0")/lib.sh"      then:  progress_init 5; step "Doing a thing" some command args
#
# On a terminal each step shows a live spinner line (with the latest line of build output) above a full-width
# "Total" bar that is re-measured every tick, so it resizes with the window. Finished steps stay as ✔ lines.
# Not a terminal (CI, pipes): plain "[n/N] label" lines.
# Env: PB_QUIET=1 (no output, errors still reported) · PB_NOREPORT=1 (skip "Created:" lines) · NO_COLOR=1 · LOGFILE=path

PB_TOTAL=1; PB_N=0; PB_TTY=0; PB_START=0
[ -t 2 ] && PB_TTY=1
if [ "$PB_TTY" = 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_OK=$(printf '\033[32m'); C_ERR=$(printf '\033[31m'); C_DIM=$(printf '\033[2m'); C_ACC=$(printf '\033[38;5;209m')
  C_GRY=$(printf '\033[90m'); C_OFF=$(printf '\033[0m')
else
  C_OK=; C_ERR=; C_DIM=; C_ACC=; C_GRY=; C_OFF=
fi
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) CH_FULL='━'; CH_HEAD='╸'; CH_EMPTY='━'; CH_OK='✔'; CH_BAD='✘'; CH_DOT='•' ;;
  *)                                CH_FULL='#'; CH_HEAD='>'; CH_EMPTY='-'; CH_OK='OK'; CH_BAD='x';  CH_DOT='|' ;;
esac
LOGFILE=${LOGFILE:-$(mktemp "${TMPDIR:-/tmp}/pimp-my-grub-build.XXXXXX")}
export LOGFILE
PB_PID=

say()  { [ "${PB_QUIET:-0}" = 1 ] || printf '%s\n' "$*" >&2; }
warn() { printf '%swarning:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; }
die()  { printf '\r\033[K%serror:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

progress_init() { PB_TOTAL=$1; PB_N=0; PB_START=0; }

term_cols() {
  c=$(stty size <&2 2>/dev/null | cut -d' ' -f2)
  case "$c" in ''|*[!0-9]*) c=${COLUMNS:-80} ;; esac
  [ "$c" -lt 30 ] && c=30
  echo "$c"
}
fmt_time() { printf '%d:%02d:%02d' $(($1 / 3600)) $(($1 % 3600 / 60)) $(($1 % 60)); }
rep() { [ "$2" -gt 0 ] && printf '%*s' "$2" '' | sed "s/ /$1/g"; return 0; }   # rep <char> <count>

# _barline <permille>  — prints the "Total ━━━╸━━━ 45% • 3/7 • 0:00:12" line, sized to the current terminal width
_barline() {
  cols=$(term_cols); el=$(( $(date +%s) - PB_START ))
  tm=$(fmt_time "$el")
  plain=$(printf ' %3d%% | %d/%d | %s' $(($1 / 10)) "$PB_N" "$PB_TOTAL" "$tm")   # ASCII twin, only used to measure
  width=$(( cols - 6 - ${#plain} - 1 )); [ "$width" -lt 10 ] && width=10
  filled=$(( width * $1 / 1000 )); [ "$filled" -gt "$width" ] && filled=$width
  if [ "$filled" -ge "$width" ]; then head=; empty=0; else head=$CH_HEAD; empty=$(( width - filled - 1 )); fi
  printf 'Total %s%s%s%s%s%s%s %3d%% %s%s%s %d/%d %s%s%s %s' \
    "$C_ACC" "$(rep "$CH_FULL" "$filled")" "$head" "$C_GRY" "$(rep "$CH_EMPTY" "$empty")" "$C_OFF" \
    "" $(($1 / 10)) "$C_DIM" "$CH_DOT" "$C_OFF" "$PB_N" "$PB_TOTAL" "$C_DIM" "$CH_DOT" "$C_OFF" "$tm"
}

_cleanup() { [ -n "$PB_PID" ] && kill "$PB_PID" 2>/dev/null; [ "$PB_TTY" = 1 ] && printf '\n' >&2; exit 130; }
trap _cleanup INT TERM
trap ':' WINCH   # the bar is re-measured every tick, so a resize just takes effect on the next redraw

_spinner() {
  case $(( $1 % 10 )) in 0) printf '⠋';; 1) printf '⠙';; 2) printf '⠹';; 3) printf '⠸';; 4) printf '⠼';;
                         5) printf '⠴';; 6) printf '⠦';; 7) printf '⠧';; 8) printf '⠇';; *) printf '⠏';; esac
}

# step "label" command [args...]  — runs the command with its output going to $LOGFILE; aborts with the log tail on failure.
step() {
  label=$1; shift
  PB_N=$((PB_N + 1))
  [ "$PB_START" = 0 ] && PB_START=$(date +%s)
  printf '\n### [%d/%d] %s\n' "$PB_N" "$PB_TOTAL" "$label" >>"$LOGFILE"
  live=0; [ "$PB_TTY" = 1 ] && [ "${PB_QUIET:-0}" != 1 ] && live=1
  if [ "$live" = 1 ]; then printf '\n' >&2
  elif [ "${PB_QUIET:-0}" != 1 ]; then printf '[%d/%d] %s\n' "$PB_N" "$PB_TOTAL" "$label" >&2; fi

  "$@" >>"$LOGFILE" 2>&1 &
  PB_PID=$!
  t0=$(date +%s); k=0
  if [ "$live" = 1 ]; then
    if [ "$PB_TTY" = 1 ]; then : ; fi
    while kill -0 "$PB_PID" 2>/dev/null; do
      el=$(( $(date +%s) - t0 )); k=$((k + 1))
      frac=$(( el * 1000 / (el + 30) ))                 # creeps towards the next step while a long one runs
      pm=$(( ((PB_N - 1) * 1000 + frac) / PB_TOTAL ))
      cols=$(term_cols); avail=$(( cols - ${#label} - 12 )); [ "$avail" -lt 0 ] && avail=0
      last=$(tail -n 1 "$LOGFILE" 2>/dev/null | tr -d '\r' | cut -c1-"$avail")
      printf '\033[1A\r\033[K%s%s%s %s %s%ss  %s%s\n\r\033[K%s' \
        "$C_ACC" "$(_spinner "$k")" "$C_OFF" "$label" "$C_DIM" "$el" "$last" "$C_OFF" "$(_barline "$pm")" >&2
      sleep 0.2 2>/dev/null || sleep 1
    done
  fi
  rc=0; wait "$PB_PID" || rc=$?
  PB_PID=
  took=$(( $(date +%s) - t0 ))
  if [ "$rc" -ne 0 ]; then
    [ "$live" = 1 ] && printf '\r\033[K\033[1A\r\033[K' >&2
    printf '%s%s failed:%s %s (exit %d)\n' "$C_ERR" "$CH_BAD" "$C_OFF" "$label" "$rc" >&2
    printf '%s--- last lines of the log ---%s\n' "$C_DIM" "$C_OFF" >&2
    tail -n 30 "$LOGFILE" >&2
    printf '%sfull log: %s%s\n' "$C_DIM" "$LOGFILE" "$C_OFF" >&2
    [ -n "${STEP_HINT:-}" ] && printf '%shint:%s %s\n' "$C_ACC" "$C_OFF" "$STEP_HINT" >&2
    exit "$rc"
  fi
  if [ "$live" = 1 ]; then
    printf '\r\033[K\033[1A\r\033[K%s%s%s %s %s(%ss)%s\n%s' "$C_OK" "$CH_OK" "$C_OFF" "$label" "$C_DIM" "$took" "$C_OFF" \
      "$(_barline $(( PB_N * 1000 / PB_TOTAL )))" >&2
    [ "$PB_N" -ge "$PB_TOTAL" ] && printf '\n' >&2
  elif [ "${PB_QUIET:-0}" != 1 ]; then
    printf '    %s%s%s done (%ss)\n' "$C_OK" "$CH_OK" "$C_OFF" "$took" >&2
  fi
  return 0
}

# report_file <path> — tells the user where a produced file ended up (absolute path and size)
report_file() {
  [ "${PB_NOREPORT:-0}" = 1 ] && return 0
  [ -e "$1" ] || { warn "expected output not found: $1"; return 0; }
  d=$(cd "$(dirname "$1")" && pwd); abs="$d/$(basename "$1")"
  size=$(du -h "$abs" 2>/dev/null | cut -f1)
  printf '%s%s Created:%s %s %s(%s)%s\n' "$C_OK" "$CH_OK" "$C_OFF" "$abs" "$C_DIM" "$size" "$C_OFF" >&2
  return 0
}

# need_cmd <command> <how to get it>
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found. $2"; }
