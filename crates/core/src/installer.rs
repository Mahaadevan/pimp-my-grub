//! Talks to the privileged helper (pkexec) and handles theme files on disk.
use serde::Serialize;
use std::collections::BTreeMap;
use std::io::{BufRead, BufReader, Cursor, Read, Write};
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub const HELPER: &str = include_str!("../../../helper/pimp-my-grub-helper.sh");
/// Installed by the distro packages together with a polkit policy (friendly auth dialog).
pub const INSTALLED_HELPER: &str = "/usr/libexec/pimp-my-grub/pimp-my-grub-helper";
const SYSTEM_PATH: &str = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
const MAX_TOTAL: usize = 64 * 1024 * 1024;
const MAX_FILE: usize = 16 * 1024 * 1024;
const MAX_FILES: usize = 800;
pub const THEME_EXT: [&str; 6] = [".txt", ".png", ".jpg", ".jpeg", ".tga", ".pf2"];

fn ok_name(n: &str) -> bool { let l = n.to_ascii_lowercase(); THEME_EXT.iter().any(|e| l.ends_with(e)) }
fn safe_component(c: &str) -> bool { !c.is_empty() && c != "." && c != ".." && c.chars().all(|ch| ch.is_ascii_alphanumeric() || "._+@- ".contains(ch)) }

#[derive(Default, Serialize, Clone, Debug)]
pub struct Change { pub action: String, pub path: String, pub note: String }
#[derive(Default, Serialize, Clone, Debug)]
pub struct Report {
    pub steps: Vec<String>, pub info: BTreeMap<String, String>, pub warns: Vec<String>, pub changes: Vec<Change>,
    pub diff: String, pub fatal: Option<String>, pub ok: bool, pub restored: bool, pub mkconfig: Vec<String>,
}

pub fn parse_report(lines: &[String]) -> Report {
    let mut r = Report::default();
    let mut in_diff = false;
    for line in lines {
        if line == "DIFFBEGIN" { in_diff = true; continue; }
        if line == "DIFFEND" { in_diff = false; continue; }
        if in_diff { r.diff.push_str(line); r.diff.push('\n'); continue; }
        let p: Vec<&str> = line.splitn(4, '\t').collect();
        let g = |i: usize| p.get(i).copied().unwrap_or("").to_string();
        match p[0] {
            "STEP" => r.steps.push(g(1)),
            "INFO" => { r.info.insert(g(1), g(2)); }
            "WARN" => r.warns.push(g(1)),
            "CHANGE" => r.changes.push(Change { action: g(1), path: g(2), note: g(3) }),
            "FATAL" => r.fatal = Some(g(1)),
            "MKCONFIG" => r.mkconfig.push(g(1)),
            "RESTORED" => r.restored = true,
            "OK" => r.ok = true,
            _ => {}
        }
    }
    r
}

pub fn stage_root() -> PathBuf {
    let uid = std::fs::metadata("/proc/self").map(|m| m.uid()).unwrap_or(0);
    let base = std::env::var("XDG_RUNTIME_DIR").ok().filter(|p| Path::new(p).is_dir()).unwrap_or_else(|| "/tmp".into());
    PathBuf::from(base).join(format!("pimpmygrub-{uid}"))
}

