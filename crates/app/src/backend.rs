//! The QObject the QML UI talks to. One method, `call`, dispatches to the Rust core and returns text/JSON,
//! which keeps the bridge small. Long jobs (network, pkexec) run on worker threads and publish JSON properties.
use cxx_qt::{CxxQtThread, Threading};
use cxx_qt_lib::QString;
use pimp_my_grub_core::editor::Editor;
use pimp_my_grub_core::installer::{self, Report};
use pimp_my_grub_core::store::{self, RepoRef, StoreTheme};
use serde_json::json;
use std::collections::{HashMap, HashSet, VecDeque};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{LazyLock, Mutex, MutexGuard};

static ED: LazyLock<Mutex<Editor>> = LazyLock::new(|| Mutex::new(Editor::new()));
pub fn ed() -> MutexGuard<'static, Editor> { ED.lock().unwrap_or_else(|e| e.into_inner()) }

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(i32, rev)]
        #[qproperty(QString, store_json, cxx_name = "storeJson")]
        #[qproperty(QString, install_json, cxx_name = "installJson")]
        #[qproperty(QString, event)]
        #[qproperty(QString, picked)]
        type Backend = super::BackendRust;

        /// Single entry point: method name plus two string arguments.
        #[qinvokable]
        fn call(self: Pin<&mut Backend>, method: &QString, a: &QString, b: &QString) -> QString;
    }

    impl cxx_qt::Threading for Backend {}
}

use core::pin::Pin;
type Ui = CxxQtThread<qobject::Backend>;

#[derive(Default)]
pub struct BackendRust { rev: i32, store_json: QString, install_json: QString, event: QString, picked: QString }

// ------------------------------------------------------------------ helpers
fn percent_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() && b[i + 1].is_ascii_hexdigit() && b[i + 2].is_ascii_hexdigit() {
            // Work on bytes: slicing the &str here could panic when a multi-byte character follows the '%'.
            if let Some(v) = std::str::from_utf8(&b[i + 1..i + 3]).ok().and_then(|h| u8::from_str_radix(h, 16).ok()) { out.push(v); i += 3; continue; }
        }
        out.push(b[i]); i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}
