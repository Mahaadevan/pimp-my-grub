//! Theme store: catalog, repo indexing (GitHub API with jsDelivr fallback), previews and downloads.
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::io::Read;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;
use std::time::Duration;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RepoRef { pub repo: String, pub branch: String, #[serde(default)] pub stars: u64, #[serde(default)] pub desc: String }
#[derive(Clone, Debug)]
pub struct FileEntry { pub path: String, pub size: u64 }
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Variant { pub label: String, pub dir: String }
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct StoreTheme {
    pub id: String, pub repo: String, pub branch: String, pub name: String, pub stars: u64, pub desc: String,
    pub preview: Option<String>, pub variants: Vec<Variant>,
}

const CATALOG: &str = include_str!("../../../data/catalog.json");
const IMG_EXT: [&str; 5] = [".png", ".jpg", ".jpeg", ".webp", ".gif"];
pub const ALLOWED_EXT: [&str; 5] = [".txt", ".png", ".jpg", ".jpeg", ".tga"];

fn base(p: &str) -> &str { p.rsplit('/').next().unwrap_or(p) }
fn stem(p: &str) -> String { let b = base(p); b.rsplit_once('.').map(|x| x.0).unwrap_or(b).to_string() }
fn is_img(p: &str) -> bool { let l = p.to_ascii_lowercase(); IMG_EXT.iter().any(|e| l.ends_with(e)) }
fn previewish(n: &str) -> bool { let l = n.to_ascii_lowercase(); ["preview", "screenshot", "demo", "thumb", "showcase"].iter().any(|k| l.contains(k)) }
fn is_res(s: &str) -> bool {
    let l = s.to_ascii_lowercase();
    let digits = |x: &str| !x.is_empty() && x.chars().all(|c| c.is_ascii_digit());
    (l.ends_with('p') && digits(&l[..l.len() - 1]) && l.len() >= 4) || l.split_once('x').map(|(a, b)| digits(a) && digits(b)).unwrap_or(false)
        || matches!(l.as_str(), "2k" | "4k" | "8k" | "hd" | "fhd" | "qhd" | "uhd")
}

fn enc(seg: &str) -> String {
    seg.bytes().map(|b| if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) { (b as char).to_string() } else { format!("%{:02X}", b) }).collect()
}
pub fn raw_url(repo: &str, branch: &str, path: &str) -> String {
    format!("https://raw.githubusercontent.com/{repo}/{branch}/{}", path.split('/').map(enc).collect::<Vec<_>>().join("/"))
}

pub fn index_files(r: &RepoRef, files: &[FileEntry]) -> Vec<StoreTheme> {
    let mut groups: Vec<(String, Vec<Variant>)> = vec![];
    let mut push = |key: String, v: Variant| match groups.iter_mut().find(|g| g.0 == key) { Some(g) => g.1.push(v), None => groups.push((key, vec![v])) };
    for f in files {
        let l = f.path.to_ascii_lowercase();
        if !(l == "theme.txt" || l.ends_with("/theme.txt")) || f.path.contains(".github/") || f.path.contains("node_modules/") { continue; }
        let dir = f.path[..f.path.len() - "theme.txt".len()].trim_end_matches('/').to_string();
        let last = base(&dir).to_string();
        if !dir.is_empty() && is_res(&last) && dir.contains('/') {
            push(dir[..dir.rfind('/').unwrap()].to_string(), Variant { label: last, dir });
        } else { push(dir.clone(), Variant { label: "default".into(), dir }); }
    }
    let images: Vec<&FileEntry> = files.iter().filter(|f| is_img(&f.path) && f.size <= 1_500_000).collect();
    let mut out = vec![];
    for (key, mut variants) in groups.into_iter().take(80) {
        let name = if key.is_empty() { r.repo.split('/').nth(1).unwrap_or("theme").to_string() } else { base(&key).to_string() };
        let inside = |f: &&&FileEntry| key.is_empty() || f.path.starts_with(&format!("{key}/"));
        let ctx = |p: &str| { let l = p.to_ascii_lowercase(); ["preview", "screenshot", "image", "asset", "doc", "demo"].iter().any(|k| l.contains(k)) };
        let pv = images.iter().filter(inside).find(|f| previewish(base(&f.path)))
            .or_else(|| images.iter().find(|f| stem(&f.path).eq_ignore_ascii_case(&name) && ctx(&f.path)))
            .or_else(|| if out.is_empty() && key.is_empty() || true { None } else { None })
            .or_else(|| images.iter().filter(inside).find(|f| { let b = base(&f.path).to_ascii_lowercase(); (b.starts_with("background") || b.starts_with("bg") || b.starts_with("wallpaper")) && f.size <= 700_000 }));
        variants.sort_by_key(|v| (!v.label.contains("1080"), v.label.clone()));
        out.push(StoreTheme { id: format!("{}#{}", r.repo, if key.is_empty() { "." } else { &key }), repo: r.repo.clone(), branch: r.branch.clone(), name, stars: r.stars, desc: r.desc.clone(), preview: pv.map(|f| raw_url(&r.repo, &r.branch, &f.path)), variants });
    }
    out
}