/// Write whitelisted files into a private staging folder. The helper re-validates it as root.
pub fn write_files(files: &BTreeMap<String, Vec<u8>>, dest: &Path) -> Result<(), String> {
    let (mut total, mut n) = (0usize, 0usize);
    for (name, data) in files {
        if !ok_name(name) { continue; }
        if !name.split('/').all(safe_component) { return Err(format!("unsafe file name: {name}")); }
        if data.len() > MAX_FILE { return Err(format!("file too large: {name}")); }
        total += data.len(); n += 1;
        if total > MAX_TOTAL || n > MAX_FILES { return Err("theme is too large".into()); }
        let p = dest.join(name);
        if let Some(d) = p.parent() { std::fs::create_dir_all(d).map_err(|e| e.to_string())?; }
        std::fs::write(&p, data).map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub fn stage_theme(files: &BTreeMap<String, Vec<u8>>) -> Result<PathBuf, String> {
    let root = stage_root();
    if root.exists() { if let Ok(rd) = std::fs::read_dir(&root) { for e in rd.flatten() { let _ = std::fs::remove_dir_all(e.path()); } } }
    let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(|e| e.to_string())?.as_nanos();
    let dir = root.join(format!("stage-{nanos}"));
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o700)).map_err(|e| e.to_string())?;
    write_files(files, &dir)?;
    if !dir.join("theme.txt").is_file() { return Err("theme.txt is missing".into()); }
    Ok(dir)
}

pub fn read_dir_files(dir: &Path) -> Result<BTreeMap<String, Vec<u8>>, String> {
    fn walk(d: &Path, base: &Path, depth: usize, out: &mut BTreeMap<String, Vec<u8>>, total: &mut usize) -> Result<(), String> {
        if depth > 6 { return Ok(()); }
        for e in std::fs::read_dir(d).map_err(|e| e.to_string())?.flatten() {
            let ft = e.file_type().map_err(|e| e.to_string())?;
            let p = e.path();
            if ft.is_symlink() { continue; }
            if ft.is_dir() { walk(&p, base, depth + 1, out, total)?; }
            else if ft.is_file() && ok_name(&p.to_string_lossy()) {
                let data = std::fs::read(&p).map_err(|e| e.to_string())?;
                *total += data.len();
                if *total > MAX_TOTAL || out.len() >= MAX_FILES { return Err("folder is too large".into()); }
                out.insert(p.strip_prefix(base).unwrap().to_string_lossy().replace('\\', "/"), data);
            }
        }
        Ok(())
    }
    let mut out = BTreeMap::new();
    walk(dir, dir, 0, &mut out, &mut 0)?;
    if out.is_empty() { return Err("no theme files found in that folder".into()); }
    Ok(out)
}

pub fn unzip(bytes: &[u8]) -> Result<BTreeMap<String, Vec<u8>>, String> {
    let mut ar = zip::ZipArchive::new(Cursor::new(bytes)).map_err(|e| e.to_string())?;
    let mut out = BTreeMap::new();
    let mut total = 0usize;
    for i in 0..ar.len() {
        let mut f = ar.by_index(i).map_err(|e| e.to_string())?;
        if f.is_dir() { continue; }
        let Some(name) = f.enclosed_name().map(|p| p.to_string_lossy().replace('\\', "/")) else { continue };
        if !ok_name(&name) { continue; }
        let mut data = Vec::new();
        f.by_ref().take(MAX_FILE as u64 + 1).read_to_end(&mut data).map_err(|e| e.to_string())?;
        total += data.len();
        if data.len() > MAX_FILE || total > MAX_TOTAL || out.len() >= MAX_FILES { return Err("archive is too large".into()); }
        out.insert(name, data);
    }
    // strip a single top-level folder ("MyTheme/theme.txt")
    if !out.contains_key("theme.txt") {
        if let Some(k) = out.keys().find(|k| k.ends_with("/theme.txt") && k.matches('/').count() == 1).cloned() {
            let pre = k.trim_end_matches("theme.txt").to_string();
            out = out.into_iter().filter_map(|(k, v)| k.strip_prefix(&pre).map(|s| (s.to_string(), v))).collect();
        }
    }
    Ok(out)
}

