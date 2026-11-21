//! Temporary check: how the editor canvas renders the theme at different zooms.
use style_my_grub_core::editor::Editor;
fn main() {
    let mut e = Editor::new();
    e.load_sample().expect("sample");
    for z in [0.35f64, 1.0, 2.0, 3.5] {
        e.zoom_to(z, 900, 560);
        let (px, w, h) = e.render_view(900, 560).expect("render");
        image::RgbaImage::from_raw(w, h, px.to_vec()).unwrap().save(format!("/tmp/zoom-{z}.png")).unwrap();
        println!("z={z} zoom={}", e.zoom());
    }
}
