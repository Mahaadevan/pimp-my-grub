//! GRUB "pixmap styles": a style is nine PNG slices named <prefix>_nw/n/ne/w/c/e/sw/s/se.png that GRUB stretches around a
//! box. This module makes such a set from a few parameters (fill, gradient, rounded corners, border, opacity), or cuts
//! one out of an ordinary picture, so complex themes can be built from scratch.
use crate::render::parse_color;
use image::{ImageFormat, RgbaImage};
use std::collections::BTreeMap;
use tiny_skia::{Color, FillRule, GradientStop, LinearGradient, Paint, PathBuilder, Pixmap, Point, SpreadMode, Stroke, Transform};

#[derive(Clone, Debug)]
pub struct StyleSpec {
    pub fill: String,
    pub fill2: String,          // empty = solid; otherwise a vertical gradient fill -> fill2
    pub opacity: u8,            // fill opacity, 0-100
    pub radius: u32,            // corner radius in px (0 = square)
    pub border_width: u32,      // px (0 = none)
    pub border: String,
    pub border_opacity: u8,     // 0-100
}
impl Default for StyleSpec {
    fn default() -> Self { StyleSpec { fill: "#2f7fd6".into(), fill2: String::new(), opacity: 100, radius: 8, border_width: 0, border: "#ffffff".into(), border_opacity: 100 } }
}

const SLICES: [&str; 9] = ["nw", "n", "ne", "w", "c", "e", "sw", "s", "se"];

fn png(img: &RgbaImage) -> Vec<u8> {
    let mut out = std::io::Cursor::new(Vec::new());
    let _ = img.write_to(&mut out, ImageFormat::Png);
    out.into_inner()
}
fn rgba_of(p: &Pixmap) -> RgbaImage {
    let mut img = RgbaImage::new(p.width(), p.height());
    for (i, px) in p.data().chunks_exact(4).enumerate() {
        let a = px[3] as u32;
        let un = |c: u8| if a == 0 { 0 } else { ((c as u32 * 255 + a / 2) / a).min(255) as u8 };
        img.put_pixel((i as u32) % p.width(), (i as u32) / p.width(), image::Rgba([un(px[0]), un(px[1]), un(px[2]), a as u8]));
    }
    img
}
fn crop(img: &RgbaImage, x: u32, y: u32, w: u32, h: u32) -> RgbaImage { image::imageops::crop_imm(img, x, y, w.max(1), h.max(1)).to_image() }

fn rounded_rect(x: f32, y: f32, w: f32, h: f32, r: f32) -> Option<tiny_skia::Path> {
    let r = r.min(w / 2.0).min(h / 2.0).max(0.0);
    let k = r * 0.552_284_75;
    let mut pb = PathBuilder::new();
    pb.move_to(x + r, y);
    pb.line_to(x + w - r, y); pb.cubic_to(x + w - r + k, y, x + w, y + r - k, x + w, y + r);
    pb.line_to(x + w, y + h - r); pb.cubic_to(x + w, y + h - r + k, x + w - r + k, y + h, x + w - r, y + h);
    pb.line_to(x + r, y + h); pb.cubic_to(x + r - k, y + h, x, y + h - r + k, x, y + h - r);
    pb.line_to(x, y + r); pb.cubic_to(x, y + r - k, x + r - k, y, x + r, y);
    pb.close();
    pb.finish()
}