/// TTF/OTF -> PF2 using GRUB's own grub-mkfont.
pub fn convert_font(ttf: &[u8], size: u32) -> Result<Vec<u8>, String> {
    if !(8..=160).contains(&size) { return Err("font size must be between 8 and 160".into()); }
    let tool = ["grub-mkfont", "grub2-mkfont"].into_iter().find(|t| SYSTEM_PATH.split(':').any(|d| Path::new(d).join(t).is_file()))
        .ok_or("grub-mkfont was not found. Install grub-common (Debian/Ubuntu) or grub2-tools (Fedora).")?;
    let tmp = std::env::temp_dir().join(format!("pimpmygrub-font-{}", std::process::id()));
    std::fs::create_dir_all(&tmp).map_err(|e| e.to_string())?;
    let (inp, out) = (tmp.join("in.ttf"), tmp.join("out.pf2"));
    std::fs::write(&inp, ttf).map_err(|e| e.to_string())?;
    let res = Command::new(tool).env_clear().env("PATH", SYSTEM_PATH).args(["-s", &size.to_string(), "-o"]).arg(&out).arg(&inp).output().map_err(|e| e.to_string())
        .and_then(|o| if o.status.success() { std::fs::read(&out).map_err(|e| e.to_string()) } else { Err(String::from_utf8_lossy(&o.stderr).into_owned()) });
    let _ = std::fs::remove_dir_all(&tmp);
    res
}

/// Run the helper. `status` and `plan` are read-only and run as the user; the rest go through pkexec.
/// Returns the process exit code and the parsed report.
pub fn run_helper(mode: &str, args: &[String], on_line: &mut dyn FnMut(&str)) -> Result<(i32, Report), String> {
    let privileged = match mode { "status" | "plan" => false, "apply" | "rollback" | "uninstall" => true, _ => return Err("unknown mode".into()) };
    if matches!(mode, "plan" | "apply") {
        let stage = args.first().ok_or("missing staged folder")?;
        let canon = std::fs::canonicalize(stage).map_err(|e| e.to_string())?;
        let root = std::fs::canonicalize(stage_root()).map_err(|e| e.to_string())?;
        if !canon.starts_with(&root) { return Err("staged folder is outside the Pimp my grub staging area".into()); }
    }
    let installed = Path::new(INSTALLED_HELPER).is_file();
    let mut cmd;
    if privileged { cmd = Command::new("pkexec"); if installed { cmd.arg(INSTALLED_HELPER); } else { cmd.args(["/bin/sh", "-c", HELPER, "pimp-my-grub-helper"]); } }
    else if installed { cmd = Command::new(INSTALLED_HELPER); }
    else { cmd = Command::new("/bin/sh"); cmd.args(["-c", HELPER, "pimp-my-grub-helper"]); }
    cmd.arg(mode).args(args);
    // AppImage-style library paths would break system tools.
    for k in ["LD_LIBRARY_PATH", "LD_PRELOAD", "APPDIR", "APPIMAGE", "ARGV0", "OWD", "PYTHONHOME", "PERLLIB", "QT_PLUGIN_PATH", "QML2_IMPORT_PATH"] { cmd.env_remove(k); }
    cmd.env("PATH", SYSTEM_PATH).env("LC_ALL", "C").stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = cmd.spawn().map_err(|e| format!("could not start helper: {e}"))?;
    let stderr = child.stderr.take();
    let t = std::thread::spawn(move || { let mut s = String::new(); if let Some(mut e) = stderr { let _ = e.read_to_string(&mut s); } s });
    let mut lines = vec![];
    if let Some(out) = child.stdout.take() { for line in BufReader::new(out).lines().map_while(Result::ok) { on_line(&line); lines.push(line); } }
    let code = child.wait().map_err(|e| e.to_string())?.code().unwrap_or(-1);
    let errtxt = t.join().unwrap_or_default();
    let mut rep = parse_report(&lines);
    if code == 126 { rep.fatal = Some("Authentication was cancelled. Nothing was changed.".into()); }
    else if code == 127 { rep.fatal = Some("Could not start pkexec. Install polkit to apply changes.".into()); }
    else if code != 0 && rep.fatal.is_none() { rep.fatal = Some(errtxt.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or("The helper failed.").to_string()); }
    let _ = std::io::stdout().flush();
    Ok((code, rep))
}
