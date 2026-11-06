//! Software renderer for theme previews (tiny-skia). Mirrors how GRUB's gfxmenu draws components.
use crate::pf2::{self, Pf2};
use crate::theme::{eval_len, unq, Assets, Comp, Doc};
use std::collections::HashMap;
use tiny_skia::{Color, FilterQuality, Paint, Pixmap, PixmapPaint, Rect as SkRect, Transform};

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Rect { pub x: i32, pub y: i32, pub w: i32, pub h: i32 }

pub const SAMPLE_ENTRIES: [(&str, &str); 5] = [
    ("Ubuntu", "ubuntu"), ("Advanced options for Ubuntu", "ubuntu"), ("Memory test (memtest86+)", "memtest"),
    ("Windows Boot Manager", "windows"), ("UEFI Firmware Settings", "efi"),
];

fn placeholder(t: &str) -> Option<&'static str> {
    Some(match t {
        "@TIMEOUT_NOTIFICATION_SHORT@" => "Booting in 5s",
        "@TIMEOUT_NOTIFICATION_MIDDLE@" => "Booting in 5 seconds",
        "@TIMEOUT_NOTIFICATION_LONG@" => "The highlighted entry will be executed automatically in 5s.",
        "@KEYMAP_SHORT@" => "enter: boot, e: options, c: cmd-line",
        "@KEYMAP_MIDDLE@" => "Enter: Boot, e: Edit Boot Options, c: GRUB Command-Line",
        "@KEYMAP_LONG@" => "Use the Up and Down keys to select which entry is highlighted. Press enter to boot the selected OS, e to edit the commands before booting or c for a command-line.",
        _ => return None,
    })
}

pub fn parse_color(v: &str, fallback: (u8, u8, u8)) -> (u8, u8, u8) {
    let s = unq(v).trim();
    if let Some(h) = s.strip_prefix('#') {
        let hx = |i: usize| u8::from_str_radix(h.get(i..i + 2)?, 16).ok();
        if h.len() == 3 {
            let d = |i: usize| u8::from_str_radix(&h[i..i + 1], 16).ok().map(|x| x * 17);
            if let (Some(r), Some(g), Some(b)) = (d(0), d(1), d(2)) { return (r, g, b); }
        } else if h.len() == 6 || h.len() == 8 {
            if let (Some(r), Some(g), Some(b)) = (hx(0), hx(2), hx(4)) { return (r, g, b); }
        }
    } else {
        let p: Vec<u8> = s.split(',').filter_map(|x| x.trim().parse().ok()).collect();
        if p.len() >= 3 { return (p[0], p[1], p[2]); }
    }
    fallback
}

pub struct DrawOpts { pub menu_sel: usize, pub progress: f32 }

#[derive(Default)]
pub struct Scene {
    pub images: HashMap<String, Pixmap>,
    pub fonts: HashMap<String, Pf2>,
    fallback: Option<Pf2>,
    seen: HashMap<String, (usize, usize)>,
}

fn decode(bytes: &[u8]) -> Option<Pixmap> {
    let img = image::load_from_memory(bytes).ok()?.to_rgba8();
    let (w, h) = img.dimensions();
    let mut data = img.into_raw();
    for px in data.chunks_exact_mut(4) {
        let a = px[3] as u32;
        for c in &mut px[..3] { *c = ((*c as u32 * a + 127) / 255) as u8; }
    }
    Pixmap::from_vec(data, tiny_skia::IntSize::from_wh(w, h)?)
}

fn load_fallback_font() -> Option<Pf2> {
    for p in ["/usr/share/grub/unicode.pf2", "/usr/share/grub2/unicode.pf2", "/boot/grub/fonts/unicode.pf2", "/boot/grub2/fonts/unicode.pf2", "/usr/share/grub/ascii.pf2"] {
        if let Ok(b) = std::fs::read(p) { if let Some(f) = pf2::parse(&b) { return Some(f); } }
    }
    None
}

