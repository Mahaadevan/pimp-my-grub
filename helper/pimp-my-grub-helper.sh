#!/bin/sh
# Pimp my grub helper: the ONLY code that touches system files.
#
#   status                         read-only system probe
#   plan     STAGE NAME GFX        read-only: show exactly what apply would change
#   apply    STAGE NAME GFX        install theme (needs root; fully reversible)
#   rollback                       undo the last apply
#   uninstall                      remove every Pimp my grub change
#
# Safety model
#   * Never edits grub.cfg by hand: it is regenerated with grub-mkconfig into a
#     temp file, checked with grub-script-check, and only then renamed into place
#     (atomic). A failed run leaves the old grub.cfg untouched.
#   * /etc/default/grub changes are limited to one marked block. Conflicting
#     lines are commented out with a "#pimpmygrub# " prefix, never deleted.
#   * Every apply snapshots /etc/default/grub, grub.cfg and the previous theme
#     under /var/lib/pimp-my-grub/backups. The very first state is kept forever in
#     /var/lib/pimp-my-grub/original.
#   * Any error after the first write triggers an automatic restore (trap).
#   * Output is machine readable: STEP/INFO/WARN/CHANGE/DIFF/FATAL/OK lines.
set -eu
umask 022
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH LC_ALL=C

MODE=${1:-}
[ $# -gt 0 ] && shift

STATE_ROOT=${GF_STATE_ROOT:-/var/lib/pimp-my-grub}
DEFAULTS=${GF_DEFAULTS:-/etc/default/grub}
TAG_BEGIN='# >>> pimp-my-grub managed block (do not edit by hand) >>>'
TAG_END='# <<< pimp-my-grub managed block <<<'
MARK='#pimpmygrub# '
MAX_KB=40960
MAX_FILES=600

TMP=""
LOCKDIR=""
OK_DONE=0
OLD_ASIDE=""
UNDO=""   # newline separated list of undo function names, executed in reverse on failure

say()    { printf '%s\n' "$*"; }
step()   { printf 'STEP\t%s\n' "$*"; }
info()   { printf 'INFO\t%s\t%s\n' "$1" "$2"; }
warn()   { printf 'WARN\t%s\n' "$*"; }
change() { printf 'CHANGE\t%s\t%s\t%s\n' "$1" "$2" "$3"; }
fatal()  { printf 'FATAL\t%s\n' "$*"; exit 2; }

cleanup() {
  code=$?
  trap - EXIT INT TERM HUP
  if [ "$code" -ne 0 ] && [ "$OK_DONE" -ne 1 ]; then
    run_undo
  fi
  [ -n "$LOCKDIR" ] && rm -rf -- "$LOCKDIR"
  [ -n "$TMP" ] && rm -rf -- "$TMP"
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# --- undo stack ------------------------------------------------------------
push_undo() { UNDO="$1
$UNDO"; }
run_undo() {
  [ -z "$UNDO" ] && return 0
  printf 'STEP\tSomething failed. Restoring the previous GRUB state...\n'
  echo "$UNDO" | while IFS= read -r fn; do
    [ -n "$fn" ] || continue
    ( set +e; eval "$fn" ) >/dev/null 2>&1 || true
  done
  printf 'RESTORED\tYour previous GRUB configuration was restored.\n'
}

require_root() {
  [ "${GF_ALLOW_NONROOT:-0}" = 1 ] && return 0
  [ "$(id -u)" -eq 0 ] || fatal "Administrator rights are required."
}

# --- detection -------------------------------------------------------------
detect() {
  if [ -n "${GF_GRUB_DIR:-}" ]; then GRUB_DIR=$GF_GRUB_DIR
  elif [ -f /boot/grub/grub.cfg ]; then GRUB_DIR=/boot/grub
  elif [ -f /boot/grub2/grub.cfg ]; then GRUB_DIR=/boot/grub2
  else fatal "No GRUB configuration found at /boot/grub/grub.cfg or /boot/grub2/grub.cfg. This system may use another bootloader (systemd-boot, rEFInd...)."
  fi
  GRUB_CFG=$GRUB_DIR/grub.cfg
  THEME_ROOT=$GRUB_DIR/themes
  [ -f "$GRUB_CFG" ] || fatal "$GRUB_CFG not found."
  [ -f "$DEFAULTS" ] || fatal "$DEFAULTS not found."
  [ -r "$DEFAULTS" ] || fatal "$DEFAULTS is not readable."
  [ ! -e /run/ostree-booted ] || fatal "Immutable (ostree) systems are not supported."
  MKCONFIG=${GF_MKCONFIG:-$(command -v grub-mkconfig || command -v grub2-mkconfig || true)}
  [ -n "$MKCONFIG" ] || fatal "grub-mkconfig was not found."
  SCRIPT_CHECK=${GF_SCRIPT_CHECK:-$(command -v grub-script-check || command -v grub2-script-check || true)}
  [ -n "$SCRIPT_CHECK" ] || fatal "grub-script-check was not found."
}

check_args() {
  STAGE=${1:-}; NAME=${2:-}; GFX=${3:-auto}
  case $NAME in ''|.*|*[!A-Za-z0-9._-]*) fatal "Invalid theme name. Use letters, digits, dot, dash, underscore." ;; esac
  [ ${#NAME} -le 48 ] || fatal "Theme name is too long (max 48)."
  printf '%s' "$GFX" | grep -Eq '^(auto|[0-9]{3,5}x[0-9]{3,5})(,(auto|[0-9]{3,5}x[0-9]{3,5}))*$' \
    || fatal "Invalid graphics mode: $GFX"
  DEST_NAME=pimpmygrub-$NAME
  DEST=$THEME_ROOT/$DEST_NAME
}

getv() { sed -n "s/^$2=//p" "$1" | head -n1; }

# --- staged theme validation ----------------------------------------------
find_allowed() { # $1 = dir ; prints allowed files (relative, NUL separated)
  ( cd "$1" && find . -type f \( -iname '*.txt' -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.tga' -o -iname '*.pf2' \) -print0 )
}

validate_stage() {
  [ -d "$STAGE" ] && [ ! -L "$STAGE" ] || fatal "The prepared theme folder is missing."
  [ -f "$STAGE/theme.txt" ] || fatal "theme.txt is missing from the theme."
  [ "$(wc -c < "$STAGE/theme.txt")" -le 262144 ] || fatal "theme.txt is unreasonably large."
  bad=$(cd "$STAGE" && find . -mindepth 1 \( -type l -o ! \( -type f -o -type d \) \) | head -n1)
  [ -z "$bad" ] || fatal "Theme contains links or special files: $bad"
  bad=$(cd "$STAGE" && find . -type f \( -iname '*.txt' -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.tga' -o -iname '*.pf2' \) -name '*[!A-Za-z0-9._+@ -]*' | head -n1)
  [ -z "$bad" ] || fatal "Unsafe file name in theme: $bad"
  bad=$(cd "$STAGE" && find . -mindepth 1 -type d -name '*[!A-Za-z0-9._+@ -]*' | head -n1)
  [ -z "$bad" ] || fatal "Unsafe folder name in theme: $bad"
  FILES=$(find_allowed "$STAGE" | tr -cd '\0' | wc -c)
  [ "$FILES" -le "$MAX_FILES" ] || fatal "Theme has too many files ($FILES)."
  KB=$(du -sk "$STAGE" | cut -f1)
  [ "$KB" -le "$MAX_KB" ] || fatal "Theme is larger than $((MAX_KB / 1024)) MB. Big themes slow down boot."
  bad=$(cd "$STAGE" && find . -type f -size +16384k | head -n1)
  [ -z "$bad" ] || fatal "A single file is larger than 16 MB: $bad"
  # referenced files: warn only (GRUB degrades gracefully when one is missing)
  awk -F'"' '/^[[:space:]]*(desktop-image|terminal-box|file|center_bitmap|tick_bitmap|[a-z_]*_style|[a-z_]*pixmap_style)[[:space:]]*[:=]/ && NF >= 3 { print $2 }' "$STAGE/theme.txt" |
  while IFS= read -r ref; do
    case $ref in *..*|/*) printf 'FATAL\tUnsafe path in theme.txt: %s\n' "$ref"; exit 3 ;; esac
    IFS=; set -- "$STAGE"/$ref
    [ -e "$1" ] || printf 'WARN\ttheme.txt references a missing file: %s\n' "$ref"
  done || exit 2
}

# --- /etc/default/grub rewrite --------------------------------------------
# $1 output path, $2 theme name ("" = remove everything Pimp my grub added), $3 gfx
build_defaults() {
  awk -v b="$TAG_BEGIN" -v e="$TAG_END" -v m="$MARK" -v unmark="$([ -z "$2" ] && echo 1 || echo 0)" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    skip { next }
    unmark == 1 && index($0, m) == 1 { print substr($0, length(m) + 1); next }
    /^[[:space:]]*(GRUB_THEME|GRUB_GFXMODE)[[:space:]]*=/ { if (unmark == 0) print m $0; else print; next }
    /^[[:space:]]*GRUB_TERMINAL(_OUTPUT)?[[:space:]]*=[[:space:]]*["'"'"']?console["'"'"']?[[:space:]]*(#.*)?$/ { if (unmark == 0) print m $0; else print; next }
    { print }
  ' "$DEFAULTS" > "$1"
  if [ -n "$2" ]; then
    {
      echo "$TAG_BEGIN"
      echo "GRUB_THEME=\"$THEME_ROOT/pimpmygrub-$2/theme.txt\""
      echo "GRUB_GFXMODE=\"$3\""
      echo "$TAG_END"
    } >> "$1"
  fi
  sh -n "$1" 2>/dev/null || fatal "Refusing to write an invalid $DEFAULTS."
}

install_defaults() { # atomic replace keeping owner and mode
  cp -p -- "$DEFAULTS" "$DEFAULTS.pimp-my-grub.tmp"
  cat "$1" > "$DEFAULTS.pimp-my-grub.tmp"
  mv -f -- "$DEFAULTS.pimp-my-grub.tmp" "$DEFAULTS"
}

# --- state ---------------------------------------------------------------
init_state() {
  [ -d "$STATE_ROOT" ] || install -d -m 0755 "$STATE_ROOT"
  install -d -m 0700 "$STATE_ROOT/backups"
  if [ ! -f "$STATE_ROOT/original/default-grub" ]; then
    install -d -m 0700 "$STATE_ROOT/original"
    cp -p -- "$DEFAULTS" "$STATE_ROOT/original/default-grub"
    cp -p -- "$GRUB_CFG" "$STATE_ROOT/original/grub.cfg"
    printf 'GRUB_CFG=%s\nDEFAULTS=%s\n' "$GRUB_CFG" "$DEFAULTS" > "$STATE_ROOT/original/location"
  fi
}

lock() {
  install -d -m 0755 "$STATE_ROOT"
  LOCKDIR="$STATE_ROOT/lock"
  if ! mkdir "$LOCKDIR" 2>/dev/null; then
    old=$(cat "$LOCKDIR/pid" 2>/dev/null || echo 0)
    if [ "$old" -gt 0 ] 2>/dev/null && kill -0 "$old" 2>/dev/null; then
      LOCKDIR=""; fatal "Another Pimp my grub operation is running."
    fi
    rm -rf -- "$LOCKDIR"; mkdir "$LOCKDIR"
  fi
  echo $$ > "$LOCKDIR/pid"
}

# --- regenerate grub.cfg safely ---------------------------------------------
# $1 = expected theme dir name ("" = none expected)
regen_cfg() {
  CFG_NEW="$GRUB_DIR/.grub.cfg.pimp-my-grub.new"
  step "Regenerating the boot menu with grub-mkconfig"
  if ! "$MKCONFIG" -o "$CFG_NEW" >"$TMP/mkconfig.out" 2>&1; then
    rm -f -- "$CFG_NEW"
    tail -n 5 "$TMP/mkconfig.out" | sed 's/^/MKCONFIG\t/'
    fatal "grub-mkconfig failed. Nothing was changed."
  fi
  step "Validating the new boot menu"
  [ -s "$CFG_NEW" ] || { rm -f -- "$CFG_NEW"; fatal "grub-mkconfig produced an empty file."; }
  "$SCRIPT_CHECK" "$CFG_NEW" >"$TMP/check.out" 2>&1 || { rm -f -- "$CFG_NEW"; fatal "grub-script-check rejected the new boot menu."; }
  OLDN=$(grep -c '^[[:space:]]*menuentry ' "$GRUB_CFG" || true)
  NEWN=$(grep -c '^[[:space:]]*menuentry ' "$CFG_NEW" || true)
  if [ "$OLDN" -gt 0 ] && [ "$NEWN" -eq 0 ]; then
    rm -f -- "$CFG_NEW"; fatal "The new boot menu has no entries. Aborting before touching grub.cfg."
  fi
  if [ -n "$1" ] && ! grep -qF "themes/pimpmygrub-$1/theme.txt" "$CFG_NEW"; then
    rm -f -- "$CFG_NEW"
    fatal "Your system configuration overrides GRUB_THEME (check /etc/default/grub.d). The theme would not be shown, so nothing was changed."
  fi
  if [ "$NEWN" -ne "$OLDN" ]; then warn "Menu entries changed from $OLDN to $NEWN (kernels or OS entries were re-detected)."; fi
  step "Activating the new boot menu"
  mv -f -- "$CFG_NEW" "$GRUB_CFG"
  sync
}

# --- undo helpers (executed through eval) ------------------------------------
u_restore_defaults() { cat "$BK/default-grub" > "$DEFAULTS.pimp-my-grub.tmp" && mv -f -- "$DEFAULTS.pimp-my-grub.tmp" "$DEFAULTS"; }
u_restore_cfg() { cp -p -- "$BK/grub.cfg" "$GRUB_DIR/.grub.cfg.restore" && "$SCRIPT_CHECK" "$GRUB_DIR/.grub.cfg.restore" && mv -f -- "$GRUB_DIR/.grub.cfg.restore" "$GRUB_CFG"; }
u_remove_dest() { rm -rf -- "$DEST"; }
u_put_back_old() { rm -rf -- "$DEST"; mv -- "$OLD_ASIDE" "$DEST"; }

# --- commands ---------------------------------------------------------------
cmd_status() {
  detect
  info grub_dir "$GRUB_DIR"
  info defaults "$DEFAULTS"
  info mkconfig "$MKCONFIG"
  info themes_dir "$THEME_ROOT"
  [ -f /sys/firmware/efi/fw_platform_size ] || [ -d /sys/firmware/efi ] && info firmware uefi || info firmware bios
  v=$("$MKCONFIG" --version 2>/dev/null | head -n1 || true); info grub_version "$v"
  info current_theme "$(sed -n 's/^[[:space:]]*GRUB_THEME=//p' "$DEFAULTS" | tail -n1 | tr -d "\"'")"
  if [ -f "$STATE_ROOT/current" ]; then
    info managed_name "$(getv "$STATE_ROOT/current" NAME)"
    info managed_when "$(getv "$STATE_ROOT/current" WHEN)"
  fi
  if [ -f "$STATE_ROOT/last-backup" ]; then info can_rollback yes; fi
  if [ -f "$STATE_ROOT/original/default-grub" ]; then info has_original yes; fi
  if ls /etc/default/grub.d/*.cfg >/dev/null 2>&1; then
    f=$(grep -lE '^[[:space:]]*(GRUB_THEME|GRUB_GFXMODE|GRUB_TERMINAL)' /etc/default/grub.d/*.cfg 2>/dev/null | head -n3 | tr '\n' ' ' || true)
    if [ -n "$f" ]; then warn "These files can override the theme settings: $f"; fi
  fi
  echo OK
}

cmd_plan() {
  detect; check_args "$@"; validate_stage
  TMP=$(mktemp -d)
  build_defaults "$TMP/new" "$NAME" "$GFX"
  CONF=$(grep -c "^$MARK" "$TMP/new" || true)
  verb=create; [ -d "$DEST" ] && verb=replace
  info grub_dir "$GRUB_DIR"
  change "$verb" "$DEST" "Theme files: $(find_allowed "$STAGE" | tr -cd '\0' | wc -c) files, $(du -sk "$STAGE" | cut -f1) KB"
  change modify "$DEFAULTS" "Adds a clearly marked block (GRUB_THEME, GRUB_GFXMODE). Lines it replaces are commented out, not deleted ($CONF)."
  change modify "$GRUB_CFG" "Regenerated by $(basename "$MKCONFIG"), validated with $(basename "$SCRIPT_CHECK"), then swapped in atomically."
  change create "$STATE_ROOT" "Backups of $DEFAULTS and grub.cfg, so every step can be undone."
  if ls /etc/default/grub.d/*.cfg >/dev/null 2>&1; then
    f=$(grep -lE '^[[:space:]]*(GRUB_THEME|GRUB_GFXMODE|GRUB_TERMINAL)' /etc/default/grub.d/*.cfg 2>/dev/null | head -n3 | tr '\n' ' ' || true)
    if [ -n "$f" ]; then warn "These files can override the theme settings: $f"; fi
  fi
  avail=$(df -Pk "$GRUB_DIR" | awk 'NR==2 {print $4}')
  [ "${avail:-0}" -gt $((KB * 2 + 20480)) ] || warn "Free space on the boot partition looks low (${avail:-0} KB)."
  [ "$(find "$STAGE" -name '*.pf2' | wc -l)" -gt 0 ] || warn "The theme has no .pf2 font. GRUB will use its built-in font for labels."
  echo DIFFBEGIN
  diff -u "$DEFAULTS" "$TMP/new" | tail -n +3 || true
  echo DIFFEND
  echo OK
}

stage_into_dest() {
  step "Copying theme files"
  install -d -m 0755 "$THEME_ROOT"
  NEWD="$THEME_ROOT/.$DEST_NAME.new"
  rm -rf -- "$NEWD"; mkdir -p -- "$NEWD"
  # copy whitelisted file types only, from a snapshot we own
  ( cd "$STAGE" && find . -type f \( -iname '*.txt' -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.tga' -o -iname '*.pf2' \) -exec cp --parents -- {} "$NEWD" \; )
  # GRUB only auto-loads fonts that sit next to theme.txt: flatten fonts from subfolders
  ( cd "$NEWD" && find . -mindepth 2 -iname '*.pf2' | while IFS= read -r f; do [ -e "$NEWD/$(basename "$f")" ] || cp -- "$f" "$NEWD/$(basename "$f")"; done )
  chmod -R u=rwX,go=rX "$NEWD"
  [ -f "$NEWD/theme.txt" ] || { rm -rf -- "$NEWD"; fatal "theme.txt was not copied."; }
}

cmd_apply() {
  require_root; detect; check_args "$@"; validate_stage
  lock; TMP=$(mktemp -d); init_state
  STAMP=$(date +%Y%m%d-%H%M%S)
  BK="$STATE_ROOT/backups/$STAMP.$$"
  mkdir -p -- "$BK"; chmod 700 "$BK"

  step "Backing up your current GRUB configuration"
  cp -p -- "$DEFAULTS" "$BK/default-grub"
  cp -p -- "$GRUB_CFG" "$BK/grub.cfg"
  PREV=""
  if [ -f "$STATE_ROOT/current" ]; then cp -p -- "$STATE_ROOT/current" "$BK/state"; PREV=$(getv "$STATE_ROOT/current" NAME); fi
  if [ -n "$PREV" ] && [ -d "$THEME_ROOT/pimpmygrub-$PREV" ]; then cp -a -- "$THEME_ROOT/pimpmygrub-$PREV" "$BK/theme"; fi

  stage_into_dest
  push_undo 'rm -rf -- "$NEWD"'
  OLD_ASIDE=""
  if [ -d "$DEST" ]; then
    OLD_ASIDE="$THEME_ROOT/.$DEST_NAME.old.$$"
    mv -- "$DEST" "$OLD_ASIDE"
    push_undo 'u_put_back_old'
  else
    push_undo 'u_remove_dest'
  fi
  mv -- "$NEWD" "$DEST"

  step "Updating $DEFAULTS (marked block only)"
  build_defaults "$TMP/new" "$NAME" "$GFX"
  push_undo 'u_restore_defaults'
  install_defaults "$TMP/new"

  push_undo 'u_restore_cfg'
  regen_cfg "$NAME"

  step "Saving state"
  printf 'NAME=%s\nGFX=%s\nDEST=%s\nWHEN=%s\n' "$NAME" "$GFX" "$DEST" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_ROOT/current"
  echo "$BK" > "$STATE_ROOT/last-backup"
  OK_DONE=1
  if [ -n "$OLD_ASIDE" ]; then rm -rf -- "$OLD_ASIDE"; fi
  # prune: keep the five newest backups
  ls -1dt "$STATE_ROOT"/backups/*/ 2>/dev/null | tail -n +6 | while IFS= read -r d; do
    [ "$d" = "$BK/" ] || rm -rf -- "$d"
  done
  echo "OK"
}

# revert helper shared by rollback/uninstall: $1 = target name or "", $2 gfx, $3 theme dir to restore or ""
revert_to() {
  TARGET=$1; TGFX=$2; TDIR=$3
  BK="$TMP/pre"; mkdir -p -- "$BK"
  cp -p -- "$DEFAULTS" "$BK/default-grub"; cp -p -- "$GRUB_CFG" "$BK/grub.cfg"
  if [ -n "$TARGET" ] && [ -n "$TDIR" ] && [ -d "$TDIR" ]; then
    step "Restoring previous theme files"
    DEST="$THEME_ROOT/pimpmygrub-$TARGET"
    if [ -d "$DEST" ]; then OLD_ASIDE="$THEME_ROOT/.old.$$"; mv -- "$DEST" "$OLD_ASIDE"; push_undo 'u_put_back_old'
    else push_undo 'u_remove_dest'; fi
    cp -a -- "$TDIR" "$DEST"
  elif [ -n "$TARGET" ]; then
    TARGET=""
  fi
  step "Updating $DEFAULTS"
  build_defaults "$TMP/new" "$TARGET" "$TGFX"
  push_undo 'u_restore_defaults'
  install_defaults "$TMP/new"
  push_undo 'u_restore_cfg'
  regen_cfg "$TARGET"
}

cmd_rollback() {
  require_root; detect; lock; TMP=$(mktemp -d)
  [ -f "$STATE_ROOT/last-backup" ] || fatal "There is nothing to roll back."
  B=$(cat "$STATE_ROOT/last-backup")
  case $B in "$STATE_ROOT"/backups/*) ;; *) fatal "The rollback pointer is invalid." ;; esac
  [ -d "$B" ] || fatal "The backup folder is gone."
  CUR=""
  if [ -f "$STATE_ROOT/current" ]; then CUR=$(getv "$STATE_ROOT/current" NAME); fi
  if [ -f "$B/state" ]; then
    PN=$(getv "$B/state" NAME); PG=$(getv "$B/state" GFX)
    revert_to "$PN" "$PG" "$B/theme"
    NEWCUR=$PN
  else
    revert_to "" "" ""
    NEWCUR=""
  fi
  if [ -n "$CUR" ] && [ "$CUR" != "$NEWCUR" ]; then rm -rf -- "$THEME_ROOT/pimpmygrub-$CUR"; fi
  if [ -n "$OLD_ASIDE" ]; then rm -rf -- "$OLD_ASIDE"; fi
  if [ -n "$NEWCUR" ]; then cp -p -- "$B/state" "$STATE_ROOT/current"; else rm -f -- "$STATE_ROOT/current"; fi
  rm -f -- "$STATE_ROOT/last-backup"
  OK_DONE=1
  echo OK
}

cmd_uninstall() {
  require_root; detect; lock; TMP=$(mktemp -d)
  revert_to "" "" ""
  for d in "$THEME_ROOT"/pimpmygrub-*; do
    if [ -d "$d" ]; then rm -rf -- "$d"; fi
  done
  rm -f -- "$STATE_ROOT/current" "$STATE_ROOT/last-backup"
  rm -rf -- "$STATE_ROOT/backups"
  OK_DONE=1
  info kept "$STATE_ROOT/original (first-ever copy of your GRUB files)"
  echo OK
}

case $MODE in
  status)    cmd_status ;;
  plan)      cmd_plan "$@" ;;
  apply)     cmd_apply "$@" ;;
  rollback)  cmd_rollback ;;
  uninstall) cmd_uninstall ;;
  *) echo "usage: pimp-my-grub-helper status|plan|apply|rollback|uninstall" >&2; exit 64 ;;
esac
