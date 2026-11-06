//! theme.txt model: parser, serializer, GRUB length expressions.
use indexmap::IndexMap;
use std::collections::BTreeMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

static NEXT: AtomicU64 = AtomicU64::new(1);
pub fn new_uid() -> u64 { NEXT.fetch_add(1, Ordering::Relaxed) }

#[derive(Clone, Debug)]
pub struct Comp {
    pub uid: u64,
    pub ty: String,
    pub props: IndexMap<String, String>, // raw values, strings keep their quotes
    pub children: Vec<Comp>,
    pub hidden: bool,
    pub locked: bool,
}
impl Comp {
    pub fn new(ty: &str) -> Self {
        Comp { uid: new_uid(), ty: ty.into(), props: IndexMap::new(), children: vec![], hidden: false, locked: false }
    }
    pub fn p(&self, k: &str) -> &str { self.props.get(k).map(|s| s.as_str()).unwrap_or("") }
    pub fn pu(&self, k: &str) -> &str { unq(self.p(k)) }
    pub fn deep_clone(&self) -> Comp {
        let mut c = self.clone();
        c.uid = new_uid();
        c.children = self.children.iter().map(|x| x.deep_clone()).collect();
        c
    }
}

pub type Assets = BTreeMap<String, Arc<Vec<u8>>>;

#[derive(Clone, Debug)]
pub struct Doc {
    pub globals: IndexMap<String, String>,
    pub root: Vec<Comp>,
    pub assets: Assets,
    pub screen: (i32, i32),
}
impl Default for Doc {
    fn default() -> Self {
        let mut g = IndexMap::new();
        g.insert("title-text".into(), "\"\"".into());
        g.insert("desktop-color".into(), "\"#101418\"".into());
        g.insert("terminal-font".into(), "\"Unifont Regular 16\"".into());
        Doc { globals: g, root: vec![], assets: BTreeMap::new(), screen: (1920, 1080) }
    }
}

pub fn unq(v: &str) -> &str {
    let t = v.trim();
    if t.len() >= 2 && t.starts_with('"') && t.ends_with('"') { &t[1..t.len() - 1] } else { t }
}
pub fn q(s: &str) -> String { format!("\"{}\"", s.replace('"', "")) }

fn is_ident(c: char) -> bool { c.is_ascii_alphanumeric() || c == '_' || c == '-' }

fn attach(stack: &mut Vec<Comp>, root: &mut Vec<Comp>, c: Comp) {
    match stack.last_mut() { Some(p) => p.children.push(c), None => root.push(c) }
}

pub fn parse_theme(text: &str) -> (IndexMap<String, String>, Vec<Comp>) {
    let mut globals = IndexMap::new();
    let mut root: Vec<Comp> = vec![];
    let mut stack: Vec<Comp> = vec![];
    for raw in text.replace('\r', "").lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') || line == "{" { continue; }
        if let Some(rest) = line.strip_prefix('+') {
            let rest = rest.trim_start();
            let end = rest.find(|c: char| !is_ident(c)).unwrap_or(rest.len());
            let ty = &rest[..end];
            if ty.is_empty() { continue; }
            let tail = rest[end..].trim();
            let mut c = Comp::new(ty);
            if tail.starts_with('{') && tail.ends_with('}') && tail.len() >= 2 {
                parse_inline(&tail[1..tail.len() - 1], &mut c);
                attach(&mut stack, &mut root, c);
            } else { stack.push(c); }
            continue;
        }
        if line.starts_with('}') {
            if let Some(c) = stack.pop() { attach(&mut stack, &mut root, c); }
            continue;
        }
        if let Some(i) = line.find(|c| c == ':' || c == '=') {
            let key = line[..i].trim();
            if !key.is_empty() && key.chars().all(is_ident) {
                let val = line[i + 1..].trim().to_string();
                match stack.last_mut() { Some(c) => { c.props.insert(key.into(), val); } None => { globals.insert(key.into(), val); } }
            }
        }
    }
    while let Some(c) = stack.pop() { attach(&mut stack, &mut root, c); }
    (globals, root)
}