fn url_path(u: &str) -> PathBuf { PathBuf::from(percent_decode(u.strip_prefix("file://").unwrap_or(u))) }
fn base_name(p: &std::path::Path) -> String { p.file_name().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default() }
fn safe_asset_name(n: &str) -> String { n.chars().map(|c| if c.is_ascii_alphanumeric() || "._+@- ".contains(c) { c } else { '_' }).collect() }
fn lock<T>(m: &'static Mutex<T>) -> MutexGuard<'static, T> { m.lock().unwrap_or_else(|e| e.into_inner()) }
static EVENT_N: AtomicU64 = AtomicU64::new(1);

// ------------------------------------------------------------------ system file / folder / colour pickers
// Qt's own dialog is only used when no system chooser can be launched. zenity (GTK) and kdialog (KDE) are the choosers
// desktops ship; they run as a child process so the app shows the same dialog as every other program.
static LAST_DIR: LazyLock<Mutex<String>> = LazyLock::new(|| Mutex::new(String::new()));
static PICK_N: AtomicU64 = AtomicU64::new(1);

fn find_tool(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|p| std::env::split_paths(&p).map(|d| d.join(name)).find(|f| f.is_file()))
}
/// Environment variables an AppImage / bundled Qt sets that would break a host program such as zenity.
fn scrub(c: &mut std::process::Command) {
    for k in ["LD_LIBRARY_PATH", "LD_PRELOAD", "QT_PLUGIN_PATH", "QML2_IMPORT_PATH", "QML_IMPORT_PATH", "QT_QPA_PLATFORMTHEME", "QT_QPA_PLATFORM", "QT_QUICK_CONTROLS_STYLE",
              "PYTHONHOME", "PYTHONPATH", "GIO_EXTRA_MODULES", "GTK_PATH", "GTK_EXE_PREFIX", "GTK_DATA_PREFIX", "GDK_PIXBUF_MODULE_FILE", "GDK_PIXBUF_MODULEDIR"] { c.env_remove(k); }
}
fn patterns(filter: &str) -> (String, Vec<String>) {
    // "Images|*.png *.jpg"  ->  ("Images", ["*.png", "*.PNG", "*.jpg", "*.JPG"])
    let (name, pats) = filter.split_once('|').unwrap_or(("Files", filter));
    let mut v = Vec::new();
    for p in pats.split_whitespace() { v.push(p.to_string()); let u = p.to_uppercase(); if u != p { v.push(u); } }
    (name.to_string(), v)
}
fn parse_colour(out: &str) -> Option<String> {
    let o = out.trim();
    if let Some(h) = o.strip_prefix('#') { if h.len() >= 6 && h[..6].chars().all(|c| c.is_ascii_hexdigit()) { return Some(format!("#{}", h[..6].to_lowercase())); } }
    let inner = o.strip_prefix("rgba(").or_else(|| o.strip_prefix("rgb("))?.trim_end_matches(')');
    let n: Vec<u8> = inner.split(',').take(3).filter_map(|x| x.trim().parse::<f32>().ok().map(|f| f.round().clamp(0.0, 255.0) as u8)).collect();
    if n.len() == 3 { Some(format!("#{:02x}{:02x}{:02x}", n[0], n[1], n[2])) } else { None }
}
/// Ok(Some(value)) chosen, Ok(None) cancelled, Err(()) no usable system chooser (caller falls back to Qt's dialog).
fn system_pick(kind: &str, title: &str, filter: &str, current: &str) -> Result<Option<String>, ()> {
    use std::process::Command;
    if std::env::var("PIMPMYGRUB_NATIVE_DIALOGS").map(|v| v == "0").unwrap_or(false) { return Err(()); }
    let kde = std::env::var("XDG_CURRENT_DESKTOP").unwrap_or_default().to_lowercase().contains("kde");
    let order: [&str; 2] = if kde { ["kdialog", "zenity"] } else { ["zenity", "kdialog"] };
    let start = { let l = lock(&LAST_DIR).clone(); if l.is_empty() { std::env::var("HOME").unwrap_or_else(|_| "/".into()) } else { l } };
    let start_slash = format!("{}/", start.trim_end_matches('/'));
    let (fname, pats) = patterns(filter);
    for tool in order {
        let Some(bin) = find_tool(tool) else { continue };
        let mut c = Command::new(bin);
        if tool == "zenity" {
            match kind {
                "color" => { c.args(["--color-selection", "--title", title]); if current.starts_with('#') { c.args(["--color", current]); } }
                "dir" => { c.args(["--file-selection", "--directory", "--title", title, "--filename", &start_slash]); }
                _ => { c.args(["--file-selection", "--title", title, "--filename", &start_slash]);
                       if !pats.is_empty() { c.arg(format!("--file-filter={fname} | {}", pats.join(" "))); c.arg("--file-filter=All files | *"); } }
            }
        } else {
            match kind {
                "color" => { c.arg("--getcolor"); }
                "dir" => { c.args(["--getexistingdirectory", &start_slash, "--title", title]); }
                _ => { c.args(["--getopenfilename", &start_slash]); c.arg(if pats.is_empty() { "*|All files".to_string() } else { format!("{}|{fname}", pats.join(" ")) }); c.args(["--title", title]); }
            }
        }
        scrub(&mut c);
        let Ok(o) = c.output() else { continue };
        let err = String::from_utf8_lossy(&o.stderr).to_lowercase();
        if o.status.success() {
            let out = String::from_utf8_lossy(&o.stdout); let line = out.lines().next().unwrap_or("").trim().to_string();
            if line.is_empty() { return Ok(None); }
            if kind == "color" { return Ok(parse_colour(&line)); }
            // zenity may return several paths separated by '|' when multi-select is on; we never ask for that.
            let p = PathBuf::from(&line);
            let dir = if p.is_dir() { Some(p.clone()) } else { p.parent().map(|d| d.to_path_buf()) };
            if let Some(d) = dir { *lock(&LAST_DIR) = d.to_string_lossy().into_owned(); }
            return Ok(Some(line));
        }
        // exit code 1 is "cancelled" for both tools, unless the toolkit could not even start
        if o.status.code() == Some(1) && !(err.contains("cannot open display") || err.contains("unable to init") || err.contains("failed to open display")) { return Ok(None); }
    }
    Err(())
}

