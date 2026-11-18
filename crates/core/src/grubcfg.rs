//! The GRUB settings that live in /etc/default/grub (timeout, default entry, kernel options ...): reading them from this
//! computer, describing them for the UI (with help text and warnings), and turning the user's edits into a validated list of
//! `KEY=VALUE` changes for the privileged helper. Nothing here writes to the system.
use indexmap::IndexMap;
use serde::Serialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

pub fn defaults_path() -> PathBuf { std::env::var_os("GF_DEFAULTS").map(PathBuf::from).unwrap_or_else(|| "/etc/default/grub".into()) }
fn cfg_candidates() -> Vec<PathBuf> {
    if let Some(p) = std::env::var_os("GF_GRUB_CFG") { return vec![p.into()]; }
    ["/boot/grub/grub.cfg", "/boot/grub2/grub.cfg", "/boot/efi/EFI/fedora/grub.cfg", "/boot/efi/EFI/ubuntu/grub.cfg"].iter().map(PathBuf::from).collect()
}

/// Parse `KEY=value` lines of the shell file (quotes removed, comments ignored).
pub fn parse_defaults(text: &str) -> IndexMap<String, String> {
    let mut m = IndexMap::new();
    for raw in text.lines() {
        let line = raw.trim().trim_start_matches("export ").trim();
        if line.is_empty() || line.starts_with('#') { continue; }
        let Some((k, v)) = line.split_once('=') else { continue };
        let k = k.trim();
        if !k.starts_with("GRUB_") || !k.chars().all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_') { continue; }
        let v = v.trim();
        let val = if let Some(r) = v.strip_prefix('"') { r.rsplit_once('"').map(|x| x.0).unwrap_or(r).to_string() }
            else if let Some(r) = v.strip_prefix('\'') { r.split('\'').next().unwrap_or("").to_string() }
            else { v.split(" #").next().unwrap_or("").trim().to_string() };
        m.insert(k.to_string(), val);
    }
    m
}

#[derive(Clone, Serialize, Debug, PartialEq)]
pub struct HostEntry { pub title: String, pub id: String, pub class: String, pub submenu: bool, pub depth: u32 }

fn quoted_title(s: &str) -> Option<String> {
    let s = s.trim_start();
    let q = s.chars().next().filter(|c| *c == '\'' || *c == '"')?;
    let rest = &s[1..];
    Some(rest[..rest.find(q)?].to_string())
}

/// Boot entries from a generated grub.cfg: `menuentry` / `submenu`, with GRUB's own numbering ("0", "1>2").
pub fn parse_entries(cfg: &str) -> Vec<HostEntry> {
    let (mut out, mut depth, mut top, mut sub, mut in_sub): (Vec<HostEntry>, i32, u32, u32, bool) = (vec![], 0, 0, 0, false);
    for raw in cfg.lines() {
        let l = raw.trim();
        let is_sub = l.starts_with("submenu ");
        if (l.starts_with("menuentry ") || is_sub) && depth <= 1 {
            if let Some(title) = quoted_title(&l[l.find(' ').unwrap_or(0)..]) {
                let class = l.split("--class").nth(1).map(|c| c.trim().split_whitespace().next().unwrap_or("").trim_matches('\'').to_string()).filter(|c| !c.is_empty()).unwrap_or_else(|| "gnu-linux".into());
                if depth == 0 { in_sub = is_sub; sub = 0; out.push(HostEntry { title, id: top.to_string(), class, submenu: is_sub, depth: 0 }); if !is_sub { top += 1; } else { sub = 0; } }
                else if in_sub { out.push(HostEntry { title, id: format!("{}>{}", top, sub), class, submenu: false, depth: 1 }); sub += 1; }
            }
        }
        let (o, c) = (l.matches('{').count() as i32, l.matches('}').count() as i32);
        depth += o - c;
        if depth <= 0 { depth = 0; if in_sub && c > 0 { top += 1; in_sub = false; } }
    }
    out
}

pub struct Host { pub defaults: IndexMap<String, String>, pub entries: Vec<HostEntry>, pub defaults_file: String, pub readable: bool, pub cfg_file: String, pub saved_entry: String, pub os_prober: bool }

pub fn read_host() -> Host { read_host_with(None, None) }

