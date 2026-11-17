//! Editor operations beyond the basics: clipboard, stacking order, grouping, alignment, styles made from parameters, and the
//! preset library (ready-made menus, labels, panels, progress bars, spinners and groups).
use crate::editor::*;
use crate::render::{parse_color, Rect};
use crate::styles::{self, StyleSpec};
use crate::theme::*;
use serde_json::{json, Value};
use std::sync::Arc;

fn hex(c: (u8, u8, u8)) -> String { format!("#{:02x}{:02x}{:02x}", c.0, c.1, c.2) }
fn shade(c: (u8, u8, u8), f: f32) -> (u8, u8, u8) { let m = |v: u8| ((v as f32 * f).round().clamp(0.0, 255.0)) as u8; (m(c.0), m(c.1), m(c.2)) }
fn rgba_png(w: u32, h: u32, px: impl Fn(u32, u32) -> [u8; 4]) -> Vec<u8> {
    let mut img = image::RgbaImage::new(w, h);
    for y in 0..h { for x in 0..w { img.put_pixel(x, y, image::Rgba(px(x, y))); } }
    let mut out = std::io::Cursor::new(Vec::new());
    let _ = img.write_to(&mut out, image::ImageFormat::Png);
    out.into_inner()
}
fn dot_png(rgb: (u8, u8, u8), d: u32) -> Vec<u8> {
    let r = d as f32 / 2.0;
    rgba_png(d, d, |x, y| { let (dx, dy) = (x as f32 + 0.5 - r, y as f32 + 0.5 - r); let a = (r - (dx * dx + dy * dy).sqrt() + 0.5).clamp(0.0, 1.0); [rgb.0, rgb.1, rgb.2, (a * 255.0) as u8] })
}
fn q2(s: &str) -> String { q(s) }