// ------------------------------------------------------------------ persisted settings (accent colour ...)
fn settings_path() -> PathBuf {
    let base = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config"))).unwrap_or_else(|| PathBuf::from("/tmp"));
    base.join("pimp-my-grub").join("settings.json")
}
fn read_settings() -> serde_json::Map<String, serde_json::Value> {
    std::fs::read_to_string(settings_path()).ok().and_then(|t| serde_json::from_str(&t).ok()).unwrap_or_default()
}
fn write_setting(k: &str, v: &str) {
    let mut m = read_settings();
    if v.is_empty() { m.remove(k); } else { m.insert(k.to_string(), serde_json::Value::String(v.to_string())); }
    let p = settings_path();
    if let Some(d) = p.parent() { let _ = std::fs::create_dir_all(d); }
    let _ = std::fs::write(p, serde_json::Value::Object(m).to_string());
}

// ------------------------------------------------------------------ store state
#[derive(Default)]
struct StoreState {
    themes: Vec<StoreTheme>, seen: HashSet<String>, previews: HashMap<String, String>, pending: usize, note: String,
    busy: String, progress: String, query: String, sort: String, started: bool,
    pq: VecDeque<(String, String)>, pworkers: usize, rq: VecDeque<RepoRef>, iworkers: usize,
}
static STORE: LazyLock<Mutex<StoreState>> = LazyLock::new(|| Mutex::new(StoreState::default()));

fn store_json() -> String {
    let s = lock(&STORE);
    let toks: Vec<String> = s.query.to_lowercase().split_whitespace().map(String::from).collect();
    let mut v: Vec<&StoreTheme> = s.themes.iter().filter(|t| { let h = format!("{} {} {}", t.name, t.repo, t.desc).to_lowercase(); toks.iter().all(|k| h.contains(k)) }).collect();
    if s.sort == "name" { v.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase())); } else { v.sort_by(|a, b| b.stars.cmp(&a.stars).then(a.name.cmp(&b.name))); }
    let themes: Vec<_> = v.iter().map(|t| json!({
        "id": t.id, "name": t.name, "repo": t.repo, "stars": t.stars, "desc": t.desc,
        "preview": s.previews.get(&t.id).map(|p| format!("file://{p}")).unwrap_or_default(),
        "hasPreview": t.preview.is_some(), "variants": t.variants.iter().map(|x| x.label.clone()).collect::<Vec<_>>(),
    })).collect();
    json!({"themes": themes, "pending": s.pending, "note": s.note, "busy": s.busy, "progress": s.progress}).to_string()
}
fn push_store(t: &Ui) { let j = store_json(); let _ = t.queue(move |mut b| b.as_mut().set_store_json(QString::from(&j))); }
fn push_event(t: &Ui, ev: String) { let _ = t.queue(move |mut b| { b.as_mut().set_event(QString::from(&ev)); let r = *b.rev() + 1; b.as_mut().set_rev(r); }); }

fn start_index(t: &Ui, repos: Vec<RepoRef>) {
    let need = {
        let mut s = lock(&STORE);
        for r in repos { if s.seen.insert(r.repo.clone()) { s.pending += 1; s.rq.push_back(r); } }
        let n = 3usize.saturating_sub(s.iworkers).min(s.rq.len());
        s.iworkers += n; n
    };
    for _ in 0..need {
        let t = t.clone();
        std::thread::spawn(move || loop {
            let r = { let mut s = lock(&STORE); match s.rq.pop_front() { Some(r) => r, None => { s.iworkers -= 1; return; } } };
            let res = store::index_repo(&r);
            { let mut s = lock(&STORE); s.pending = s.pending.saturating_sub(1); match res { Ok(th) => s.themes.extend(th), Err(e) => s.note = e } }
            push_store(&t);
        });
    }
    push_store(t);
}

fn request_preview(t: &Ui, id: String) {
    let need = {
        let mut s = lock(&STORE);
        if s.previews.contains_key(&id) || s.pq.iter().any(|p| p.0 == id) { return; }
        let Some(url) = s.themes.iter().find(|x| x.id == id).and_then(|x| x.preview.clone()) else { return };
        s.pq.push_back((id, url));
        let n = 3usize.saturating_sub(s.pworkers).min(1);
        s.pworkers += n; n
    };
    for _ in 0..need {
        let t = t.clone();
        std::thread::spawn(move || loop {
            let (id, url) = { let mut s = lock(&STORE); match s.pq.pop_front() { Some(x) => x, None => { s.pworkers -= 1; return; } } };
            if let Ok(p) = store::fetch_preview(&url) { lock(&STORE).previews.insert(id, p.to_string_lossy().into_owned()); push_store(&t); }
        });
    }
}