/// The same, from files the caller names. The app uses this for the copies the privileged helper makes when the user's
/// own account is not allowed to read `/etc/default/grub` or `grub.cfg` (root-owned on most systems).
pub fn read_host_with(defaults: Option<&Path>, cfg: Option<&Path>) -> Host {
    let dp = defaults.map(Path::to_path_buf).unwrap_or_else(defaults_path);
    let text = std::fs::read_to_string(&dp);
    let readable = text.is_ok();
    let defaults = parse_defaults(&text.unwrap_or_default());
    let (mut entries, mut cfg_file) = (vec![], String::new());
    let candidates = match cfg { Some(c) => vec![c.to_path_buf()], None => cfg_candidates() };
    for c in candidates { if let Ok(t) = std::fs::read_to_string(&c) { entries = parse_entries(&t); cfg_file = c.to_string_lossy().into(); if !entries.is_empty() { break; } } }
    let mut saved = String::new();
    for g in ["/boot/grub/grubenv", "/boot/grub2/grubenv"] { if let Ok(t) = std::fs::read_to_string(g) { if let Some(v) = t.lines().find_map(|l| l.strip_prefix("saved_entry=")) { saved = v.to_string(); break; } } }
    let os_prober = ["/usr/bin/os-prober", "/usr/sbin/os-prober", "/bin/os-prober"].iter().any(|p| Path::new(p).exists());
    Host { defaults, entries, defaults_file: dp.to_string_lossy().into(), readable, cfg_file, saved_entry: saved, os_prober }
}

struct Opt { id: &'static str, group: &'static str, label: &'static str, kind: &'static str, tip: &'static str, warn: &'static str }
const OPTS: &[Opt] = &[
    Opt { id: "timeout", group: "Boot menu", label: "Wait before booting (seconds)", kind: "number",
          tip: "How long the menu waits before it boots the default entry. 0 boots immediately, -1 waits until you choose. (GRUB_TIMEOUT)",
          warn: "0 (or a hidden menu) makes it hard to reach the menu or recovery entries. Hold Shift or press Esc while starting if you need it." },
    Opt { id: "timeout_style", group: "Boot menu", label: "Menu style", kind: "select",
          tip: "menu: always show the menu. countdown: hide the menu but show the countdown. hidden: show nothing until you press a key. (GRUB_TIMEOUT_STYLE)",
          warn: "\"hidden\" with a short timeout can lock you out of the menu on a system you cannot easily recover." },
    Opt { id: "remember_last", group: "Boot menu", label: "Boot the previously selected entry", kind: "switch",
          tip: "Remember the entry you booted last time and start it by default (GRUB_DEFAULT=saved and GRUB_SAVEDEFAULT=true). Good for dual boot.",
          warn: "Needs a writable boot partition (GRUB writes the choice to grubenv). It does not work on some Btrfs/RAID/LVM /boot setups." },
    Opt { id: "default_entry", group: "Boot menu", label: "Default entry", kind: "select",
          tip: "The entry that boots when you do nothing. Ignored while \"Boot the previously selected entry\" is on. (GRUB_DEFAULT)",
          warn: "Entries are counted by position. After a kernel update the numbers can point to a different entry." },
    Opt { id: "os_prober", group: "Boot menu", label: "Detect other operating systems", kind: "switch",
          tip: "Look for Windows and other Linux systems and add them to the menu (os-prober). Newer GRUB versions turn this off by default. (GRUB_DISABLE_OS_PROBER)",
          warn: "Turning it off removes Windows and other systems from the menu the next time the menu is generated. They still boot from the firmware menu." },
    Opt { id: "submenu", group: "Boot menu", label: "Group older kernels in \"Advanced options\"", kind: "switch",
          tip: "Keep the main menu short by putting every other kernel inside an Advanced options submenu. (GRUB_DISABLE_SUBMENU)", warn: "" },
    Opt { id: "recovery", group: "Boot menu", label: "Show recovery-mode entries", kind: "switch",
          tip: "Add a \"(recovery mode)\" entry for each kernel. (GRUB_DISABLE_RECOVERY)",
          warn: "Recovery entries are your safety net when something stops booting. Think twice before removing them." },
    Opt { id: "quiet", group: "Kernel", label: "Quiet boot (hide kernel messages)", kind: "switch",
          tip: "Adds \"quiet\" to the kernel options so boot messages are hidden. (GRUB_CMDLINE_LINUX_DEFAULT)", warn: "" },
    Opt { id: "splash", group: "Kernel", label: "Splash screen", kind: "switch",
          tip: "Adds \"splash\" so the distribution's graphical boot screen is shown. (GRUB_CMDLINE_LINUX_DEFAULT)", warn: "" },
    Opt { id: "cmdline_default", group: "Kernel", label: "Kernel options (normal boot)", kind: "text",
          tip: "Extra options passed to the kernel on a normal boot, for example \"quiet splash nomodeset\". (GRUB_CMDLINE_LINUX_DEFAULT)",
          warn: "Wrong kernel options can stop the system from booting. Change them only if you know what they do." },
    Opt { id: "cmdline", group: "Kernel", label: "Kernel options (all boots)", kind: "text",
          tip: "Options passed to the kernel on every boot, including recovery mode. (GRUB_CMDLINE_LINUX)",
          warn: "These apply to recovery mode too. A wrong value (for example a root= or resume= setting) can make every entry fail to boot." },
    Opt { id: "distributor", group: "Appearance", label: "Name shown in the menu", kind: "text",
          tip: "The distribution name shown in front of the entries, for example \"Ubuntu\". (GRUB_DISTRIBUTOR)", warn: "" },
    Opt { id: "gfxpayload", group: "Appearance", label: "Kernel video mode", kind: "select",
          tip: "keep: keep the menu's resolution while the kernel starts (smoother). text: switch to text mode first. (GRUB_GFXPAYLOAD_LINUX)",
          warn: "\"keep\" can give a black screen on some graphics cards. If that happens choose \"text\"." },
    Opt { id: "recordfail", group: "Advanced", label: "Wait after a failed boot (seconds)", kind: "number",
          tip: "After a boot that did not finish, the menu stays visible this long (Ubuntu/Debian). (GRUB_RECORDFAIL_TIMEOUT)", warn: "" },
];