pub struct PresetInfo { pub id: &'static str, pub label: &'static str, pub tip: &'static str }
const fn pi(id: &'static str, label: &'static str, tip: &'static str) -> PresetInfo { PresetInfo { id, label, tip } }

pub fn preset_list(kind: &str) -> Vec<PresetInfo> {
    match kind {
        "boot_menu" => vec![
            pi("centered", "Centered list", "A clean list in the middle of the screen with a rounded highlight."),
            pi("sidebar", "Left sidebar", "A translucent card on the left side with large rows."),
            pi("boxed", "Boxed with border", "A bordered panel; the highlight is a tinted rounded bar."),
            pi("minimal", "Minimal text", "Plain text, the selected entry is simply coloured. No images."),
            pi("gradient", "Gradient highlight", "A two-colour gradient highlight and a scrollbar."),
            pi("wide", "Full-width bar", "A highlight bar that spans the whole screen width."),
        ],
        "label" => vec![
            pi("title", "Big title", "A large centred heading near the top."),
            pi("subtitle", "Subtitle", "Smaller grey text under a title."),
            pi("hint", "Key hints (footer)", "Shows GRUB's key help at the bottom of the screen."),
            pi("countdown", "Countdown text", "\"Booting in N seconds\" that follows the countdown."),
            pi("big_timer", "Large timer digits", "Big monospaced seconds in a corner, driven by the countdown."),
        ],
        "rectangle" => vec![
            pi("panel", "Dark panel", "A translucent dark rectangle behind other items."),
            pi("card", "Rounded card", "A rounded, bordered card (a picture at a fixed size)."),
            pi("divider", "Divider line", "A thin horizontal line."),
            pi("accent_bar", "Accent bar", "A solid strip in your accent colour."),
            pi("fade", "Top fade", "A gradient that darkens the top of the screen."),
        ],
        "progress_bar" => vec![
            pi("classic", "Classic bar", "A simple bordered bar in the accent colour."),
            pi("thin", "Thin line", "A slim 6-pixel line without text."),
            pi("pill", "Rounded pill", "A rounded dark track with a rounded accent fill."),
            pi("labelled", "Bar with countdown text", "The bar with \"Booting in Ns\" inside."),
        ],
        "circular_progress" => vec![
            pi("ring", "Ring of dots", "24 dots that light up around a circle."),
            pi("dots12", "Clock dots", "12 larger dots, like a clock face."),
            pi("spinner", "Fading spinner", "12 dots that disappear as the time runs out."),
        ],
        "canvas" => vec![
            pi("empty", "Empty group", "A container; drag items into it so they move together."),
            pi("header_footer", "Header and footer", "A group with a title at the top and key hints at the bottom."),
            pi("stack", "Centered stack", "A vertical stack of title, subtitle and hint."),
            pi("two_columns", "Two columns", "A horizontal box with two vertical stacks side by side."),
        ],
        _ => vec![],
    }
}

fn label(props: &[(&str, &str)]) -> Comp {
    let mut c = Comp::new("label");
    for (k, v) in template("label") { c.props.insert(k.into(), v.into()); }
    for (k, v) in props { c.props.insert((*k).into(), (*v).into()); }
    c
}

impl Editor {
    // ------------------------------------------------------------ preview state
    pub fn set_timeout(&mut self, secs: i32) {
        self.timeout_secs = secs.clamp(0, 3600);
        self.progress = if self.timeout_total <= 0 { 1.0 } else { (self.timeout_secs as f32 / self.timeout_total as f32).clamp(0.0, 1.0) };
        self.touch();
    }
    pub fn set_timeout_total(&mut self, total: i32) { self.timeout_total = total.clamp(0, 3600); let s = self.timeout_secs; self.set_timeout(s); }
    pub fn set_timeout_visible(&mut self, v: bool) { self.timeout_visible = v; self.touch(); }
    pub fn set_entries(&mut self, e: Vec<(String, String)>) { self.entries = e; self.menu_sel = 0; self.touch(); }
    pub fn set_accent(&mut self, h: &str) { self.accent = parse_color(h, self.accent); self.touch(); }

    // ------------------------------------------------------------ clipboard
    pub fn has_clipboard(&self) -> bool { self.clipboard.is_some() }
    pub fn copy(&mut self, uid: u64) -> bool { match find(&self.doc.root, uid).cloned() { Some(c) => { self.clipboard = Some(c); true } None => false } }
    pub fn cut(&mut self, uid: u64) -> bool { if self.copy(uid) { self.remove(uid); true } else { false } }
    pub fn paste(&mut self) -> Option<u64> {
        let mut d = self.clipboard.clone()?.deep_clone();
        self.checkpoint();
        for k in ["left", "top"] { if let Some(n) = d.props.get(k).and_then(|v| v.parse::<i32>().ok()) { d.props.insert(k.into(), (n + 24).to_string()); } }
        let id = d.uid;
        let into = self.selected.and_then(|s| find(&self.doc.root, s)).filter(|c| matches!(c.ty.as_str(), "canvas" | "vbox" | "hbox")).map(|c| c.uid);
        match into { Some(p) => { if let Some(pc) = find_mut(&mut self.doc.root, p) { pc.children.push(d); } } None => self.doc.root.push(d) }
        self.selected = Some(id); self.touch(); Some(id)
    }

    // ------------------------------------------------------------ stacking order
    pub fn bring_to_front(&mut self, uid: u64) { self.checkpoint(); if let Some(l) = container_of(&mut self.doc.root, uid) { if let Some(i) = l.iter().position(|c| c.uid == uid) { let c = l.remove(i); l.push(c); } } self.touch(); }
    pub fn send_to_back(&mut self, uid: u64) { self.checkpoint(); if let Some(l) = container_of(&mut self.doc.root, uid) { if let Some(i) = l.iter().position(|c| c.uid == uid) { let c = l.remove(i); l.insert(0, c); } } self.touch(); }

    // ------------------------------------------------------------ grouping and alignment
    pub fn group(&mut self, uid: u64) -> Option<u64> {
        self.ensure_layout();
        let r = *self.rects.get(&uid)?;
        let pr = self.parent_rect(uid);
        self.checkpoint();
        let l = container_of(&mut self.doc.root, uid)?;
        let i = l.iter().position(|c| c.uid == uid)?;
        let mut child = l.remove(i);
        let mut g = Comp::new("canvas");
        for (k, v) in [("left", r.x - pr.x), ("top", r.y - pr.y), ("width", r.w), ("height", r.h)] { g.props.insert(k.into(), v.to_string()); }
        for (k, v) in [("left", 0), ("top", 0), ("width", r.w), ("height", r.h)] { child.props.insert(k.into(), v.to_string()); }
        let gid = g.uid;
        g.children.push(child);
        l.insert(i, g);
        self.selected = Some(gid); self.touch(); Some(gid)
    }
    pub fn ungroup(&mut self, uid: u64) -> bool {
        self.ensure_layout();
        let Some(c) = find(&self.doc.root, uid) else { return false };
        if !matches!(c.ty.as_str(), "canvas" | "vbox" | "hbox") || c.children.is_empty() { return false; }
        let pr = self.parent_rect(uid);
        let abs: Vec<(u64, Rect)> = c.children.iter().filter_map(|k| self.rects.get(&k.uid).map(|r| (k.uid, *r))).collect();
        self.checkpoint();
        let Some(l) = container_of(&mut self.doc.root, uid) else { return false };
        let Some(i) = l.iter().position(|x| x.uid == uid) else { return false };
        let g = l.remove(i);
        let mut first = None;
        for (n, mut k) in g.children.into_iter().enumerate() {
            if let Some((_, r)) = abs.iter().find(|(u, _)| *u == k.uid) {
                k.props.insert("left".into(), (r.x - pr.x).to_string()); k.props.insert("top".into(), (r.y - pr.y).to_string());
                if k.props.get("width").map(|v| v.is_empty()).unwrap_or(true) { k.props.insert("width".into(), r.w.to_string()); }
                if k.props.get("height").map(|v| v.is_empty()).unwrap_or(true) { k.props.insert("height".into(), r.h.to_string()); }
            }
            first.get_or_insert(k.uid);
            l.insert(i + n, k);
        }
        self.selected = first; self.touch(); true
    }
    pub fn align(&mut self, uid: u64, mode: &str) {
        self.ensure_layout();
        let Some(r) = self.rects.get(&uid).copied() else { return };
        match mode {
            "left" => self.set_prop(uid, "left", "0"),
            "right" => self.set_prop(uid, "left", &format!("100%-{}", r.w)),
            "hcenter" => self.center(uid, true),
            "top" => self.set_prop(uid, "top", "0"),
            "bottom" => self.set_prop(uid, "top", &format!("100%-{}", r.h)),
            "vcenter" => self.center(uid, false),
            _ => {}
        }
    }

    // ------------------------------------------------------------ styles from parameters
    /// Add the nine slices of a style to the theme and return the pattern to put in a `*_style` property.
    pub fn new_style(&mut self, prefix: &str, spec: &StyleSpec) -> String {
        let clean: String = prefix.chars().map(|c| if c.is_ascii_alphanumeric() || c == '-' || c == '_' { c } else { '-' }).take(32).collect();
        let name = if clean.is_empty() { format!("style-{}", new_uid()) } else { clean };
        for (slice, bytes) in styles::render_slices(spec) { self.doc.assets.insert(format!("{name}_{slice}.png"), Arc::new(bytes)); }
        self.touch();
        format!("{name}_*.png")
    }
    /// The "Style designer": make a style from parameters and assign it to property `key` of the selected item.
    pub fn design_style(&mut self, uid: u64, key: &str, spec: &StyleSpec) -> String {
        let pat = self.new_style(&format!("{}-{}", key.replace("_pixmap_style", "").replace("_style", "").replace('_', "-"), uid), spec);
        self.set_prop(uid, key, &q(&pat));
        pat
    }
    /// Cut a picture into a style (corner sizes l, t, r, b) and assign it.
    pub fn import_style(&mut self, uid: u64, key: &str, png: &[u8], l: u32, t: u32, r: u32, b: u32) -> Result<String, String> {
        let slices = styles::slice_image(png, l, t, r, b)?;
        let name = format!("{}-{}", key.replace("_pixmap_style", "").replace("_style", "").replace('_', "-"), uid);
        for (slice, bytes) in slices { self.doc.assets.insert(format!("{name}_{slice}.png"), Arc::new(bytes)); }
        let pat = format!("{name}_*.png");
        self.set_prop(uid, key, &q(&pat));
        Ok(pat)
    }

    // ------------------------------------------------------------ presets
    pub fn presets_json() -> String {
        let mut o = serde_json::Map::new();
        for k in ["boot_menu", "label", "rectangle", "progress_bar", "circular_progress", "canvas"] {
            o.insert(k.into(), Value::Array(preset_list(k).iter().map(|p| json!({"id": p.id, "label": p.label, "tip": p.tip})).collect()));
        }
        Value::Object(o).to_string()
    }

    pub fn add_preset(&mut self, kind: &str, id: &str) -> Option<u64> {
        let acc = self.accent;
        let (a, adark) = (hex(acc), hex(shade(acc, 0.72)));
        let s = |x: &str| x.to_string();
        let sp = |fill: &str, radius: u32| StyleSpec { fill: fill.into(), radius, ..Default::default() };
        Some(match (kind, id) {
            ("boot_menu", "centered") => {
                let sel = self.new_style("menu-sel", &sp(&a, 8));
                self.add("boot_menu", &[("left", s("25%")), ("top", s("30%")), ("width", s("50%")), ("height", s("45%")), ("item_height", s("40")), ("item_padding", s("18")), ("item_spacing", s("6")), ("item_color", q("#c9ccd3")), ("selected_item_color", q("#ffffff")), ("selected_item_pixmap_style", q(&sel))])
            }
            ("boot_menu", "sidebar") => {
                let card = self.new_style("menu-card", &StyleSpec { fill: "#0e1014".into(), opacity: 72, radius: 14, border_width: 1, border: "#ffffff".into(), border_opacity: 14, ..Default::default() });
                let sel = self.new_style("menu-sel", &StyleSpec { fill: a.clone(), opacity: 90, radius: 10, ..Default::default() });
                self.add("boot_menu", &[("left", s("4%")), ("top", s("15%")), ("width", s("32%")), ("height", s("70%")), ("item_height", s("46")), ("item_padding", s("20")), ("item_spacing", s("4")), ("item_color", q("#d6d9df")), ("selected_item_color", q("#ffffff")), ("menu_pixmap_style", q(&card)), ("selected_item_pixmap_style", q(&sel))])
            }
            ("boot_menu", "boxed") => {
                let card = self.new_style("menu-box", &StyleSpec { fill: "#0a0c10".into(), opacity: 88, radius: 10, border_width: 2, border: a.clone(), ..Default::default() });
                let sel = self.new_style("menu-sel", &StyleSpec { fill: a.clone(), opacity: 24, radius: 6, border_width: 1, border: a.clone(), ..Default::default() });
                self.add("boot_menu", &[("left", s("20%")), ("top", s("22%")), ("width", s("60%")), ("height", s("52%")), ("item_height", s("38")), ("item_padding", s("16")), ("item_spacing", s("6")), ("item_color", q("#c9ccd3")), ("selected_item_color", q("#ffffff")), ("menu_pixmap_style", q(&card)), ("selected_item_pixmap_style", q(&sel))])
            }
            ("boot_menu", "minimal") => self.add("boot_menu", &[("left", s("30%")), ("top", s("35%")), ("width", s("40%")), ("height", s("35%")), ("item_height", s("30")), ("item_padding", s("6")), ("item_spacing", s("2")), ("item_color", q("#8d93a0")), ("selected_item_color", q(&a))]),
            ("boot_menu", "gradient") => {
                let sel = self.new_style("menu-sel", &StyleSpec { fill: a.clone(), fill2: adark, radius: 6, ..Default::default() });
                self.add("boot_menu", &[("left", s("25%")), ("top", s("28%")), ("width", s("50%")), ("height", s("40%")), ("item_height", s("38")), ("item_padding", s("16")), ("item_spacing", s("6")), ("selected_item_color", q("#ffffff")), ("selected_item_pixmap_style", q(&sel)), ("scrollbar", s("true")), ("scrollbar_width", s("10"))])
            }
            ("boot_menu", "wide") => {
                let sel = self.new_style("menu-sel", &sp(&a, 0));
                self.add("boot_menu", &[("left", s("0")), ("top", s("35%")), ("width", s("100%")), ("height", s("30%")), ("item_height", s("44")), ("item_padding", s("120")), ("item_spacing", s("0")), ("item_color", q("#c9ccd3")), ("selected_item_color", q("#1a0b0b")), ("selected_item_pixmap_style", q(&sel))])
            }

            ("label", "title") => { self.use_builtin_font(&q("Inter Bold 32")); self.add("label", &[("left", s("10%")), ("top", s("8%")), ("width", s("80%")), ("height", s("48")), ("text", q("Select an operating system")), ("font", q("Inter Bold 32")), ("color", q("#ffffff")), ("align", q("center"))]) }
            ("label", "subtitle") => { self.use_builtin_font(&q("Inter Regular 24")); self.add("label", &[("left", s("10%")), ("top", s("16%")), ("width", s("80%")), ("height", s("32")), ("text", q("Use the arrow keys to choose, Enter to boot")), ("font", q("Inter Regular 24")), ("color", q("#9aa0ab")), ("align", q("center"))]) }
            ("label", "hint") => { self.use_builtin_font(&q("Inter Regular 16")); self.add("label", &[("left", s("0")), ("top", s("94%")), ("width", s("100%")), ("height", s("24")), ("text", q("@KEYMAP_SHORT@")), ("font", q("Inter Regular 16")), ("color", q("#6b7280")), ("align", q("center"))]) }
            ("label", "countdown") => { self.use_builtin_font(&q("Inter Regular 24")); self.add("label", &[("id", q("__timeout__")), ("left", s("25%")), ("top", s("80%")), ("width", s("50%")), ("height", s("32")), ("text", q("Booting in %d seconds")), ("font", q("Inter Regular 24")), ("color", q(&a)), ("align", q("center"))]) }
            ("label", "big_timer") => { self.use_builtin_font(&q("JetBrains Mono Bold 48")); self.add("label", &[("id", q("__timeout__")), ("left", s("82%")), ("top", s("6%")), ("width", s("14%")), ("height", s("64")), ("text", q("%02d")), ("font", q("JetBrains Mono Bold 48")), ("color", q(&a)), ("align", q("right"))]) }

            ("rectangle", "panel") => { self.rect_asset("panel", rgba_png(1, 1, |_, _| [14, 16, 20, 190]), &[("left", s("5%")), ("top", s("20%")), ("width", s("40%")), ("height", s("60%"))], None) }
            ("rectangle", "divider") => { self.rect_asset("divider", rgba_png(1, 1, |_, _| [255, 255, 255, 70]), &[("left", s("10%")), ("top", s("80%")), ("width", s("80%")), ("height", s("2"))], None) }
            ("rectangle", "accent_bar") => { let c = hex(acc); self.rect_asset("accent", rgba_png(1, 1, |_, _| [acc.0, acc.1, acc.2, 255]), &[("left", s("0")), ("top", s("0")), ("width", s("100%")), ("height", s("6"))], Some(c)) }
            ("rectangle", "fade") => { self.rect_asset("fade", rgba_png(1, 64, |_, y| [0, 0, 0, (210.0 * (1.0 - y as f32 / 63.0)) as u8]), &[("left", s("0")), ("top", s("0")), ("width", s("100%")), ("height", s("30%"))], None) }
            ("rectangle", "card") => {
                let bytes = styles::box_png(&StyleSpec { fill: "#12151b".into(), opacity: 92, radius: 18, border_width: 2, border: a.clone(), border_opacity: 80, ..Default::default() }, 480, 260);
                self.rect_asset("card", bytes, &[("left", s("50%-240")), ("top", s("50%-130")), ("width", s("480")), ("height", s("260"))], None)
            }

            ("progress_bar", "classic") => self.add("progress_bar", &[("left", s("20%")), ("top", s("88%")), ("width", s("60%")), ("height", s("20"))]),
            ("progress_bar", "thin") => self.add("progress_bar", &[("left", s("20%")), ("top", s("92%")), ("width", s("60%")), ("height", s("6")), ("text", s("")), ("border_color", q("#2a2f3a")), ("bg_color", q("#2a2f3a"))]),
            ("progress_bar", "pill") => {
                let track = self.new_style("bar-track", &StyleSpec { fill: "#1b1f27".into(), radius: 10, border_width: 1, border: "#343b49".into(), ..Default::default() });
                let fill = self.new_style("bar-fill", &sp(&a, 10));
                self.add("progress_bar", &[("left", s("25%")), ("top", s("88%")), ("width", s("50%")), ("height", s("20")), ("text", s("")), ("bar_style", q(&track)), ("highlight_style", q(&fill))])
            }
            ("progress_bar", "labelled") => { self.use_builtin_font(&q("Inter Regular 16")); self.add("progress_bar", &[("left", s("25%")), ("top", s("86%")), ("width", s("50%")), ("height", s("28")), ("text", q("@TIMEOUT_NOTIFICATION_SHORT@")), ("font", q("Inter Regular 16")), ("text_color", q("#ffffff"))]) }

            ("circular_progress", "ring") => self.dots("ring", 24, 8, false),
            ("circular_progress", "dots12") => self.dots("clock", 12, 12, false),
            ("circular_progress", "spinner") => self.dots("spin", 12, 10, true),

            ("canvas", "empty") => self.add("canvas", &[]),
            ("canvas", "header_footer") => {
                self.use_builtin_font(&q("Inter Bold 32")); self.use_builtin_font(&q("Inter Regular 16"));
                self.group_of("canvas", &[("left", "0"), ("top", "0"), ("width", "100%"), ("height", "100%")], vec![
                    label(&[("left", "10%"), ("top", "6%"), ("width", "80%"), ("height", "48"), ("text", &q("Select an operating system")), ("font", &q("Inter Bold 32")), ("color", &q("#ffffff")), ("align", &q("center"))]),
                    label(&[("left", "0"), ("top", "94%"), ("width", "100%"), ("height", "24"), ("text", "\"@KEYMAP_SHORT@\""), ("font", &q("Inter Regular 16")), ("color", &q("#6b7280")), ("align", &q("center"))]),
                ])
            }
            ("canvas", "stack") => {
                self.use_builtin_font(&q("Inter Bold 32")); self.use_builtin_font(&q("Inter Regular 24")); self.use_builtin_font(&q("Inter Regular 16"));
                self.group_of("vbox", &[("left", "25%"), ("top", "8%"), ("width", "50%"), ("height", "20%")], vec![
                    label(&[("width", "100%"), ("height", "48"), ("text", &q("Welcome")), ("font", &q("Inter Bold 32")), ("color", &q("#ffffff")), ("align", &q("center"))]),
                    label(&[("width", "100%"), ("height", "36"), ("text", &q("Choose what to start")), ("font", &q("Inter Regular 24")), ("color", &q("#9aa0ab")), ("align", &q("center"))]),
                    label(&[("width", "100%"), ("height", "28"), ("text", "\"@KEYMAP_SHORT@\""), ("font", &q("Inter Regular 16")), ("color", &q("#6b7280")), ("align", &q("center"))]),
                ])
            }
            ("canvas", "two_columns") => {
                self.use_builtin_font(&q("Inter Bold 32")); self.use_builtin_font(&q("Inter Regular 24"));
                let col = |t: &str, d: &str| { let mut v = Comp::new("vbox"); for (k, x) in [("width", "50%"), ("height", "100%")] { v.props.insert(k.into(), x.into()); }
                    v.children = vec![label(&[("width", "100%"), ("height", "44"), ("text", &q(t)), ("font", &q("Inter Bold 32")), ("color", &q("#ffffff")), ("align", &q("center"))]), label(&[("width", "100%"), ("height", "32"), ("text", &q(d)), ("font", &q("Inter Regular 24")), ("color", &q("#9aa0ab")), ("align", &q("center"))])]; v };
                self.group_of("hbox", &[("left", "10%"), ("top", "20%"), ("width", "80%"), ("height", "20%")], vec![col("Linux", "Daily driver"), col("Windows", "Games and work")])
            }
            _ => return None,
        })
    }

    /// An image component that shows a generated picture (rectangles are pictures in GRUB).
    fn rect_asset(&mut self, name: &str, png: Vec<u8>, props: &[(&str, String)], color: Option<String>) -> u64 {
        let file = format!("{name}-{}.png", new_uid());
        self.add_asset(&file, png);
        let mut p: Vec<(&str, String)> = vec![("file", q(&file))];
        p.extend(props.iter().map(|(k, v)| (*k, v.clone())));
        let id = self.add("image", &p);
        if let Some(c) = color { self.rect_colors.insert(id, c); }
        id
    }
    fn dots(&mut self, name: &str, n: u32, d: u32, vanish: bool) -> u64 {
        let file = format!("{name}-dot-{}.png", new_uid());
        self.add_asset(&file, dot_png(self.accent, d));
        self.add("circular_progress", &[("left", "50%-60".into()), ("top", "72%".into()), ("width", "120".into()), ("height", "120".into()), ("tick_bitmap", q2(&file)), ("num_ticks", n.to_string()), ("start_angle", "-64".into()), ("ticks_disappear", vanish.to_string())])
    }
    fn group_of(&mut self, ty: &str, props: &[(&str, &str)], children: Vec<Comp>) -> u64 {
        self.checkpoint();
        let mut g = Comp::new(ty);
        for (k, v) in props { g.props.insert((*k).into(), (*v).into()); }
        g.children = children;
        let id = g.uid;
        self.doc.root.push(g);
        self.selected = Some(id); self.touch(); id
    }
}