fn store_get(t: &Ui, id: String, mode: String, vidx: usize) {
    let Some(theme) = lock(&STORE).themes.iter().find(|x| x.id == id).cloned() else { return };
    { let mut s = lock(&STORE); s.busy = id.clone(); s.progress = "Starting…".into(); s.note.clear(); }
    push_store(t);
    let t = t.clone();
    std::thread::spawn(move || {
        let v = theme.variants.get(vidx).or(theme.variants.first()).cloned();
        let Some(v) = v else { return };
        let tp = Mutex::new(t.clone());
        let res = store::download_theme(&theme, &v.dir, &|d, n| { lock(&STORE).progress = format!("Downloading {d}/{n}"); push_store(&tp.lock().unwrap()); });
        let mut ev = String::new();
        match res {
            Ok(files) => {
                let name = if theme.variants.len() > 1 { format!("{}-{}", theme.name, v.label) } else { theme.name.clone() };
                match ed().load_files(&files, &name) { Ok(()) => ev = format!("{mode}:{}:{name}", EVENT_N.fetch_add(1, Ordering::Relaxed)), Err(e) => lock(&STORE).note = e }
            }
            Err(e) => lock(&STORE).note = e,
        }
        { let mut s = lock(&STORE); s.busy.clear(); s.progress.clear(); }
        push_store(&t);
        if !ev.is_empty() { push_event(&t, ev); }
    });
}

// ------------------------------------------------------------------ installer state
#[derive(Default)]
struct InstallState { phase: String, mode: String, sys: Option<Report>, plan: Option<Report>, result: Option<Report>, live: Vec<String>, error: String, stage: Option<PathBuf>, seq: u64 }
static INSTALL: LazyLock<Mutex<InstallState>> = LazyLock::new(|| Mutex::new(InstallState::default()));

fn install_json() -> String {
    let s = lock(&INSTALL);
    json!({"phase": s.phase, "mode": s.mode, "sys": s.sys, "plan": s.plan, "result": s.result, "live": s.live, "error": s.error}).to_string()
}
fn push_install(t: &Ui) { let j = install_json(); let _ = t.queue(move |mut b| b.as_mut().set_install_json(QString::from(&j))); }

fn probe(t: &Ui, then_phase: &'static str) {
    let t = t.clone();
    std::thread::spawn(move || {
        let r = installer::run_helper("status", &[], &mut |_| {});
        {
            let mut s = lock(&INSTALL);
            match r {
                Ok((_, rep)) => { if let Some(f) = rep.fatal.clone() { s.error = f; s.phase = "failed".into(); } else { s.phase = then_phase.into(); } s.sys = Some(rep); }
                Err(e) => { s.error = e; s.phase = "failed".into(); }
            }
        }
        push_install(&t);
    });
}

fn install_plan(t: &Ui, name: String, gfx: String) {
    let seq = { let mut s = lock(&INSTALL); s.seq += 1; s.plan = None; s.error.clear(); s.seq };
    push_install(t);
    let t = t.clone();
    std::thread::spawn(move || {
        let files = ed().files();
        let out = installer::stage_theme(&files).and_then(|stage| {
            let (_, rep) = installer::run_helper("plan", &[stage.to_string_lossy().into_owned(), name, gfx], &mut |_| {})?;
            Ok((stage, rep))
        });
        {
            let mut s = lock(&INSTALL);
            if s.seq != seq { return; }
            match out { Ok((stage, rep)) => { if let Some(f) = rep.fatal.clone() { s.error = f; } s.stage = Some(stage); s.plan = Some(rep); } Err(e) => s.error = e }
        }
        push_install(&t);
    });
}

fn install_run(t: &Ui, mode: &'static str, args: Vec<String>) {
    { let mut s = lock(&INSTALL); s.phase = "applying".into(); s.live.clear(); s.error.clear(); s.result = None; }
    push_install(t);
    let t = t.clone();
    std::thread::spawn(move || {
        let tp = t.clone();
        let r = installer::run_helper(mode, &args, &mut |l| { if let Some(st) = l.strip_prefix("STEP\t") { lock(&INSTALL).live.push(st.to_string()); push_install(&tp); } });
        {
            let mut s = lock(&INSTALL);
            match r {
                Ok((_, rep)) => { if rep.ok { s.phase = "done".into(); } else { s.phase = "failed".into(); s.error = rep.fatal.clone().unwrap_or_else(|| "The change was not completed.".into()); } s.result = Some(rep); }
                Err(e) => { s.phase = "failed".into(); s.error = e; }
            }
        }
        push_install(&t);
        // refresh system info so Manage shows the new state
        if let Ok((_, rep)) = installer::run_helper("status", &[], &mut |_| {}) { lock(&INSTALL).sys = Some(rep); push_install(&t); }
    });
}