/// Pixel-exact rectangle fill, clipped to the pixmap (no anti-aliasing: faster and crisp).
pub fn fill(dst: &mut Pixmap, x: i32, y: i32, w: i32, h: i32, c: (u8, u8, u8)) {
    let (x0, y0) = (x.max(0), y.max(0));
    let (x1, y1) = ((x + w).min(dst.width() as i32), (y + h).min(dst.height() as i32));
    if x1 <= x0 || y1 <= y0 { return; }
    if let Some(r) = SkRect::from_xywh(x0 as f32, y0 as f32, (x1 - x0) as f32, (y1 - y0) as f32) {
        let mut p = Paint::default();
        p.anti_alias = false;
        p.set_color(Color::from_rgba8(c.0, c.1, c.2, 255));
        dst.fill_rect(r, &p, Transform::identity(), None);
    }
}

fn blit(dst: &mut Pixmap, src: &Pixmap, x: i32, y: i32, w: i32, h: i32) {
    if w <= 0 || h <= 0 { return; }
    let (sw, sh) = (src.width() as f32, src.height() as f32);
    let same = w as f32 == sw && h as f32 == sh;
    let quality = if same || src.width() <= 2 || src.height() <= 2 { FilterQuality::Nearest } else { FilterQuality::Bilinear };
    let t = Transform::from_row(w as f32 / sw, 0.0, 0.0, h as f32 / sh, x as f32, y as f32);
    dst.draw_pixmap(0, 0, src.as_ref(), &PixmapPaint { quality, ..Default::default() }, t, None);
}

impl Scene {
    pub fn new() -> Self { Scene { fallback: load_fallback_font(), ..Default::default() } }

    /// Decode new or changed assets. Returns true when anything changed.
    pub fn sync(&mut self, assets: &Assets) -> bool {
        let mut changed = false;
        let gone: Vec<String> = self.seen.keys().filter(|k| !assets.contains_key(*k)).cloned().collect();
        for k in gone { self.seen.remove(&k); self.images.remove(&k); changed = true; }
        for (path, bytes) in assets {
            let id = (std::sync::Arc::as_ptr(bytes) as usize, bytes.len());
            if self.seen.get(path) == Some(&id) { continue; }
            self.seen.insert(path.clone(), id);
            changed = true;
            let l = path.to_ascii_lowercase();
            if l.ends_with(".pf2") { if let Some(f) = pf2::parse(bytes) { self.fonts.insert(f.name.clone(), f); } }
            else if let Some(p) = decode(bytes) { self.images.insert(path.clone(), p); }
        }
        changed
    }

    pub fn font_names(&self) -> Vec<String> { let mut v: Vec<_> = self.fonts.keys().cloned().collect(); v.sort(); v }