fn d<'a>(m: &'a IndexMap<String, String>, k: &str) -> &'a str { m.get(k).map(|s| s.as_str()).unwrap_or("") }
fn has_token(s: &str, t: &str) -> bool { s.split_whitespace().any(|x| x == t) }
fn set_token(s: &str, t: &str, on: bool) -> String {
    let mut v: Vec<&str> = s.split_whitespace().filter(|x| *x != t).collect();
    if on { v.push(t); }
    v.join(" ")
}

/// Current value of an option, as the UI shows it ("true"/"false" for switches).
pub fn current(id: &str, m: &IndexMap<String, String>) -> String {
    let tf = |b: bool| if b { "true" } else { "false" }.to_string();
    match id {
        "timeout" => { let v = d(m, "GRUB_TIMEOUT"); if v.is_empty() { "5".into() } else { v.into() } }
        "timeout_style" => { let v = d(m, "GRUB_TIMEOUT_STYLE"); if v.is_empty() { "menu".into() } else { v.into() } }
        "remember_last" => tf(d(m, "GRUB_DEFAULT") == "saved" && d(m, "GRUB_SAVEDEFAULT") == "true"),
        "default_entry" => { let v = d(m, "GRUB_DEFAULT"); if v.is_empty() || v == "saved" { "0".into() } else { v.into() } }
        "os_prober" => tf(d(m, "GRUB_DISABLE_OS_PROBER") == "false"),
        "submenu" => tf(!matches!(d(m, "GRUB_DISABLE_SUBMENU"), "y" | "true")),
        "recovery" => tf(d(m, "GRUB_DISABLE_RECOVERY") != "true"),
        "quiet" => tf(has_token(d(m, "GRUB_CMDLINE_LINUX_DEFAULT"), "quiet")),
        "splash" => tf(has_token(d(m, "GRUB_CMDLINE_LINUX_DEFAULT"), "splash")),
        "cmdline_default" => d(m, "GRUB_CMDLINE_LINUX_DEFAULT").into(),
        "cmdline" => d(m, "GRUB_CMDLINE_LINUX").into(),
        "distributor" => d(m, "GRUB_DISTRIBUTOR").into(),
        "gfxpayload" => { let v = d(m, "GRUB_GFXPAYLOAD_LINUX"); if v.is_empty() { "keep".into() } else { v.into() } }
        "recordfail" => { let v = d(m, "GRUB_RECORDFAIL_TIMEOUT"); if v.is_empty() { "30".into() } else { v.into() } }
        _ => String::new(),
    }
}

/// Everything the settings page needs: the options with their current values, plus facts about this computer.
pub fn options_json(h: &Host) -> Value {
    let entries: Vec<Value> = h.entries.iter().filter(|e| e.depth == 0).map(|e| json!({"v": e.id, "l": format!("{}. {}", e.id, e.title)})).collect();
    let opts: Vec<Value> = OPTS.iter().map(|o| {
        let options = match o.id {
            "timeout_style" => json!([{"v": "menu", "l": "menu (always shown)"}, {"v": "countdown", "l": "countdown"}, {"v": "hidden", "l": "hidden"}]),
            "default_entry" => Value::Array(if entries.is_empty() { (0..6).map(|i| json!({"v": i.to_string(), "l": format!("{i}. (entry {})", i + 1)})).collect() } else { entries.clone() }),
            "gfxpayload" => json!([{"v": "keep", "l": "keep (smooth)"}, {"v": "text", "l": "text (safest)"}]),
            _ => json!([]),
        };
        json!({"id": o.id, "group": o.group, "label": o.label, "kind": o.kind, "tip": o.tip, "warn": o.warn, "value": current(o.id, &h.defaults), "options": options})
    }).collect();
    json!({"options": opts, "entries": h.entries, "file": h.defaults_file, "readable": h.readable, "cfg": h.cfg_file, "saved_entry": h.saved_entry, "os_prober_installed": h.os_prober})
}

