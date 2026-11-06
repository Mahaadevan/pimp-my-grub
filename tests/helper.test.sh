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