    fn font(&self, name: &str) -> Option<&Pf2> {
        if let Some(f) = self.fonts.get(name) { return Some(f); }
        let low = name.to_ascii_lowercase();
        self.fonts.iter().find(|(k, _)| k.to_ascii_lowercase() == low).map(|(_, f)| f).or(self.fallback.as_ref())
    }
    fn text_h(&self, name: &str) -> i32 { self.font(name).map(|f| f.height()).unwrap_or(18) }
    fn text_w(&self, name: &str, t: &str) -> i32 { self.font(name).map(|f| f.measure(t)).unwrap_or(t.chars().count() as i32 * 8) }
    fn text(&self, dst: &mut Pixmap, name: &str, t: &str, x: i32, y: i32, c: (u8, u8, u8)) {
        match self.font(name) {
            Some(f) => f.draw(dst, t, x, y, c),
            None => fill(dst, x, y + 4, self.text_w(name, t), 8, c), // no font anywhere: show a bar so layout stays visible
        }
    }
    fn label_text<'a>(&self, c: &'a Comp) -> String {
        let t = c.pu("text");
        placeholder(t).map(|s| s.to_string()).unwrap_or_else(|| t.replace("%02d", "05").replace("%d", "5"))
    }

    pub fn layout(&self, doc: &Doc) -> HashMap<u64, Rect> {
        let mut out = HashMap::new();
        self.place(&doc.root, Rect { x: 0, y: 0, w: doc.screen.0, h: doc.screen.1 }, 0, &mut out);
        out
    }

    fn place(&self, list: &[Comp], parent: Rect, flow: u8, out: &mut HashMap<u64, Rect>) {
        let mut cursor = 0;
        for c in list {
            let img = if c.ty == "image" { self.images.get(c.pu("file")) } else { None };
            let font = if c.pu("font").is_empty() { "Unifont Regular 16" } else { c.pu("font") };
            let mut w = eval_len(c.props.get("width").map(|s| s.as_str()), parent.w, -1);
            let mut h = eval_len(c.props.get("height").map(|s| s.as_str()), parent.h, -1);
            if w < 0 { w = match (img, c.ty.as_str()) { (Some(i), _) => i.width() as i32, (_, "label") => self.text_w(font, &self.label_text(c)), _ => parent.w }; }
            if h < 0 { h = match (img, c.ty.as_str()) { (Some(i), _) => i.height() as i32, (_, "label") => self.text_h(font), _ => parent.h }; }
            let mut x = parent.x + eval_len(c.props.get("left").map(|s| s.as_str()), parent.w, 0);
            let mut y = parent.y + eval_len(c.props.get("top").map(|s| s.as_str()), parent.h, 0);
            if flow == 1 { y = parent.y + cursor; cursor += h; }
            if flow == 2 { x = parent.x + cursor; cursor += w; }
            let r = Rect { x, y, w, h };
            out.insert(c.uid, r);
            if !c.children.is_empty() { self.place(&c.children, r, match c.ty.as_str() { "vbox" => 1, "hbox" => 2, _ => 0 }, out); }
        }
    }

    pub fn hit_test(&self, doc: &Doc, rects: &HashMap<u64, Rect>, x: i32, y: i32) -> Option<u64> {
        fn walk(list: &[Comp], rects: &HashMap<u64, Rect>, x: i32, y: i32, found: &mut Option<u64>) {
            for c in list {
                if c.hidden { continue; }
                if let Some(r) = rects.get(&c.uid) { if x >= r.x && y >= r.y && x <= r.x + r.w && y <= r.y + r.h { *found = Some(c.uid); } }
                walk(&c.children, rects, x, y, found);
            }
        }
        let mut f = None;
        walk(&doc.root, rects, x, y, &mut f);
        f
    }

    // ---------------------------------------------------------------- drawing
    pub fn draw(&self, dst: &mut Pixmap, doc: &Doc, rects: &HashMap<u64, Rect>, o: &DrawOpts) {
        let (sw, sh) = doc.screen;
        let g = |k: &str| doc.globals.get(k).map(|s| s.as_str()).unwrap_or("");
        let bg = parse_color(g("desktop-color"), (0, 0, 0));
        dst.fill(Color::from_rgba8(bg.0, bg.1, bg.2, 255));
        if let Some(img) = self.images.get(unq(g("desktop-image"))) { self.background(dst, img, sw, sh, unq(g("desktop-image-scale-method")), unq(g("desktop-image-h-align")), unq(g("desktop-image-v-align"))); }
        let title = unq(g("title-text"));
        if !title.is_empty() {
            let fname = if unq(g("title-font")).is_empty() { "Unifont Regular 16" } else { unq(g("title-font")) };
            self.text(dst, fname, title, (sw - self.text_w(fname, title)) / 2, 12, parse_color(g("title-color"), (255, 255, 255)));
        }
        fn walk(s: &Scene, dst: &mut Pixmap, list: &[Comp], rects: &HashMap<u64, Rect>, o: &DrawOpts) {
            for c in list {
                if c.hidden { continue; }
                if let Some(r) = rects.get(&c.uid) { s.comp(dst, c, *r, o); }
                walk(s, dst, &c.children, rects, o);
            }
        }
        walk(self, dst, &doc.root, rects, o);
    }

    fn background(&self, dst: &mut Pixmap, img: &Pixmap, w: i32, h: i32, mode: &str, ha: &str, va: &str) {
        let (iw, ih) = (img.width() as f32, img.height() as f32);
        let s = match mode { "crop" => (w as f32 / iw).max(h as f32 / ih), "fitwidth" => w as f32 / iw, "fitheight" => h as f32 / ih, _ => 0.0 };
        if s == 0.0 { blit(dst, img, 0, 0, w, h); return; }
        let (dw, dh) = ((iw * s) as i32, (ih * s) as i32);
        let dx = match ha { "left" => 0, "right" => w - dw, _ => (w - dw) / 2 };
        let dy = match va { "top" => 0, "bottom" => h - dh, _ => (h - dh) / 2 };
        blit(dst, img, dx, dy, dw, dh);
    }

    fn comp(&self, dst: &mut Pixmap, c: &Comp, r: Rect, o: &DrawOpts) {
        match c.ty.as_str() {
            "image" => if let Some(i) = self.images.get(c.pu("file")) { blit(dst, i, r.x, r.y, r.w, r.h); },
            "label" => {
                let f = if c.pu("font").is_empty() { "Unifont Regular 16" } else { c.pu("font") };
                let t = self.label_text(c);
                let tw = self.text_w(f, &t);
                let x = match c.pu("align") { "center" => r.x + (r.w - tw) / 2, "right" => r.x + r.w - tw, _ => r.x };
                self.text(dst, f, &t, x, r.y + (r.h - self.text_h(f)) / 2, parse_color(c.p("color"), (0, 0, 0)));
            }
            "boot_menu" => self.menu(dst, c, r, o),
            "progress_bar" => self.progress(dst, c, r, o),
            "circular_progress" => self.circular(dst, c, r, o),
            _ => {}
        }
    }

    fn nine(&self, dst: &mut Pixmap, pattern: &str, r: Rect) -> bool {
        if !pattern.contains('*') { return false; }
        let get = |s: &str| self.images.get(&pattern.replacen('*', s, 1));
        let [nw, n, ne, w, c, e, sw, s, se] = ["nw", "n", "ne", "w", "c", "e", "sw", "s", "se"].map(get);
        if ![nw, n, ne, w, c, e, sw, s, se].iter().any(|x| x.is_some()) { return false; }
        let dim = |a: Option<&Pixmap>| a.map(|p| (p.width() as i32, p.height() as i32)).unwrap_or((0, 0));
        let lw = dim(nw).0.max(dim(w).0).max(dim(sw).0);
        let rw = dim(ne).0.max(dim(e).0).max(dim(se).0);
        let th = dim(nw).1.max(dim(n).1).max(dim(ne).1);
        let bh = dim(sw).1.max(dim(s).1).max(dim(se).1);
        let (mw, mh) = (r.w - lw - rw, r.h - th - bh);
        let mut d = |i: Option<&Pixmap>, x: i32, y: i32, w: i32, h: i32| if let Some(i) = i { if w > 0 && h > 0 { blit(dst, i, x, y, w, h); } };
        d(c, r.x + lw, r.y + th, mw, mh);
        d(n, r.x + lw, r.y, mw, th); d(s, r.x + lw, r.y + r.h - bh, mw, bh);
        d(w, r.x, r.y + th, lw, mh); d(e, r.x + r.w - rw, r.y + th, rw, mh);
        d(nw, r.x, r.y, lw, th); d(ne, r.x + r.w - rw, r.y, rw, th);
        d(sw, r.x, r.y + r.h - bh, lw, bh); d(se, r.x + r.w - rw, r.y + r.h - bh, rw, bh);
        true
    }

    fn menu(&self, dst: &mut Pixmap, c: &Comp, r: Rect, o: &DrawOpts) {
        let ev = |k: &str, par: i32, d: i32| eval_len(c.props.get(k).map(|s| s.as_str()), par, d);
        let (ih, pad, sp) = (ev("item_height", r.h, 42), ev("item_padding", r.w, 14), ev("item_spacing", r.h, 16));
        let (iw, ihh, isp) = (ev("icon_width", r.w, 32), ev("icon_height", r.h, 32), ev("item_icon_space", r.w, 4));
        let f = if c.pu("item_font").is_empty() { "Unifont Regular 16" } else { c.pu("item_font") };
        let sf = if c.pu("selected_item_font").is_empty() { f } else { c.pu("selected_item_font") };
        let (col, scol) = (parse_color(c.p("item_color"), (128, 128, 128)), parse_color(c.p("selected_item_color"), (255, 255, 255)));
        let scroll = c.pu("scrollbar") == "true";
        self.nine(dst, c.pu("menu_pixmap_style"), r);
        let visible = ((r.h + sp) / (ih + sp).max(1)).max(1) as usize;
        let n = visible.min(SAMPLE_ENTRIES.len());
        let w = r.w - if scroll { ev("scrollbar_width", r.w, 16) } else { 0 };
        for (i, (label, class)) in SAMPLE_ENTRIES.iter().enumerate().take(n) {
            let sel = i == o.menu_sel % SAMPLE_ENTRIES.len();
            let row = Rect { x: r.x, y: r.y + i as i32 * (ih + sp), w, h: ih };
            self.nine(dst, c.pu(if sel { "selected_item_pixmap_style" } else { "item_pixmap_style" }), row);
            let mut tx = row.x + pad;
            if iw > 0 { if let Some(icon) = self.images.get(&format!("icons/{class}.png")) { blit(dst, icon, tx, row.y + (ih - ihh) / 2, iw, ihh); } }
            tx += iw + if iw > 0 { isp } else { 0 };
            let fname = if sel { sf } else { f };
            self.text(dst, fname, label, tx, row.y + (ih - self.text_h(fname)) / 2, if sel { scol } else { col });
        }
    }

    fn progress(&self, dst: &mut Pixmap, c: &Comp, r: Rect, o: &DrawOpts) {
        let fw = (r.w as f32 * o.progress).round() as i32;
        let (bs, hs) = (c.pu("bar_style"), c.pu("highlight_style"));
        if !bs.is_empty() || !hs.is_empty() {
            if !bs.is_empty() { self.nine(dst, bs, r); }
            if !hs.is_empty() && fw > 0 { self.nine(dst, hs, Rect { w: fw, ..r }); }
        } else {
            fill(dst, r.x, r.y, r.w, r.h, parse_color(c.p("bg_color"), (255, 255, 255)));
            fill(dst, r.x, r.y, fw, r.h, parse_color(c.p("fg_color"), (0, 0, 0)));
            let b = parse_color(c.p("border_color"), (0, 0, 0));
            fill(dst, r.x, r.y, r.w, 1, b); fill(dst, r.x, r.y + r.h - 1, r.w, 1, b);
            fill(dst, r.x, r.y, 1, r.h, b); fill(dst, r.x + r.w - 1, r.y, 1, r.h, b);
        }
        if c.pu("show_text") != "false" && !c.p("text").is_empty() {
            let f = if c.pu("font").is_empty() { "Unifont Regular 16" } else { c.pu("font") };
            let t = self.label_text(c);
            self.text(dst, f, &t, r.x + (r.w - self.text_w(f, &t)) / 2, r.y + (r.h - self.text_h(f)) / 2, parse_color(c.p("text_color"), (0, 0, 0)));
        }
    }

    fn circular(&self, dst: &mut Pixmap, c: &Comp, r: Rect, o: &DrawOpts) {
        let (cx, cy) = (r.x + r.w / 2, r.y + r.h / 2);
        if let Some(cb) = self.images.get(c.pu("center_bitmap")) { blit(dst, cb, cx - cb.width() as i32 / 2, cy - cb.height() as i32 / 2, cb.width() as i32, cb.height() as i32); }
        let Some(tb) = self.images.get(c.pu("tick_bitmap")) else { return };
        let ticks = eval_len(c.props.get("num_ticks").map(|s| s.as_str()), 100, 64).max(1);
        let start = eval_len(c.props.get("start_angle").map(|s| s.as_str()), 256, -64) as f32;
        let vanish = c.pu("ticks_disappear") == "true";
        let lit = (ticks as f32 * o.progress).round() as i32;
        let (tw, th) = (tb.width() as i32, tb.height() as i32);
        let radius = (r.w.min(r.h) / 2 - tw.max(th) / 2) as f32;
        for i in 0..ticks {
            if if vanish { i < lit } else { i >= lit } { continue; }
            let a = (start + i as f32 * 256.0 / ticks as f32) * std::f32::consts::TAU / 256.0;
            blit(dst, tb, cx + (a.cos() * radius) as i32 - tw / 2, cy + (a.sin() * radius) as i32 - th / 2, tw, th);
        }
    }
}