fn safe_text(s: &str) -> bool { s.chars().all(|c| c.is_ascii_alphanumeric() || " _.,:;=/@+%-<>()".contains(c)) && s.len() <= 400 }

/// Turn the user's edits (option id -> new value) into the minimal list of GRUB_* assignments. "" means "remove the line".
pub fn to_changes(m: &IndexMap<String, String>, edits: &HashMap<String, String>) -> Result<Vec<(String, String)>, String> {
    let mut want: IndexMap<&str, String> = IndexMap::new();
    let is = |id: &str| edits.contains_key(id);
    let ev = |id: &str| edits.get(id).cloned().unwrap_or_else(|| current(id, m));
    let boolv = |s: &str| matches!(s, "true" | "false").then(|| s == "true");
    for id in edits.keys() { if !OPTS.iter().any(|o| o.id == id) { return Err(format!("unknown setting: {id}")); } }
    if is("timeout") { let v = ev("timeout"); if !(v.parse::<i32>().map(|n| (-1..=3600).contains(&n)).unwrap_or(false)) { return Err("The wait must be a whole number from -1 to 3600.".into()); } want.insert("GRUB_TIMEOUT", v); }
    if is("timeout_style") { let v = ev("timeout_style"); if !["menu", "countdown", "hidden"].contains(&v.as_str()) { return Err("Unknown menu style.".into()); } want.insert("GRUB_TIMEOUT_STYLE", v); }
    if is("remember_last") || is("default_entry") {
        let remember = boolv(&ev("remember_last")).ok_or("remember_last must be true or false")?;
        if remember { want.insert("GRUB_DEFAULT", "saved".into()); want.insert("GRUB_SAVEDEFAULT", "true".into()); }
        else {
            let e = ev("default_entry");
            if e.is_empty() || e.len() > 40 || !e.chars().all(|c| c.is_ascii_digit() || c == '>') { return Err("The default entry must be a number such as 0 or 1>2.".into()); }
            want.insert("GRUB_DEFAULT", e); want.insert("GRUB_SAVEDEFAULT", String::new());
        }
    }
    if is("os_prober") { want.insert("GRUB_DISABLE_OS_PROBER", if boolv(&ev("os_prober")).ok_or("bad value")? { "false" } else { "true" }.into()); }
    if is("submenu") { want.insert("GRUB_DISABLE_SUBMENU", if boolv(&ev("submenu")).ok_or("bad value")? { String::new() } else { "y".into() }); }
    if is("recovery") { want.insert("GRUB_DISABLE_RECOVERY", if boolv(&ev("recovery")).ok_or("bad value")? { String::new() } else { "true".into() }); }
    if is("cmdline_default") || is("quiet") || is("splash") {
        let mut s = if is("cmdline_default") { ev("cmdline_default") } else { current("cmdline_default", m) };
        if !safe_text(&s) { return Err("The kernel options contain characters that are not allowed (quotes, $, backslash, backtick).".into()); }
        if is("quiet") { s = set_token(&s, "quiet", boolv(&ev("quiet")).ok_or("bad value")?); }
        if is("splash") { s = set_token(&s, "splash", boolv(&ev("splash")).ok_or("bad value")?); }
        want.insert("GRUB_CMDLINE_LINUX_DEFAULT", s);
    }
    if is("cmdline") { let v = ev("cmdline"); if !safe_text(&v) { return Err("The kernel options contain characters that are not allowed (quotes, $, backslash, backtick).".into()); } want.insert("GRUB_CMDLINE_LINUX", v); }
    if is("distributor") { let v = ev("distributor"); if !safe_text(&v) { return Err("The name contains characters that are not allowed.".into()); } want.insert("GRUB_DISTRIBUTOR", v); }
    if is("gfxpayload") { let v = ev("gfxpayload"); if !["keep", "text"].contains(&v.as_str()) { return Err("Unknown video mode.".into()); } want.insert("GRUB_GFXPAYLOAD_LINUX", v); }
    if is("recordfail") { let v = ev("recordfail"); if !(v.parse::<u32>().map(|n| n <= 3600).unwrap_or(false)) { return Err("The failed-boot wait must be a whole number from 0 to 3600.".into()); } want.insert("GRUB_RECORDFAIL_TIMEOUT", v); }
    // keep only what really differs from the file now
    Ok(want.into_iter().filter(|(k, v)| d(m, k) != v.as_str()).map(|(k, v)| (k.to_string(), v)).collect())
}

