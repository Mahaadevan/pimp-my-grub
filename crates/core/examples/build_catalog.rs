//! Index every repo in data/catalog.json and write the themes back, so the app opens with a full store and no API calls.
//!   GITHUB_TOKEN=... cargo run -p pimp-my-grub-core --example build_catalog
use pimp_my_grub_core::store::{catalog, index_repo};
fn main() {
    let (repos, _) = catalog();
    let (mut kept, mut themes) = (vec![], vec![]);
    for r in repos {
        match index_repo(&r) {
            Ok(t) if !t.is_empty() => { eprintln!("{} -> {} themes", r.repo, t.len()); kept.push(r); themes.extend(t); }
            Ok(_) => eprintln!("{} has no theme.txt, skipped", r.repo),
            Err(e) => eprintln!("{} skipped: {e}", r.repo),
        }
    }
    let out = serde_json::json!({ "repos": kept, "themes": themes });
    std::fs::write("data/catalog.json", serde_json::to_vec_pretty(&out).unwrap()).unwrap();
}
