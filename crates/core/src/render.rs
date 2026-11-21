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

fn placeholder(t: &str, secs: i32) -> Option<String> {
    Some(match t {
        "@TIMEOUT_NOTIFICATION_SHORT@" => format!("Booting in {secs}s"),
        "@TIMEOUT_NOTIFICATION_MIDDLE@" => format!("Booting in {secs} seconds"),
        "@TIMEOUT_NOTIFICATION_LONG@" => format!("The highlighted entry will be executed automatically in {secs}s."),
        "@KEYMAP_SHORT@" => "enter: boot, e: options, c: cmd-line".into(),
        "@KEYMAP_MIDDLE@" => "Enter: Boot, e: Edit Boot Options, c: GRUB Command-Line".into(),
        "@KEYMAP_LONG@" => "Use the Up and Down keys to select which entry is highlighted. Press enter to boot the selected OS, e to edit the commands before booting or c for a command-line.".into(),
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

/// The nine pieces of a GRUB pixmap style, in the order GRUB names them.
const PIECES: [&str; 9] = ["nw", "n", "ne", "w", "c", "e", "sw", "s", "se"];

/// Row geometry of a boot menu in theme units: where the rows start, how tall they are, where a row's text and icon go,
/// how many fit and which one is first. Filled in by `Scene::menu_layout`, which the renderer and the preview's hit test
/// both use, so a click always lands on the row it is drawn on.
pub struct MenuLayout {
    pub x: i32, pub y: i32, pub w: i32, pub ih: i32, pub vs: i32,
    pub first: usize, pub visible: usize,
    pub text_x: i32, pub icon_x: i32, pub icon_w: i32, pub icon_h: i32,
    pub item_off: i32, pub sel_off: i32,
    pub item_pad_top: i32, pub sel_pad_top: i32,
    pub scroll: bool, pub scrollbar: Rect,
}

pub struct Scene {
    /// Entries the boot menu shows: (title, class). Empty = a small sample list.
    pub entries: Vec<(String, String)>,
    /// The countdown items (id __timeout__) disappear after a key press in the live preview, as in GRUB.
    pub hide_timeout: bool,
    /// Seconds left on the countdown (shown by `%d` / `%02d` and the @TIMEOUT_NOTIFICATION_*@ texts).
    pub secs: i32,
    pub images: HashMap<String, Pixmap>,
    pub fonts: HashMap<String, Pf2>,
    fallback: Option<Pf2>,
    seen: HashMap<String, (usize, usize)>,
    /// Render scale. 1.0 draws the theme at its own resolution, exactly as GRUB does; 2.0 draws every part twice as
    /// large, which is what the editor and the full-screen preview ask for when they are zoomed in, so the result is
    /// re-rendered sharp instead of being an enlarged copy of the 1:1 raster.
    pub scale: f32,
}

impl Default for Scene {
    fn default() -> Self {
        Scene { entries: vec![], hide_timeout: false, secs: 5, images: HashMap::new(), fonts: HashMap::new(), fallback: None, seen: HashMap::new(), scale: 1.0 }
    }
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

/// Compact built-in PF2 (Latin, Greek, Cyrillic; GNU Unifont, 16 px). Used when no GRUB font is installed, so previews
/// always show real text instead of grey bars (AppImage, Flatpak, or a machine without GRUB).
const BUILTIN_FONT: &[u8] = include_bytes!("../assets/fallback.pf2");

fn load_fallback_font() -> Option<Pf2> {
    // Prefer the system's full Unicode font when GRUB is installed; otherwise use the built-in one.
    for p in ["/usr/share/grub/unicode.pf2", "/usr/share/grub2/unicode.pf2", "/boot/grub/fonts/unicode.pf2", "/boot/grub2/fonts/unicode.pf2", "/usr/share/grub/ascii.pf2"] {
        if let Ok(b) = std::fs::read(p) { if let Some(f) = pf2::parse(&b) { return Some(f); } }
    }
    pf2::parse(BUILTIN_FONT)
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
    // Enlarged (the editor zoomed in): copy the pixels without smoothing, so the picture stays crisp instead of turning
    // into mush. Shrunk: one bilinear pass averages neighbouring pixels and keeps the small picture free of shimmer.
    let shrunk = w < src.width() as i32 || h < src.height() as i32;
    let quality = if shrunk && !same && src.width() > 2 && src.height() > 2 { FilterQuality::Bilinear } else { FilterQuality::Nearest };
    let t = Transform::from_row(w as f32 / sw, 0.0, 0.0, h as f32 / sh, x as f32, y as f32);
    dst.draw_pixmap(0, 0, src.as_ref(), &PixmapPaint { quality, ..Default::default() }, t, None);
}

impl Scene {
    pub fn new() -> Self { Scene { fallback: load_fallback_font(), ..Default::default() } }

    /// Theme units to render pixels.
    fn s(&self, v: i32) -> i32 { (v as f32 * self.scale).round() as i32 }
    fn sr(&self, r: Rect) -> Rect { Rect { x: self.s(r.x), y: self.s(r.y), w: self.s(r.w), h: self.s(r.h) } }

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
    /// Pixel size of a picture as it arrives from the theme (used to guess the resolution a theme was made for).
    pub fn image_size(&self, name: &str) -> Option<(u32, u32)> {
        self.images.get(name).map(|p| (p.width(), p.height()))
    }

    fn font(&self, name: &str) -> Option<&Pf2> {
        if let Some(f) = self.fonts.get(name) { return Some(f); }
        let low = name.to_ascii_lowercase();
        self.fonts.iter().find(|(k, _)| k.to_ascii_lowercase() == low).map(|(_, f)| f).or(self.fallback.as_ref())
    }
    fn text_h(&self, name: &str) -> i32 { self.font(name).map(|f| f.height()).unwrap_or(18) }
    fn text_w(&self, name: &str, t: &str) -> i32 { self.font(name).map(|f| f.measure(t)).unwrap_or(t.chars().count() as i32 * 8) }
    fn text(&self, dst: &mut Pixmap, name: &str, t: &str, x: i32, y: i32, c: (u8, u8, u8)) {
        match self.font(name) {
            Some(f) => f.draw_scaled(dst, t, x, y, c, self.scale),
            None => fill(dst, self.s(x), self.s(y + 4), self.s(self.text_w(name, t)), self.s(8).max(1), c), // no font anywhere: show a bar so layout stays visible
        }
    }
    fn label_text(&self, c: &Comp) -> String {
        let t = c.pu("text");
        placeholder(t, self.secs).unwrap_or_else(|| t.replace("%02d", &format!("{:02}", self.secs)).replace("%d", &self.secs.to_string()))
    }
    fn entry_list(&self) -> Vec<(String, String)> {
        if self.entries.is_empty() { SAMPLE_ENTRIES.iter().map(|(a, b)| (a.to_string(), b.to_string())).collect() } else { self.entries.clone() }
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

    /// One piece of a style (`pattern` carries the `*`), if the theme ships it.
    fn piece<'a>(&'a self, pattern: &str, name: &str) -> Option<&'a Pixmap> {
        if pattern.contains('*') { self.images.get(&pattern.replacen('*', name, 1)) } else { None }
    }

    /// Whether the theme ships any piece of this style: GRUB draws a box even when only its centre exists.
    fn has_style(&self, pattern: &str) -> bool {
        PIECES.iter().any(|p| self.piece(pattern, p).is_some())
    }

    /// Padding a style puts around its content: the width of the west/east pieces and the height of the north/south
    /// pieces, exactly like GRUB's image box (a missing piece adds nothing).
    fn style_pads(&self, pattern: &str) -> (i32, i32, i32, i32) {
        let dim = |n: &str| self.piece(pattern, n).map(|i| (i.width() as i32, i.height() as i32)).unwrap_or((0, 0));
        let (nw, ne, sw, se, w, e, n, s) = (dim("nw"), dim("ne"), dim("sw"), dim("se"), dim("w"), dim("e"), dim("n"), dim("s"));
        (w.0.max(nw.0).max(sw.0), e.0.max(ne.0).max(se.0), n.1.max(nw.1).max(ne.1), s.1.max(sw.1).max(se.1))
    }

    /// Where a boot menu puts its rows, following GRUB's list widget (`gui_list.c`): the row area is inset by the menu
    /// style's border and by `item_padding`; a row is as tall as its text unless `item_height` says otherwise, with
    /// `item_spacing` between rows; and the text starts past the widest west piece of the plain and selected row styles
    /// (that is why the text of a theme with a decorated highlight does not begin at the row's edge) plus
    /// `icon_width + item_icon_space`.
    pub fn menu_layout(&self, c: &Comp, r: Rect, sel: usize, count: usize) -> MenuLayout {
        let ev = |k: &str, par: i32, d: i32| eval_len(c.props.get(k).map(|s| s.as_str()), par, d);
        let font = if c.pu("item_font").is_empty() { "Unifont Regular 16" } else { c.pu("item_font") };
        let ih = ev("item_height", r.h, self.text_h(font)).max(1);
        let vs = ev("item_spacing", r.h, 0);
        let boxpad = ev("item_padding", r.w, 0);
        let (ml, mr, mt, mb) = self.style_pads(c.pu("menu_pixmap_style"));
        let (il, _, it, ib) = self.style_pads(c.pu("item_pixmap_style"));
        let (sl, _, st, sb) = self.style_pads(c.pu("selected_item_pixmap_style"));
        // Every row is indented by the widest west piece and pushed down by the tallest top piece of the two row styles,
        // so a plain row and the selected row put their text on the same column and line.
        let (left, top, bottom) = (il.max(sl), it.max(st), ib.max(sb));
        let total = count.max(1);
        let room = r.h - 2 * boxpad - top - bottom - mt - mb;
        let visible = (((room + vs) / (ih + vs).max(1)).max(1) as usize).min(total);
        let sel = sel % total;
        let first = if sel >= visible { sel + 1 - visible } else { 0 };   // keep the selected row in view, like GRUB

        // The scroll bar sits in the menu style's east or west pad when the theme picks a side, and in a column of its
        // own on the right otherwise; only that last case takes room away from the rows.
        let (sbw, slp, srp) = (ev("scrollbar_width", r.w, 16), ev("scrollbar_left_pad", r.w, 2), ev("scrollbar_right_pad", r.w, 0));
        let slice = c.pu("scrollbar_slice");
        let scroll = c.pu("scrollbar") != "false" && total > visible
            && (self.has_style(c.pu("scrollbar_frame")) || self.has_style(c.pu("scrollbar_thumb")));
        let (mut cx, mut cw) = (r.x + ml, r.w - ml - mr);
        match slice {
            "west" => { cx += srp; cw -= srp; }
            "east" => cw -= slp,
            _ => if scroll { cw -= sbw + slp + srp },
        }
        let (tp, bp) = (ev("scrollbar_top_pad", r.h, 0), ev("scrollbar_bottom_pad", r.h, 0));
        let (ty, th) = (r.y + mt + tp, (r.h - mt - mb - tp - bp).max(1));
        let bar = |x: i32, w: i32| Rect { x, y: ty, w: w.max(1), h: th };
        let scrollbar = match slice {
            "west" => if ml > sbw { bar(r.x + ml - sbw, sbw) } else { bar(r.x, ml) },
            "east" => bar(r.x + r.w - mr, mr),
            _ => bar(r.x + r.w - mr - sbw - srp, sbw),
        };

        let x = cx + boxpad;
        let (icon_w, icon_h) = (ev("icon_width", r.w, 0), ev("icon_height", r.h, ih));
        MenuLayout {
            x, y: r.y + mt + boxpad, w: (cw - 2 * boxpad).max(1), ih, vs, first, visible,
            text_x: x + left + icon_w + ev("item_icon_space", r.w, 0), icon_x: x + left, icon_w, icon_h,
            // GRUB draws a row's box from the top of the row area, so a style with a taller top piece rides up.
            item_off: top - it, sel_off: top - st, item_pad_top: it, sel_pad_top: st,
            scroll, scrollbar,
        }
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
            let tw = self.text_w(fname, title);
            self.text(dst, fname, title, (sw - tw) / 2, 12, parse_color(g("title-color"), (255, 255, 255)));
        }
        fn walk(s: &Scene, dst: &mut Pixmap, list: &[Comp], rects: &HashMap<u64, Rect>, o: &DrawOpts) {
            for c in list {
                if c.hidden || (s.hide_timeout && c.pu("id") == "__timeout__") { continue; }   // GRUB removes the countdown once a key is pressed
                if let Some(r) = rects.get(&c.uid) { s.comp(dst, c, *r, o); }
                walk(s, dst, &c.children, rects, o);
            }
        }
        walk(self, dst, &doc.root, rects, o);
    }

    fn background(&self, dst: &mut Pixmap, img: &Pixmap, w: i32, h: i32, mode: &str, ha: &str, va: &str) {
        let (iw, ih) = (img.width() as f32, img.height() as f32);
        let s = match mode {
            "crop" => (w as f32 / iw).max(h as f32 / ih),
            "fitwidth" => w as f32 / iw,
            "fitheight" => h as f32 / ih,
            "padding" => (w as f32 / iw).min(h as f32 / ih),   // fit inside, keep the aspect ratio (GRUB's "padding")
            _ => 0.0,                                          // stretch, GRUB's default
        };
        if s == 0.0 { blit(dst, img, 0, 0, self.s(w), self.s(h)); return; }
        let (dw, dh) = ((iw * s) as i32, (ih * s) as i32);
        let dx = match ha { "left" => 0, "right" => w - dw, _ => (w - dw) / 2 };
        let dy = match va { "top" => 0, "bottom" => h - dh, _ => (h - dh) / 2 };
        blit(dst, img, self.s(dx), self.s(dy), self.s(dw), self.s(dh));
    }

    fn comp(&self, dst: &mut Pixmap, c: &Comp, r: Rect, o: &DrawOpts) {
        match c.ty.as_str() {
            "image" => if let Some(i) = self.images.get(c.pu("file")) { blit(dst, i, self.s(r.x), self.s(r.y), self.s(r.w), self.s(r.h)); },
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
        if !self.has_style(pattern) { return false; }
        let get = |s: &str| self.images.get(&pattern.replacen('*', s, 1));
        let [nw, n, ne, w, c, e, sw, s, se] = PIECES.map(get);
        let dim = |a: Option<&Pixmap>| a.map(|p| (p.width() as i32, p.height() as i32)).unwrap_or((0, 0));
        let (lw, rw) = (self.s(dim(nw).0.max(dim(w).0).max(dim(sw).0)), self.s(dim(ne).0.max(dim(e).0).max(dim(se).0)));
        let (th, bh) = (self.s(dim(nw).1.max(dim(n).1).max(dim(ne).1)), self.s(dim(sw).1.max(dim(s).1).max(dim(se).1)));
        let r = self.sr(r);
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
        let f = if c.pu("item_font").is_empty() { "Unifont Regular 16" } else { c.pu("item_font") };
        let sf = if c.pu("selected_item_font").is_empty() { f } else { c.pu("selected_item_font") };
        let (col, scol) = (parse_color(c.p("item_color"), (128, 128, 128)), parse_color(c.p("selected_item_color"), (255, 255, 255)));
        let entries = self.entry_list();
        let total = entries.len().max(1);
        let lay = self.menu_layout(c, r, o.menu_sel, entries.len());
        let sel_i = o.menu_sel % total;
        self.nine(dst, c.pu("menu_pixmap_style"), r);
        for (row_i, (label, class)) in entries.iter().enumerate().skip(lay.first).take(lay.visible) {
            let sel = row_i == sel_i;
            let y = lay.y + (row_i - lay.first) as i32 * (lay.ih + lay.vs);
            let row = Rect { x: lay.x, y, w: lay.w, h: lay.ih };
            let off = if sel { lay.sel_off } else { lay.item_off };
            self.nine(dst, c.pu(if sel { "selected_item_pixmap_style" } else { "item_pixmap_style" }), Rect { y: y + off, ..row });
            let top = if sel { lay.sel_pad_top } else { lay.item_pad_top };
            if lay.icon_w > 0 {
                if let Some(icon) = self.images.get(&format!("icons/{class}.png")) {
                    blit(dst, icon, self.s(lay.icon_x), self.s(y + top + (lay.ih - lay.icon_h) / 2), self.s(lay.icon_w), self.s(lay.icon_h));
                }
            }
            let fname = if sel { sf } else { f };
            self.text(dst, fname, label, lay.text_x, y + top + (lay.ih - self.text_h(fname)) / 2, if sel { scol } else { col });
        }
        if lay.scroll {
            let frame = lay.scrollbar;
            let th = ((frame.h as i64 * lay.visible as i64 / total as i64) as i32).max(8).min(frame.h);
            let thumb = Rect { x: frame.x, y: frame.y + ((frame.h - th) as i64 * lay.first as i64 / (total - lay.visible).max(1) as i64) as i32, w: frame.w, h: th };
            let plain = |dst: &mut Pixmap, rr: Rect, col: (u8, u8, u8)| { let rr = self.sr(rr); fill(dst, rr.x, rr.y, rr.w.max(1), rr.h.max(1), col) };
            if !self.nine(dst, c.pu("scrollbar_frame"), frame) { plain(dst, frame, (44, 48, 56)); }
            if !self.nine(dst, c.pu("scrollbar_thumb"), thumb) { plain(dst, thumb, (150, 156, 168)); }
        }
    }

    fn progress(&self, dst: &mut Pixmap, c: &Comp, r: Rect, o: &DrawOpts) {
        let fw = (r.w as f32 * o.progress).round() as i32;
        let (bs, hs) = (c.pu("bar_style"), c.pu("highlight_style"));
        if !bs.is_empty() || !hs.is_empty() {
            if !bs.is_empty() { self.nine(dst, bs, r); }
            if !hs.is_empty() && fw > 0 { self.nine(dst, hs, Rect { w: fw, ..r }); }
        } else {
            let (x, y, w, h) = (self.s(r.x), self.s(r.y), self.s(r.w), self.s(r.h));
            let t = self.s(1).max(1);
            fill(dst, x, y, w, h, parse_color(c.p("bg_color"), (255, 255, 255)));
            fill(dst, x, y, self.s(fw), h, parse_color(c.p("fg_color"), (0, 0, 0)));
            let b = parse_color(c.p("border_color"), (0, 0, 0));
            fill(dst, x, y, w, t, b); fill(dst, x, y + h - t, w, t, b);
            fill(dst, x, y, t, h, b); fill(dst, x + w - t, y, t, h, b);
        }
        if c.pu("show_text") != "false" && !c.p("text").is_empty() {
            let f = if c.pu("font").is_empty() { "Unifont Regular 16" } else { c.pu("font") };
            let t = self.label_text(c);
            self.text(dst, f, &t, r.x + (r.w - self.text_w(f, &t)) / 2, r.y + (r.h - self.text_h(f)) / 2, parse_color(c.p("text_color"), (0, 0, 0)));
        }
    }

    fn circular(&self, dst: &mut Pixmap, c: &Comp, r: Rect, o: &DrawOpts) {
        let (cx, cy) = (r.x + r.w / 2, r.y + r.h / 2);
        if let Some(cb) = self.images.get(c.pu("center_bitmap")) {
            blit(dst, cb, self.s(cx - cb.width() as i32 / 2), self.s(cy - cb.height() as i32 / 2), self.s(cb.width() as i32), self.s(cb.height() as i32));
        }
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
            blit(dst, tb, self.s(cx + (a.cos() * radius) as i32 - tw / 2), self.s(cy + (a.sin() * radius) as i32 - th / 2), self.s(tw), self.s(th));
        }
    }
}
