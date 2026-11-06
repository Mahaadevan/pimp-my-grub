//! Render a theme folder to a PNG with the same renderer the editor uses:  cargo run -p pimp-my-grub-core --example preview -- <theme-dir> <out.png> [WxH]
use pimp_my_grub_core::{editor::Editor, installer};
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let files = installer::read_dir_files(std::path::Path::new(&a[1])).expect("read theme");
    let mut e = Editor::new();
    e.load_files(&files, "preview").expect("parse theme");
    if let Some(sz) = a.get(3).and_then(|s| s.split_once('x')) { e.doc.screen = (sz.0.parse().unwrap(), sz.1.parse().unwrap()); }
    e.fit(1280, 760);
    let (px, w, h) = e.render_view(1280, 760).expect("render");
    let img = image::RgbaImage::from_raw(w, h, px.to_vec()).unwrap();
    img.save(&a[2]).unwrap();
}