// -------------------------------------------------------------------- network
fn get(url: &str, limit: u64) -> Result<Vec<u8>, String> {
    let agent = ureq::AgentBuilder::new().timeout(Duration::from_secs(25)).user_agent("pimp-my-grub").build();
    let mut req = agent.get(url);
    // An optional token lifts GitHub's API rate limit (used when building the catalog in CI).
    if let (true, Ok(t)) = (url.starts_with("https://api.github.com"), std::env::var("GITHUB_TOKEN")) { req = req.set("Authorization", &format!("Bearer {t}")); }
    let resp = req.call().map_err(|e| match e { ureq::Error::Status(c, _) => format!("HTTP {c} for {url}"), e => e.to_string() })?;
    let mut buf = Vec::new();
    resp.into_reader().take(limit + 1).read_to_end(&mut buf).map_err(|e| e.to_string())?;
    if buf.len() as u64 > limit { return Err("download is larger than the allowed limit".into()); }
    Ok(buf)
}

pub fn cache_dir() -> PathBuf {
    let base = std::env::var("XDG_CACHE_HOME").map(PathBuf::from).unwrap_or_else(|_| PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| "/tmp".into())).join(".cache"));
    base.join("pimp-my-grub")
}

fn list_files(repo: &str, branch: &str) -> Result<Vec<FileEntry>, String> {
    let gh = get(&format!("https://api.github.com/repos/{repo}/git/trees/{branch}?recursive=1"), 20_000_000)
        .and_then(|b| serde_json::from_slice::<serde_json::Value>(&b).map_err(|e| e.to_string()))
        .map(|j| j["tree"].as_array().map(|a| a.iter().filter(|t| t["type"] == "blob").map(|t| FileEntry { path: t["path"].as_str().unwrap_or("").into(), size: t["size"].as_u64().unwrap_or(0) }).collect::<Vec<_>>()).unwrap_or_default());
    match gh { Ok(v) if !v.is_empty() => Ok(v), _ => {
        let b = get(&format!("https://data.jsdelivr.com/v1/packages/gh/{repo}@{branch}?structure=flat"), 20_000_000).map_err(|e| format!("Could not list {repo}: {e}"))?;
        let j: serde_json::Value = serde_json::from_slice(&b).map_err(|e| e.to_string())?;
        Ok(j["files"].as_array().map(|a| a.iter().map(|f| FileEntry { path: f["name"].as_str().unwrap_or("").trim_start_matches('/').into(), size: f["size"].as_u64().unwrap_or(0) }).collect()).unwrap_or_default())
    } }
}

/// Bundled catalog: curated repos and, when built by CI, fully indexed themes.
pub fn catalog() -> (Vec<RepoRef>, Vec<StoreTheme>) {
    // PIMPMYGRUB_CATALOG=/path/catalog.json overrides the bundled list (offline mirrors, testing).
    let text = std::env::var("PIMPMYGRUB_CATALOG").ok().and_then(|p| std::fs::read_to_string(p).ok()).unwrap_or_else(|| CATALOG.to_string());
    let j: serde_json::Value = serde_json::from_str(&text).unwrap_or_default();
    (serde_json::from_value(j["repos"].clone()).unwrap_or_default(), serde_json::from_value(j["themes"].clone()).unwrap_or_default())
}