// ------------------------------------------------------------------ the QObject
impl qobject::Backend {
    pub fn call(mut self: Pin<&mut Self>, method: &QString, a: &QString, b: &QString) -> QString {
        let (m, a, b) = (method.to_string(), a.to_string(), b.to_string());
        let t = self.qt_thread();
        let mut mutated = true;
        let out: String = match m.as_str() {
            // ---- read-only
            "layers" => { mutated = false; ed().layers_json() }
            "inspector" => { mutated = false; ed().inspector_json() }
            "status" => { mutated = false; let e = ed(); json!({"undo": e.can_undo(), "redo": e.can_redo(), "name": e.name, "menuSel": e.menu_sel, "progress": e.progress}).to_string() }
            // ---- editing
            "undo" => { ed().undo(); String::new() }
            "redo" => { ed().redo(); String::new() }
            "new" => { ed().reset(); String::new() }
            "add" => { ed().add(&a, &[]); String::new() }
            "addRect" => { ed().add_rect(&a); String::new() }
            "remove" => { let mut e = ed(); if let Some(u) = e.selected { e.remove(u); } String::new() }
            "duplicate" => { let mut e = ed(); if let Some(u) = e.selected { e.duplicate(u); } String::new() }
            "reorder" => { let mut e = ed(); if let Some(u) = e.selected { e.reorder(u, a.parse().unwrap_or(1)); } String::new() }
            "select" => { ed().selected = a.parse().ok(); String::new() }
            // Changes nothing; only bumps `rev` so the panels refresh after a canvas edit. (The canvas used to call
            // "select" with an empty id for this, which silently cleared the selection on every click.)
            "touch" => String::new(),
            "getSetting" => { mutated = false; read_settings().get(&a).and_then(|v| v.as_str()).unwrap_or("").to_string() }
            "setSetting" => { mutated = false; write_setting(&a, &b); String::new() }
            // a = "kind\u{1}title\u{1}filter\u{1}current", b = token. Returns "native" when a system chooser was started
            // (the answer arrives later in `picked`), otherwise "fallback" and the QML side opens Qt's own dialog.
            "pick" => {
                mutated = false;
                let mut it = a.split('\u{1}');
                let (kind, title, filter, current) = (it.next().unwrap_or("file").to_string(), it.next().unwrap_or("").to_string(), it.next().unwrap_or("").to_string(), it.next().unwrap_or("").to_string());
                let usable = !std::env::var("PIMPMYGRUB_NATIVE_DIALOGS").map(|v| v == "0").unwrap_or(false) && (find_tool("zenity").is_some() || find_tool("kdialog").is_some());
                if usable {
                    let tok = b.clone();
                    std::thread::spawn(move || {
                        let n = PICK_N.fetch_add(1, Ordering::Relaxed);
                        let val = match system_pick(&kind, &title, &filter, &current) { Ok(Some(v)) => v, Ok(None) => String::new(), Err(()) => "!fallback".to_string() };
                        let msg = format!("{n}\u{1}{tok}\u{1}{val}");
                        let _ = t.queue(move |mut bk| { bk.as_mut().set_picked(QString::from(&msg)); });
                    });
                    "native".to_string()
                } else { "fallback".to_string() }
            }
            "version" => { mutated = false; env!("CARGO_PKG_VERSION").to_string() }
            "toggle" => { if let Ok(u) = a.parse() { ed().toggle(u, b == "locked"); } String::new() }
            "setField" => { ed().set_field(&a, &b); String::new() }
            "rectColor" => { let mut e = ed(); if let Some(u) = e.selected { e.recolor_rect(u, &a); } String::new() }
            "center" => { let mut e = ed(); if let Some(u) = e.selected { e.center(u, a == "x"); } String::new() }
            "solidStyle" => { let mut e = ed(); if let Some(u) = e.selected { e.add_solid_style(u, &a, &b); } String::new() }
            "menuSel" => { ed().menu_sel = a.parse().unwrap_or(0); String::new() }
            "progress" => { ed().progress = a.parse().unwrap_or(0.5); String::new() }
            "setName" => { let mut e = ed(); e.name = a.chars().map(|c| if c.is_ascii_alphanumeric() || "._-".contains(c) { c } else { '-' }).take(48).collect(); String::new() }
            "removeAsset" => { ed().remove_asset(&a); String::new() }
            "addAsset" => {
                let p = url_path(&a);
                match std::fs::read(&p) {
                    Ok(bytes) if bytes.len() <= 16 << 20 => { let n = safe_asset_name(&base_name(&p)); ed().add_asset(&n, bytes); n }
                    Ok(_) => "ERR:file is larger than 16 MB".into(),
                    Err(e) => format!("ERR:{e}"),
                }
            }
            "addFont" => {
                let p = url_path(&a);
                let size: u32 = b.parse().unwrap_or(24);
                match std::fs::read(&p).map_err(|e| e.to_string()).and_then(|ttf| installer::convert_font(&ttf, size)) {
                    Ok(pf2) => {
                        let name = pimp_my_grub_core::pf2::read_name(&pf2);
                        let stem = p.file_stem().map(|s| safe_asset_name(&s.to_string_lossy())).unwrap_or_else(|| "font".into());
                        ed().add_asset(&format!("{stem}-{size}.pf2"), pf2);
                        name
                    }
                    Err(e) => format!("ERR:{e}"),
                }
            }
            "openFolder" => { let p = url_path(&a); match installer::read_dir_files(&p).and_then(|f| ed().load_files(&f, &base_name(&p))) { Ok(()) => String::new(), Err(e) => format!("ERR:{e}") } }
            "openZip" => {
                let p = url_path(&a);
                let stem = p.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
                match std::fs::read(&p).map_err(|e| e.to_string()).and_then(|b| installer::unzip(&b)).and_then(|f| ed().load_files(&f, &stem)) { Ok(()) => String::new(), Err(e) => format!("ERR:{e}") }
            }
            "exportTo" => {
                let e = ed();
                let dest = url_path(&a).join(&e.name);
                match std::fs::create_dir_all(&dest).map_err(|e| e.to_string()).and_then(|_| installer::write_files(&e.files(), &dest)) { Ok(()) => dest.to_string_lossy().into_owned(), Err(er) => format!("ERR:{er}") }
            }
            // ---- store
            "storeInit" => {
                mutated = false;
                let first = { let mut s = lock(&STORE); let f = !s.started; s.started = true; f };
                if first {
                    let (repos, themes) = store::catalog();
                    { let mut s = lock(&STORE); for th in themes { s.seen.insert(th.repo.clone()); s.themes.push(th); } }
                    start_index(&t, repos);
                } else { push_store(&t); }
                String::new()
            }
            "storeQuery" => { mutated = false; { let mut s = lock(&STORE); s.query = a; s.sort = b; } push_store(&t); String::new() }
            "storeGithub" => {
                mutated = false;
                { lock(&STORE).note.clear(); }
                let t2 = t.clone();
                std::thread::spawn(move || match store::search_github(&a) {
                    Ok(r) => { if r.is_empty() { lock(&STORE).note = "No GitHub repositories found with the grub-theme topic.".into(); } start_index(&t2, r); }
                    Err(e) => { lock(&STORE).note = e; push_store(&t2); }
                });
                String::new()
            }
            "preview" => { mutated = false; request_preview(&t, a); String::new() }
            "storeGet" => { mutated = false; store_get(&t, a, b.split(':').next().unwrap_or("edit").to_string(), b.split(':').nth(1).and_then(|x| x.parse().ok()).unwrap_or(0)); String::new() }
            // ---- installer
            "installOpen" => {
                mutated = false;
                { let mut s = lock(&INSTALL); *s = InstallState { phase: "probe".into(), mode: a.clone(), seq: s.seq, ..Default::default() }; }
                push_install(&t);
                probe(&t, if a == "manage" { "manage" } else { "review" });
                String::new()
            }
            "installPlan" => { mutated = false; install_plan(&t, a, b); String::new() }
            "installApply" => {
                mutated = false;
                let stage = lock(&INSTALL).stage.clone();
                match stage { Some(st) => install_run(&t, "apply", vec![st.to_string_lossy().into_owned(), a, b]), None => { lock(&INSTALL).error = "Nothing is prepared yet.".into(); push_install(&t); } }
                String::new()
            }
            "installRollback" => { mutated = false; install_run(&t, "rollback", vec![]); String::new() }
            "installUninstall" => { mutated = false; install_run(&t, "uninstall", vec![]); String::new() }
            _ => { mutated = false; format!("ERR:unknown method {m}") }
        };
        if mutated { let r = *self.rev() + 1; self.as_mut().set_rev(r); }
        QString::from(&out)
    }
}
