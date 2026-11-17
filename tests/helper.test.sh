#!/bin/sh
# Exercises pimp-my-grub-helper.sh against a fake GRUB tree (no root, nothing real is touched).
set -eu
H="$(cd "$(dirname "$0")/.." && pwd)/helper/pimp-my-grub-helper.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GF_ALLOW_NONROOT=1 GF_STATE_ROOT="$T/var" GF_DEFAULTS="$T/default-grub" GF_GRUB_DIR="$T/boot/grub"
export GF_MKCONFIG="$T/mkconfig" GF_SCRIPT_CHECK="$T/check"
mkdir -p "$T/boot/grub" "$T/stage/fonts"
cat > "$T/default-grub" <<'D'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_GFXMODE=640x480
GRUB_TERMINAL=console
GRUB_CMDLINE_LINUX="quiet"
D
echo 'menuentry "Linux" {}' > "$T/boot/grub/grub.cfg"
# fake grub-mkconfig: reads the defaults file, emits a menu with the theme line
cat > "$T/mkconfig" <<M
#!/bin/sh
[ "\${FAIL_MKCONFIG:-0}" = 1 ] && exit 1
. "$T/default-grub"
[ "\${NO_THEME:-0}" = 1 ] && GRUB_THEME=""
printf 'set theme=%s\n' "\$GRUB_THEME" > "\$2"
echo 'menuentry "Linux" {' >> "\$2"; echo '}' >> "\$2"
M
printf '#!/bin/sh\n[ -s "$1" ]\n' > "$T/check"; chmod +x "$T/mkconfig" "$T/check"
cat > "$T/stage/theme.txt" <<'X'
desktop-image: "bg.png"
+ label { left = 1 top = 2 text = "hi" }
X
printf 'PNG' > "$T/stage/bg.png"; printf 'PF' > "$T/stage/fonts/x.pf2"
ok() { printf 'ok - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1"; exit 1; }

sh "$H" status >/dev/null || bad status
sh "$H" plan "$T/stage" demo 1920x1080 | grep -q '^DIFFBEGIN' || bad plan
grep -q 'GRUB_THEME' "$T/default-grub" && bad "plan must not modify"; ok "plan is read-only"

sh "$H" apply "$T/stage" demo 1920x1080 > "$T/out" || { cat "$T/out"; bad apply; }; tail -1 "$T/out" | grep -q "^OK" || { cat "$T/out"; bad apply; }
grep -q 'pimp-my-grub managed block' "$T/default-grub" || bad block
grep -q '^#pimpmygrub# GRUB_TERMINAL=console' "$T/default-grub" || bad "conflict commented"
grep -q '^#pimpmygrub# GRUB_GFXMODE=640x480' "$T/default-grub" || bad "gfx commented"
[ -f "$T/boot/grub/themes/pimpmygrub-demo/x.pf2" ] || bad "font flattened"
grep -q 'themes/pimpmygrub-demo/theme.txt' "$T/boot/grub/grub.cfg" || bad cfg
ok "apply"

# second theme, then rollback to the first
sh "$H" apply "$T/stage" two auto | tail -1 | grep -q '^OK' || bad apply2
[ -d "$T/boot/grub/themes/pimpmygrub-two" ] || bad two
sh "$H" rollback | tail -1 | grep -q '^OK' || bad rollback
[ -d "$T/boot/grub/themes/pimpmygrub-demo" ] && [ ! -d "$T/boot/grub/themes/pimpmygrub-two" ] || bad "rollback dirs"
grep -q 'pimpmygrub-demo' "$T/default-grub" || bad "rollback block"
ok "rollback to previous theme"

# failure injection: mkconfig dies after defaults were written -> everything restored
cp "$T/default-grub" "$T/before"; cp "$T/boot/grub/grub.cfg" "$T/before.cfg"
if FAIL_MKCONFIG=1 sh "$H" apply "$T/stage" three auto >/dev/null; then bad "should fail"; fi
cmp "$T/default-grub" "$T/before" && cmp "$T/boot/grub/grub.cfg" "$T/before.cfg" || bad "restore after failure"
[ ! -d "$T/boot/grub/themes/pimpmygrub-three" ] || bad "leftover dir"
ok "failed apply restores state"

# override detected: cfg lacks our theme -> refused and restored
if NO_THEME=1 sh "$H" apply "$T/stage" four auto >/dev/null; then bad "override should fail"; fi
cmp "$T/default-grub" "$T/before" || bad "restore after override"
ok "theme override refused"

# hostile stage: symlink and bad name
ln -s /etc/passwd "$T/stage/evil.png"
if sh "$H" plan "$T/stage" demo auto | grep -q '^OK'; then bad "symlink accepted"; fi
rm "$T/stage/evil.png"
if sh "$H" plan "$T/stage" '../x' auto | grep -q '^OK'; then bad "bad name accepted"; fi
ok "hostile input rejected"

# uninstall returns defaults to the original text
sh "$H" uninstall | tail -1 | grep -q '^OK' || bad uninstall
cmp "$T/default-grub" "$T/var/original/default-grub" || bad "uninstall != original"
[ ! -d "$T/boot/grub/themes/pimpmygrub-demo" ] || bad "theme left"
ok "uninstall restores original defaults"

# ------------------------------------------------------------------ settings (timeout, default entry, kernel options ...)
S=$T/set; mkdir -p "$S"
cat > "$T/default-grub" <<'D'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
D
cp "$T/default-grub" "$T/orig-settings"
printf 'GRUB_TIMEOUT=2\nGRUB_DEFAULT=saved\nGRUB_SAVEDEFAULT=true\n' > "$S/settings.conf"
sh "$H" cplan "$S" | grep -q '^DIFFBEGIN' || bad "cplan"
cmp -s "$T/default-grub" "$T/orig-settings" || bad "cplan must not modify"; ok "settings plan is read-only"

sh "$H" capply "$S" | tail -1 | grep -q '^OK' || bad capply
grep -q 'pimp-my-grub settings block' "$T/default-grub" || bad "settings block"
grep -q '^GRUB_TIMEOUT="2"' "$T/default-grub" || bad "timeout written"
grep -q '^GRUB_TIMEOUT=5' "$T/default-grub" || bad "original line must stay untouched"
ok "settings applied in a marked block, original lines kept"

# a second change keeps the first (merge), and an empty value removes a setting with `unset`
printf 'GRUB_TIMEOUT_STYLE=hidden\nGRUB_SAVEDEFAULT=\n' > "$S/settings.conf"
sh "$H" capply "$S" | tail -1 | grep -q '^OK' || bad capply2
grep -q '^GRUB_TIMEOUT="2"' "$T/default-grub" || bad "first change lost in the merge"
grep -q '^GRUB_TIMEOUT_STYLE="hidden"' "$T/default-grub" || bad "second change missing"
grep -q '^unset GRUB_SAVEDEFAULT' "$T/default-grub" || bad "unset"
[ "$(grep -c 'settings block (do not' "$T/default-grub")" = 1 ] || bad "exactly one block"
ok "settings merge across changes"

# undo goes back one change at a time and restores the exact files
sh "$H" rollback | tail -1 | grep -q '^OK' || bad rollback-settings
grep -q 'TIMEOUT_STYLE' "$T/default-grub" && bad "second change not undone"
grep -q '^GRUB_TIMEOUT="2"' "$T/default-grub" || bad "first change must remain"
sh "$H" rollback | tail -1 | grep -q '^OK' || bad rollback-settings2
cmp -s "$T/default-grub" "$T/orig-settings" || bad "second rollback must restore the original file"
ok "settings rollback restores the exact previous file, one step at a time"

# hostile or invalid settings are refused and nothing changes
for bad_line in 'GRUB_TIMEOUT=abc' 'GRUB_TIMEOUT=99999' 'GRUB_CMDLINE_LINUX="x"; reboot' 'GRUB_CMDLINE_LINUX=a$(id)b' 'GRUB_CMDLINE_LINUX=a`id`' 'GRUB_THEME=/evil' 'GRUB_TIMEOUT_STYLE=evil' 'PATH=/tmp' 'GRUB_DEFAULT=0;reboot'; do
  printf '%s\n' "$bad_line" > "$S/settings.conf"
  if sh "$H" cplan "$S" 2>&1 | grep -q '^OK'; then bad "accepted: $bad_line"; fi
  if sh "$H" capply "$S" 2>&1 | tail -1 | grep -q '^OK'; then bad "applied: $bad_line"; fi
done
cmp -s "$T/default-grub" "$T/orig-settings" || bad "refused settings changed the file"
ln -sf /etc/passwd "$S/settings.conf"; if sh "$H" cplan "$S" 2>&1 | grep -q '^OK'; then bad "symlinked settings.conf accepted"; fi; rm -f "$S/settings.conf"
ok "hostile settings rejected"

# failure while regenerating the menu: everything is put back
printf 'GRUB_TIMEOUT=1\n' > "$S/settings.conf"
FAIL_MKCONFIG=1 sh "$H" capply "$S" >/dev/null 2>&1 && bad "failing mkconfig must fail"
cmp -s "$T/default-grub" "$T/orig-settings" || bad "failed settings apply restores state"; ok "failed settings apply restores state"

# settings and a theme live side by side; theme rollback keeps the settings; uninstall removes both
printf 'GRUB_TIMEOUT=3\n' > "$S/settings.conf"; sh "$H" capply "$S" | tail -1 | grep -q '^OK' || bad capply3
sh "$H" apply "$T/stage" demo 1920x1080 | tail -1 | grep -q '^OK' || bad "theme after settings"
grep -q '^GRUB_TIMEOUT="3"' "$T/default-grub" || bad "settings survive a theme apply"
grep -q 'pimp-my-grub managed block' "$T/default-grub" || bad "theme block"
sh "$H" uninstall | tail -1 | grep -q '^OK' || bad uninstall2
grep -q 'pimp-my-grub' "$T/default-grub" && bad "uninstall must remove both blocks"
cmp -s "$T/default-grub" "$T/orig-settings" || bad "uninstall != original after settings and theme"
ok "settings and theme coexist; uninstall removes both"