/// The file the helper reads: one `KEY=VALUE` per line.
pub fn conf_text(changes: &[(String, String)]) -> String { changes.iter().map(|(k, v)| format!("{k}={v}\n")).collect() }

#[cfg(test)]
mod tests {
    use super::*;
    const SAMPLE: &str = "# comment\nGRUB_DEFAULT=0\nGRUB_TIMEOUT_STYLE=hidden\nGRUB_TIMEOUT=\"10\"\nGRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`\nGRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash\"\nGRUB_CMDLINE_LINUX=''\n#GRUB_DISABLE_OS_PROBER=true\n";
    #[test] fn parses_shell_values() {
        let m = parse_defaults(SAMPLE);
        assert_eq!(m["GRUB_TIMEOUT"], "10"); assert_eq!(m["GRUB_TIMEOUT_STYLE"], "hidden"); assert_eq!(m["GRUB_CMDLINE_LINUX_DEFAULT"], "quiet splash");
        assert!(!m.contains_key("GRUB_DISABLE_OS_PROBER"));
        assert_eq!(current("quiet", &m), "true"); assert_eq!(current("os_prober", &m), "false"); assert_eq!(current("timeout", &m), "10");
    }
    #[test] fn finds_entries_and_submenus() {
        let cfg = "menuentry 'Ubuntu' --class ubuntu --class gnu-linux $menuentry_id_option 'gnulinux-simple' {\n  insmod ext2\n}\nsubmenu 'Advanced options for Ubuntu' $menuentry_id_option 'gnulinux-advanced' {\n\tmenuentry 'Ubuntu, with Linux 6.8' --class ubuntu {\n\t\tinsmod ext2\n\t}\n\tmenuentry 'Ubuntu, with Linux 6.5' --class ubuntu {\n\t}\n}\nmenuentry 'Windows Boot Manager (on /dev/sda1)' --class windows {\n}\n";
        let e = parse_entries(cfg);
        let ids: Vec<(&str, &str)> = e.iter().map(|x| (x.id.as_str(), x.title.as_str())).collect();
        assert_eq!(ids, vec![("0", "Ubuntu"), ("1", "Advanced options for Ubuntu"), ("1>0", "Ubuntu, with Linux 6.8"), ("1>1", "Ubuntu, with Linux 6.5"), ("2", "Windows Boot Manager (on /dev/sda1)")]);
        assert_eq!(e[0].class, "ubuntu"); assert_eq!(e[4].class, "windows");
    }
    #[test] fn remember_last_and_toggles_become_grub_keys() {
        let m = parse_defaults(SAMPLE);
        let mut ed = HashMap::new(); ed.insert("remember_last".into(), "true".into()); ed.insert("quiet".into(), "false".into()); ed.insert("os_prober".into(), "true".into());
        let c: HashMap<_, _> = to_changes(&m, &ed).unwrap().into_iter().collect();
        assert_eq!(c["GRUB_DEFAULT"], "saved"); assert_eq!(c["GRUB_SAVEDEFAULT"], "true"); assert_eq!(c["GRUB_CMDLINE_LINUX_DEFAULT"], "splash"); assert_eq!(c["GRUB_DISABLE_OS_PROBER"], "false");
        assert!(!c.contains_key("GRUB_TIMEOUT"));
    }
    #[test] fn unchanged_values_produce_no_changes_and_bad_input_is_refused() {
        let m = parse_defaults(SAMPLE);
        let mut ed = HashMap::new(); ed.insert("timeout".into(), "10".into());
        assert!(to_changes(&m, &ed).unwrap().is_empty());
        for (id, v) in [("timeout", "abc"), ("timeout", "99999"), ("cmdline", "a\"; rm -rf /"), ("cmdline_default", "$(reboot)"), ("timeout_style", "evil"), ("default_entry", "0; reboot"), ("nope", "1")] {
            let mut e = HashMap::new(); e.insert(id.to_string(), v.to_string());
            assert!(to_changes(&m, &e).is_err(), "{id}={v} must be refused");
        }
    }
}