fn parse_inline(s: &str, c: &mut Comp) {
    let b: Vec<char> = s.chars().collect();
    let mut i = 0;
    while i < b.len() {
        while i < b.len() && b[i].is_whitespace() { i += 1; }
        let ks = i;
        while i < b.len() && is_ident(b[i]) { i += 1; }
        let key: String = b[ks..i].iter().collect();
        while i < b.len() && b[i].is_whitespace() { i += 1; }
        if key.is_empty() || i >= b.len() || b[i] != '=' { i += 1; continue; }
        i += 1;
        while i < b.len() && b[i].is_whitespace() { i += 1; }
        let vs = i;
        if i < b.len() && b[i] == '"' { i += 1; while i < b.len() && b[i] != '"' { i += 1; } i += 1; }
        else { while i < b.len() && !b[i].is_whitespace() { i += 1; } }
        c.props.insert(key, b[vs..i.min(b.len())].iter().collect());
    }
}

pub fn serialize_theme(globals: &IndexMap<String, String>, root: &[Comp], header: &str) -> String {
    let mut out = String::new();
    for l in header.lines() { out.push_str(&format!("# {l}\n")); }
    for (k, v) in globals { out.push_str(&format!("{k}: {v}\n")); }
    fn emit(c: &Comp, ind: &str, out: &mut String) {
        out.push_str(&format!("\n{ind}+ {} {{\n", c.ty));
        for (k, v) in &c.props { if !v.is_empty() { out.push_str(&format!("{ind}  {k} = {v}\n")); } }
        let inner = format!("{ind}  ");
        for ch in &c.children { emit(ch, &inner, out); }
        out.push_str(&format!("{ind}}}\n"));
    }
    for c in root { emit(c, "", &mut out); }
    out
}

/// GRUB length expressions: "50%-120", "30%+4", "12".
pub fn eval_len(expr: Option<&str>, parent: i32, fallback: i32) -> i32 {
    let Some(e) = expr else { return fallback };
    let s: String = unq(e).chars().filter(|c| !c.is_whitespace()).collect();
    if s.is_empty() { return fallback; }
    let b: Vec<char> = s.chars().collect();
    let (mut i, mut total, mut ok) = (0usize, 0f64, false);
    while i < b.len() {
        let mut sign = 1.0;
        if b[i] == '+' || b[i] == '-' { if b[i] == '-' { sign = -1.0; } i += 1; }
        let st = i;
        while i < b.len() && (b[i].is_ascii_digit() || b[i] == '.') { i += 1; }
        if st == i { return fallback; }
        let n: f64 = b[st..i].iter().collect::<String>().parse().unwrap_or(0.0);
        let pct = i < b.len() && b[i] == '%';
        if pct { i += 1; }
        total += sign * if pct { n * parent as f64 / 100.0 } else { n };
        ok = true;
    }
    if ok { total.round() as i32 } else { fallback }
}

pub fn doc_from_files(files: &BTreeMap<String, Vec<u8>>) -> Result<Doc, String> {
    let key = files.keys().find(|k| k.eq_ignore_ascii_case("theme.txt")).ok_or("theme.txt not found in this theme")?.clone();
    let (globals, root) = parse_theme(&String::from_utf8_lossy(&files[&key]));
    let mut assets = Assets::new();
    for (k, v) in files {
        let l = k.to_ascii_lowercase();
        if *k != key && [".png", ".jpg", ".jpeg", ".tga", ".pf2"].iter().any(|e| l.ends_with(e)) { assets.insert(k.clone(), Arc::new(v.clone())); }
    }
    let mut screen = (1920, 1080);
    if let Some(v) = globals.get("screen-size") {
        if let Some((w, h)) = unq(v).split_once(|c| c == 'x' || c == 'X') { if let (Ok(w), Ok(h)) = (w.trim().parse(), h.trim().parse()) { screen = (w, h); } }
    }
    Ok(Doc { globals, root, assets, screen })
}

pub fn missing_assets(doc: &Doc) -> Vec<String> {
    let mut out: Vec<String> = vec![];
    let mut check = |v: &str| {
        let p = unq(v);
        if p.is_empty() { return; }
        let found = if let Some((a, b)) = p.split_once('*') { doc.assets.keys().any(|k| k.starts_with(a) && k.ends_with(b)) } else { doc.assets.contains_key(p) };
        if !found && !out.iter().any(|x| x == p) { out.push(p.to_string()); }
    };
    for k in ["desktop-image", "terminal-box"] { if let Some(v) = doc.globals.get(k) { check(v); } }
    fn walk(c: &Comp, f: &mut dyn FnMut(&str)) {
        for (k, v) in &c.props { if k == "file" || k == "center_bitmap" || k == "tick_bitmap" || k.ends_with("_style") { f(v); } }
        for ch in &c.children { walk(ch, f); }
    }
    for c in &doc.root { walk(c, &mut check); }
    out
}