pub fn index_repo(r: &RepoRef) -> Result<Vec<StoreTheme>, String> {
    let path = cache_dir().join("idx").join(format!("{}.json", r.repo.replace('/', "__")));
    if let Ok(m) = std::fs::metadata(&path) {
        if m.modified().ok().and_then(|t| t.elapsed().ok()).map(|e| e < Duration::from_secs(86_400)).unwrap_or(false) {
            if let Ok(t) = std::fs::read(&path).map_err(|e| e.to_string()).and_then(|b| serde_json::from_slice(&b).map_err(|e| e.to_string())) { return Ok(t); }
        }
    }
    let themes = index_files(r, &list_files(&r.repo, &r.branch)?);
    let _ = std::fs::create_dir_all(path.parent().unwrap());
    let _ = std::fs::write(&path, serde_json::to_vec(&themes).unwrap_or_default());
    Ok(themes)
}

pub fn search_github(query: &str) -> Result<Vec<RepoRef>, String> {
    let q: String = format!("{query} topic:grub-theme").bytes().map(|b| if b.is_ascii_alphanumeric() || b"-_.~:".contains(&b) { (b as char).to_string() } else { format!("%{:02X}", b) }).collect();
    let b = get(&format!("https://api.github.com/search/repositories?q={q}&sort=stars&per_page=20"), 5_000_000).map_err(|e| if e.contains("403") { "GitHub rate limit reached. Try again later.".to_string() } else { e })?;
    let j: serde_json::Value = serde_json::from_slice(&b).map_err(|e| e.to_string())?;
    Ok(j["items"].as_array().map(|a| a.iter().map(|i| RepoRef { repo: i["full_name"].as_str().unwrap_or("").into(), branch: i["default_branch"].as_str().unwrap_or("main").into(), stars: i["stargazers_count"].as_u64().unwrap_or(0), desc: i["description"].as_str().unwrap_or("").into() }).collect()).unwrap_or_default())
}

/// Download a preview into the cache and return its local path (only small images are accepted).
pub fn fetch_preview(url: &str) -> Result<PathBuf, String> {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in url.bytes() { h ^= b as u64; h = h.wrapping_mul(0x100000001b3); }
    let ext = url.rsplit('.').next().filter(|e| e.len() <= 4).unwrap_or("png");
    let path = cache_dir().join("previews").join(format!("{h:016x}.{ext}"));
    if path.is_file() { return Ok(path); }
    let bytes = get(url, 2_000_000)?;
    let _ = std::fs::create_dir_all(path.parent().unwrap());
    std::fs::write(&path, bytes).map_err(|e| e.to_string())?;
    Ok(path)
}

/// Download one theme directory (paths relative to that directory).
pub fn download_theme(t: &StoreTheme, dir: &str, progress: &(dyn Fn(usize, usize) + Sync)) -> Result<BTreeMap<String, Vec<u8>>, String> {
    let prefix = if dir.is_empty() { String::new() } else { format!("{dir}/") };
    let files: Vec<FileEntry> = list_files(&t.repo, &t.branch)?.into_iter().filter(|f| f.path.starts_with(&prefix) && { let l = f.path.to_ascii_lowercase(); ALLOWED_EXT.iter().any(|e| l.ends_with(e)) || l.ends_with(".pf2") }).collect();
    let total: u64 = files.iter().map(|f| f.size).sum();
    if files.is_empty() { return Err("No theme files found.".into()); }
    if files.len() > 600 || total > 45 * 1024 * 1024 { return Err("This theme is too large to import (over 45 MB).".into()); }
    let (next, done) = (AtomicUsize::new(0), AtomicUsize::new(0));
    let out = Mutex::new(BTreeMap::new());
    let err = Mutex::new(None::<String>);
    std::thread::scope(|s| {
        for _ in 0..6 {
            s.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::SeqCst);
                if i >= files.len() || err.lock().unwrap().is_some() { break; }
                let f = &files[i];
                match get(&raw_url(&t.repo, &t.branch, &f.path), 17_000_000) {
                    Ok(b) => { out.lock().unwrap().insert(f.path[prefix.len()..].to_string(), b); progress(done.fetch_add(1, Ordering::SeqCst) + 1, files.len()); }
                    Err(e) => { *err.lock().unwrap() = Some(e); }
                }
            });
        }
    });
    if let Some(e) = err.into_inner().unwrap() { return Err(e); }
    Ok(out.into_inner().unwrap())
}