/// Render the nine slices (keys "nw".."se") of a style.
pub fn render_slices(spec: &StyleSpec) -> BTreeMap<&'static str, Vec<u8>> {
    let k = spec.radius.max(spec.border_width).clamp(1, 96);
    let s = 2 * k + 2;                        // canvas: two corners plus a 2x2 middle
    let sf = s as f32;
    let col = |hex: &str, op: u8| { let (r, g, b) = parse_color(hex, (255, 255, 255)); Color::from_rgba8(r, g, b, (op.min(100) as f32 * 2.55).round() as u8) };
    let fill_a = col(&spec.fill, spec.opacity);
    let fill_b = if spec.fill2.is_empty() { fill_a } else { col(&spec.fill2, spec.opacity) };
    let mut pix = Pixmap::new(s, s).expect("size");
    if let Some(path) = rounded_rect(0.0, 0.0, sf, sf, spec.radius as f32) {
        let mut paint = Paint::default(); paint.anti_alias = true;
        if spec.fill2.is_empty() { paint.set_color(fill_a); }
        else if let Some(g) = LinearGradient::new(Point::from_xy(0.0, 0.0), Point::from_xy(0.0, sf), vec![GradientStop::new(0.0, fill_a), GradientStop::new(1.0, fill_b)], SpreadMode::Pad, Transform::identity()) { paint.shader = g; }
        pix.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);
        if spec.border_width > 0 {
            let bw = spec.border_width as f32;
            if let Some(bp) = rounded_rect(bw / 2.0, bw / 2.0, sf - bw, sf - bw, (spec.radius as f32 - bw / 2.0).max(0.0)) {
                let mut sp = Paint::default(); sp.anti_alias = true; sp.set_color(col(&spec.border, spec.border_opacity));
                pix.stroke_path(&bp, &sp, &Stroke { width: bw, ..Default::default() }, Transform::identity(), None);
            }
        }
    }
    let img = rgba_of(&pix);
    let mut out = BTreeMap::new();
    let mut out_local: Vec<(&'static str, RgbaImage)> = vec![
        ("nw", crop(&img, 0, 0, k, k)), ("ne", crop(&img, s - k, 0, k, k)), ("sw", crop(&img, 0, s - k, k, k)), ("se", crop(&img, s - k, s - k, k, k)),
        ("n", crop(&img, k, 0, 1, k)), ("s", crop(&img, k, s - k, 1, k)), ("w", crop(&img, 0, k, k, 1)), ("e", crop(&img, s - k, k, k, 1)),
    ];
    // the centre carries the gradient: a 1 x 64 strip that GRUB stretches to the box
    let mut centre = RgbaImage::new(1, 64);
    for y in 0..64u32 {
        let t = y as f32 / 63.0;
        let mix = |a: f32, b: f32| a + (b - a) * t;
        centre.put_pixel(0, y, image::Rgba([(mix(fill_a.red(), fill_b.red()) * 255.0).round() as u8, (mix(fill_a.green(), fill_b.green()) * 255.0).round() as u8, (mix(fill_a.blue(), fill_b.blue()) * 255.0).round() as u8, (mix(fill_a.alpha(), fill_b.alpha()) * 255.0).round() as u8]));
    }
    // with a border the centre must not be the border colour; edge strips already hold it
    out_local.push(("c", centre));
    for (n, im) in out_local { out.insert(n, png(&im)); }
    out
}

/// Cut a picture into the nine slices. `l, t, r, b` are the sizes of the fixed corners in pixels.
pub fn slice_image(bytes: &[u8], l: u32, t: u32, r: u32, b: u32) -> Result<BTreeMap<&'static str, Vec<u8>>, String> {
    let img = image::load_from_memory(bytes).map_err(|e| e.to_string())?.to_rgba8();
    let (w, h) = img.dimensions();
    if l + r >= w || t + b >= h { return Err(format!("the corners ({l}+{r} wide, {t}+{b} tall) do not fit in a {w}x{h} picture")); }
    let (mw, mh) = (w - l - r, h - t - b);
    let mut out = BTreeMap::new();
    let parts: [(&'static str, (u32, u32, u32, u32)); 9] = [
        ("nw", (0, 0, l, t)), ("n", (l, 0, mw, t)), ("ne", (w - r, 0, r, t)), ("w", (0, t, l, mh)), ("c", (l, t, mw, mh)), ("e", (w - r, t, r, mh)),
        ("sw", (0, h - b, l, b)), ("s", (l, h - b, mw, b)), ("se", (w - r, h - b, r, b)),
    ];
    for (n, (x, y, cw, ch)) in parts { if cw > 0 && ch > 0 { out.insert(n, png(&crop(&img, x, y, cw, ch))); } }
    Ok(out)
}

/// A single rounded box of exactly `w` x `h` px (for a card that is placed as an ordinary image).
pub fn box_png(spec: &StyleSpec, w: u32, h: u32) -> Vec<u8> {
    let col = |hex: &str, op: u8| { let (r, g, b) = parse_color(hex, (255, 255, 255)); Color::from_rgba8(r, g, b, (op.min(100) as f32 * 2.55).round() as u8) };
    let (w, h) = (w.clamp(4, 2000), h.clamp(4, 2000));
    let mut pix = Pixmap::new(w, h).expect("size");
    if let Some(path) = rounded_rect(0.0, 0.0, w as f32, h as f32, spec.radius as f32) {
        let mut paint = Paint::default(); paint.anti_alias = true;
        let (a, b) = (col(&spec.fill, spec.opacity), if spec.fill2.is_empty() { col(&spec.fill, spec.opacity) } else { col(&spec.fill2, spec.opacity) });
        if spec.fill2.is_empty() { paint.set_color(a); }
        else if let Some(g) = LinearGradient::new(Point::from_xy(0.0, 0.0), Point::from_xy(0.0, h as f32), vec![GradientStop::new(0.0, a), GradientStop::new(1.0, b)], SpreadMode::Pad, Transform::identity()) { paint.shader = g; }
        pix.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);
        if spec.border_width > 0 {
            let bw = spec.border_width as f32;
            if let Some(bp) = rounded_rect(bw / 2.0, bw / 2.0, w as f32 - bw, h as f32 - bw, (spec.radius as f32 - bw / 2.0).max(0.0)) {
                let mut sp = Paint::default(); sp.anti_alias = true; sp.set_color(col(&spec.border, spec.border_opacity));
                pix.stroke_path(&bp, &sp, &Stroke { width: bw, ..Default::default() }, Transform::identity(), None);
            }
        }
    }
    png(&rgba_of(&pix))
}

pub fn slice_names() -> [&'static str; 9] { SLICES }
