//! Editor state: document operations, undo/redo, selection, viewport, pointer handling and JSON views for the UI.
use crate::render::{fill, parse_color, DrawOpts, Rect, Scene};
use crate::theme::*;
use indexmap::IndexMap;
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;
use tiny_skia::{Color, FilterQuality, Pixmap, PixmapPaint, Transform};

const HANDLES: [(&str, f32, f32); 8] = [("nw", 0., 0.), ("n", 0.5, 0.), ("ne", 1., 0.), ("e", 1., 0.5), ("se", 1., 1.), ("s", 0.5, 1.), ("sw", 0., 1.), ("w", 0., 0.5)];
pub const SCREEN_PRESETS: [(i32, i32); 6] = [(1920, 1080), (2560, 1440), (1366, 768), (1280, 720), (1024, 768), (800, 600)];

fn template(ty: &str) -> Vec<(&'static str, &'static str)> {
    match ty {
        "label" => vec![("left", "100"), ("top", "100"), ("width", "320"), ("height", "32"), ("text", "\"Label\""), ("color", "\"#ffffff\""), ("font", "\"Unifont Regular 16\""), ("align", "\"left\"")],
        "image" => vec![("left", "100"), ("top", "100"), ("width", "200"), ("height", "120"), ("file", "\"\"")],
        "boot_menu" => vec![("left", "20%"), ("top", "30%"), ("width", "60%"), ("height", "40%"), ("item_font", "\"Unifont Regular 16\""), ("selected_item_font", "\"Unifont Regular 16\""), ("item_color", "\"#c8ccd4\""), ("selected_item_color", "\"#ffffff\""), ("item_height", "36"), ("item_padding", "12"), ("item_spacing", "8"), ("icon_width", "0"), ("icon_height", "0"), ("item_icon_space", "0"), ("scrollbar", "false")],
        "progress_bar" => vec![("id", "\"__timeout__\""), ("left", "20%"), ("top", "85%"), ("width", "60%"), ("height", "20"), ("fg_color", "\"#ff9248\""), ("bg_color", "\"#2a3140\""), ("border_color", "\"#4a5468\""), ("text_color", "\"#ffffff\""), ("font", "\"Unifont Regular 16\""), ("text", "\"@TIMEOUT_NOTIFICATION_SHORT@\"")],
        "circular_progress" => vec![("id", "\"__timeout__\""), ("left", "45%"), ("top", "75%"), ("width", "10%"), ("height", "10%"), ("num_ticks", "24"), ("start_angle", "-64"), ("ticks_disappear", "false")],
        "vbox" => vec![("left", "10%"), ("top", "10%"), ("width", "30%"), ("height", "60%")],
        "hbox" => vec![("left", "10%"), ("top", "10%"), ("width", "60%"), ("height", "30%")],
        _ => vec![("left", "10%"), ("top", "10%"), ("width", "80%"), ("height", "80%")],
    }
}

/// (key, label, kind). kinds: str expr color bool select file font style
fn schema(ty: &str) -> Vec<(&'static str, &'static str, &'static str)> {
    match ty {
        "label" => vec![("text", "Text", "str"), ("color", "Color", "color"), ("font", "Font", "font"), ("align", "Align", "select")],
        "image" => vec![("file", "Image", "file")],
        "boot_menu" => vec![("item_font", "Item font", "font"), ("selected_item_font", "Selected font", "font"), ("item_color", "Item color", "color"), ("selected_item_color", "Selected color", "color"), ("item_height", "Item height", "expr"), ("item_padding", "Item padding", "expr"), ("item_spacing", "Item spacing", "expr"), ("icon_width", "Icon width", "expr"), ("icon_height", "Icon height", "expr"), ("item_icon_space", "Icon gap", "expr"), ("item_pixmap_style", "Item style", "style"), ("selected_item_pixmap_style", "Selected style", "style"), ("menu_pixmap_style", "Menu style", "style"), ("scrollbar", "Scrollbar", "bool")],
        "progress_bar" => vec![("id", "Id", "str"), ("text", "Text", "str"), ("font", "Font", "font"), ("text_color", "Text color", "color"), ("fg_color", "Fill color", "color"), ("bg_color", "Back color", "color"), ("border_color", "Border", "color"), ("bar_style", "Bar style", "style"), ("highlight_style", "Fill style", "style")],
        "circular_progress" => vec![("id", "Id", "str"), ("center_bitmap", "Center", "file"), ("tick_bitmap", "Tick", "file"), ("num_ticks", "Ticks", "expr"), ("start_angle", "Start angle", "expr"), ("ticks_disappear", "Ticks vanish", "bool")],
        _ => vec![],
    }
}
const THEME_SCHEMA: [(&str, &str, &str); 6] = [("desktop-color", "Background", "color"), ("desktop-image", "Image", "file"), ("desktop-image-scale-method", "Scale", "select"), ("title-text", "Title", "str"), ("title-color", "Title color", "color"), ("title-font", "Title font", "font")];

fn quoted(kind: &str) -> bool { matches!(kind, "str" | "color" | "select" | "file" | "font" | "style") }

fn find<'a>(list: &'a [Comp], uid: u64) -> Option<&'a Comp> {
    for c in list { if c.uid == uid { return Some(c); } if let Some(f) = find(&c.children, uid) { return Some(f); } }
    None
}
fn find_mut<'a>(list: &'a mut [Comp], uid: u64) -> Option<&'a mut Comp> {
    for c in list.iter_mut() {
        if c.uid == uid { return Some(c); }
        if let Some(f) = find_mut(&mut c.children, uid) { return Some(f); }
    }
    None
}
fn container_of<'a>(list: &'a mut Vec<Comp>, uid: u64) -> Option<&'a mut Vec<Comp>> {
    if list.iter().any(|c| c.uid == uid) { return Some(list); }
    for c in list.iter_mut() { if let Some(f) = container_of(&mut c.children, uid) { return Some(f); } }
    None
}
fn parent_uid(list: &[Comp], uid: u64, parent: Option<u64>) -> Option<Option<u64>> {
    for c in list { if c.uid == uid { return Some(parent); } if let Some(f) = parent_uid(&c.children, uid, Some(c.uid)) { return Some(f); } }
    None
}

pub fn solid_png(rgb: (u8, u8, u8)) -> Vec<u8> {
    let img = image::RgbaImage::from_pixel(1, 1, image::Rgba([rgb.0, rgb.1, rgb.2, 255]));
    let mut out = std::io::Cursor::new(Vec::new());
    let _ = img.write_to(&mut out, image::ImageFormat::Png);
    out.into_inner()
}

struct Snap { globals: IndexMap<String, String>, root: Vec<Comp>, screen: (i32, i32) }
#[derive(PartialEq)]
enum DragKind { Move, Resize, Pan }
struct Drag { kind: DragKind, handle: &'static str, sx: f64, sy: f64, start: Rect, pan0: (f64, f64), moved: bool, uid: u64, parent: Rect }

pub struct Editor {
    pub doc: Doc,
    pub name: String,
    pub selected: Option<u64>,
    pub menu_sel: usize,
    pub progress: f32,
    pub rect_colors: HashMap<u64, String>,
    scene: Scene,
    rev: u64,
    drawn: (u64, usize, u32, bool),
    scene_pix: Option<Pixmap>,
    view_pix: Option<Pixmap>,
    rects: HashMap<u64, Rect>,
    undo: Vec<Snap>,
    redo: Vec<Snap>,
    zoom: f64, pan: (f64, f64),
    drag: Option<Drag>,
    guides: (Option<i32>, Option<i32>),
    pub space: bool,
}

impl Default for Editor { fn default() -> Self { Self::new() } }

impl Editor {
    pub fn new() -> Self {
        Editor { doc: Doc::default(), name: "my-theme".into(), selected: None, menu_sel: 0, progress: 0.6, rect_colors: HashMap::new(), scene: Scene::new(), rev: 1, drawn: (0, 0, 0, false), scene_pix: None, view_pix: None, rects: HashMap::new(), undo: vec![], redo: vec![], zoom: 0.5, pan: (40., 40.), drag: None, guides: (None, None), space: false }
    }
    pub fn rev(&self) -> u64 { self.rev }
    fn touch(&mut self) { self.rev += 1; }
    fn snap(&self) -> Snap { Snap { globals: self.doc.globals.clone(), root: self.doc.root.clone(), screen: self.doc.screen } }
    pub fn checkpoint(&mut self) { let s = self.snap(); self.undo.push(s); if self.undo.len() > 100 { self.undo.remove(0); } self.redo.clear(); }
    fn restore(&mut self, s: Snap) {
        self.doc.globals = s.globals; self.doc.root = s.root; self.doc.screen = s.screen;
        if let Some(id) = self.selected { if find(&self.doc.root, id).is_none() { self.selected = None; } }
        self.touch();
    }
    pub fn undo(&mut self) { if let Some(s) = self.undo.pop() { let cur = self.snap(); self.redo.push(cur); self.restore(s); } }
    pub fn redo(&mut self) { if let Some(s) = self.redo.pop() { let cur = self.snap(); self.undo.push(cur); self.restore(s); } }
    pub fn can_undo(&self) -> bool { !self.undo.is_empty() }
    pub fn can_redo(&self) -> bool { !self.redo.is_empty() }

    pub fn load(&mut self, doc: Doc, name: &str) {
        self.doc = doc; self.selected = None; self.undo.clear(); self.redo.clear(); self.rect_colors.clear();
        let n: String = name.chars().map(|c| if c.is_ascii_alphanumeric() || "._-".contains(c) { c } else { '-' }).take(48).collect();
        if !n.is_empty() { self.name = n; }
        self.touch();
    }
    pub fn reset(&mut self) { self.load(Doc::default(), "my-theme"); }
    pub fn load_files(&mut self, files: &BTreeMap<String, Vec<u8>>, name: &str) -> Result<(), String> { let d = doc_from_files(files)?; self.load(d, name); Ok(()) }

    /// Finished theme: theme.txt plus every asset.
    pub fn files(&self) -> BTreeMap<String, Vec<u8>> {
        let mut g = self.doc.globals.clone();
        g.shift_remove("screen-size");
        let mut out = BTreeMap::new();
        out.insert("theme.txt".to_string(), serialize_theme(&g, &self.doc.root, "Made with Pimp my grub").into_bytes());
        for (k, v) in &self.doc.assets { out.insert(k.clone(), v.as_ref().clone()); }
        out
    }

    // ------------------------------------------------------------ mutations
    pub fn set_prop(&mut self, uid: u64, key: &str, value: &str) {
        let same = find(&self.doc.root, uid).map(|c| c.p(key) == value).unwrap_or(true);
        if same { return; }
        self.checkpoint();
        if let Some(c) = find_mut(&mut self.doc.root, uid) { c.props.insert(key.into(), value.into()); }
        self.touch();
    }
    pub fn set_global(&mut self, key: &str, value: &str) {
        self.checkpoint();
        if value.is_empty() { self.doc.globals.shift_remove(key); } else { self.doc.globals.insert(key.into(), value.into()); }
        self.touch();
    }
    pub fn set_screen(&mut self, w: i32, h: i32) { self.checkpoint(); self.doc.screen = (w, h); self.touch(); }

    pub fn add(&mut self, ty: &str, extra: &[(&str, String)]) -> u64 {
        self.checkpoint();
        let mut c = Comp::new(ty);
        for (k, v) in template(ty) { c.props.insert(k.into(), v.into()); }
        for (k, v) in extra { c.props.insert((*k).into(), v.clone()); }
        let id = c.uid;
        let into_container = self.selected.and_then(|s| find(&self.doc.root, s)).map(|s| matches!(s.ty.as_str(), "canvas" | "vbox" | "hbox")).unwrap_or(false);
        match (into_container, self.selected) {
            (true, Some(s)) => { if let Some(p) = find_mut(&mut self.doc.root, s) { p.children.push(c); } }
            _ => self.doc.root.push(c),
        }
        self.selected = Some(id); self.touch(); id
    }
    pub fn add_rect(&mut self, color: &str) {
        let name = format!("rect-{}.png", new_uid());
        self.add_asset(&name, solid_png(parse_color(color, (255, 146, 72))));
        let id = self.add("image", &[("file", q(&name)), ("width", "300".into()), ("height", "160".into())]);
        self.rect_colors.insert(id, color.to_string());
    }
    pub fn recolor_rect(&mut self, uid: u64, color: &str) {
        if let Some(c) = find(&self.doc.root, uid) {
            let f = c.pu("file").to_string();
            self.rect_colors.insert(uid, color.to_string());
            self.add_asset(&f, solid_png(parse_color(color, (255, 146, 72))));
        }
    }
    pub fn add_asset(&mut self, path: &str, bytes: Vec<u8>) { self.doc.assets.insert(path.into(), Arc::new(bytes)); self.touch(); }
    pub fn remove_asset(&mut self, path: &str) { self.doc.assets.remove(path); self.touch(); }
    pub fn add_solid_style(&mut self, uid: u64, key: &str, color: &str) {
        let prefix = format!("{}-{}", key.replace("_pixmap_style", "").replace("_style", ""), uid);
        self.add_asset(&format!("{prefix}_c.png"), solid_png(parse_color(color, (47, 127, 214))));
        self.set_prop(uid, key, &q(&format!("{prefix}_*.png")));
    }
    pub fn remove(&mut self, uid: u64) {
        self.checkpoint();
        if let Some(l) = container_of(&mut self.doc.root, uid) { l.retain(|c| c.uid != uid); }
        if self.selected == Some(uid) { self.selected = None; }
        self.touch();
    }
    pub fn duplicate(&mut self, uid: u64) {
        let Some(orig) = find(&self.doc.root, uid).cloned() else { return };
        self.checkpoint();
        let mut d = orig.deep_clone();
        for k in ["left", "top"] { if let Some(v) = d.props.get(k).cloned() { if let Ok(n) = v.parse::<i32>() { d.props.insert(k.into(), (n + 20).to_string()); } } }
        let id = d.uid;
        if let Some(l) = container_of(&mut self.doc.root, uid) { let i = l.iter().position(|c| c.uid == uid).unwrap_or(0); l.insert(i + 1, d); }
        self.selected = Some(id); self.touch();
    }
    pub fn reorder(&mut self, uid: u64, dir: i32) {
        self.checkpoint();
        if let Some(l) = container_of(&mut self.doc.root, uid) {
            let i = l.iter().position(|c| c.uid == uid).unwrap_or(0) as i32;
            let j = i + dir;
            if j >= 0 && (j as usize) < l.len() { l.swap(i as usize, j as usize); }
        }
        self.touch();
    }
    pub fn toggle(&mut self, uid: u64, locked: bool) { if let Some(c) = find_mut(&mut self.doc.root, uid) { if locked { c.locked = !c.locked } else { c.hidden = !c.hidden } } self.touch(); }
    pub fn center(&mut self, uid: u64, x_axis: bool) {
        self.ensure_layout();
        let Some(c) = find(&self.doc.root, uid) else { return };
        let (key, size) = if x_axis { ("left", "width") } else { ("top", "height") };
        let reference = if x_axis { self.doc.screen.0 } else { self.doc.screen.1 };
        let sv = c.p(size).to_string();
        let val = match sv.strip_suffix('%').and_then(|n| n.parse::<f64>().ok()) {
            Some(p) => format!("{}%", ((100.0 - p) / 2.0 * 100.0).round() / 100.0),
            None => format!("50%-{}", eval_len(Some(&sv), reference, 0) / 2),
        };
        self.set_prop(uid, key, &val);
    }

    // ------------------------------------------------------------ UI-facing JSON
    pub fn set_field(&mut self, key: &str, value: &str) {
        match self.selected {
            Some(uid) => {
                let ty = find(&self.doc.root, uid).map(|c| c.ty.clone()).unwrap_or_default();
                let kind = schema(&ty).iter().find(|s| s.0 == key).map(|s| s.2).unwrap_or("expr");
                let v = if quoted(kind) { if value.is_empty() && kind != "str" { String::new() } else { q(value) } } else { value.trim().to_string() };
                self.set_prop(uid, key, &v);
            }
            None => {
                if key == "screen" { if let Some((w, h)) = value.split_once('x') { if let (Ok(w), Ok(h)) = (w.parse(), h.parse()) { self.set_screen(w, h); } } return; }
                let kind = THEME_SCHEMA.iter().find(|s| s.0 == key).map(|s| s.2).unwrap_or("str");
                self.set_global(key, &if value.is_empty() { String::new() } else if quoted(kind) { q(value) } else { value.to_string() });
            }
        }
    }

    pub fn layers_json(&self) -> String {
        fn walk(list: &[Comp], depth: i32, sel: Option<u64>, out: &mut Vec<Value>) {
            for c in list.iter().rev() {
                let label = if c.ty == "label" && !c.pu("text").is_empty() { format!("“{}”", c.pu("text")) } else if !c.pu("id").is_empty() { c.pu("id").to_string() } else { c.ty.clone() };
                out.push(json!({"uid": c.uid, "type": c.ty, "label": label, "depth": depth, "selected": sel == Some(c.uid), "hidden": c.hidden, "locked": c.locked}));
                walk(&c.children, depth + 1, sel, out);
            }
        }
        let mut v = vec![];
        walk(&self.doc.root, 0, self.selected, &mut v);
        Value::Array(v).to_string()
    }

    fn style_options(&self) -> Vec<String> {
        let mut set = std::collections::BTreeSet::new();
        for k in self.doc.assets.keys() {
            for s in ["_nw", "_ne", "_sw", "_se", "_n", "_s", "_e", "_w", "_c"] {
                if let Some(p) = k.strip_suffix(&format!("{s}.png")) { set.insert(format!("{p}_*.png")); }
            }
        }
        set.into_iter().collect()
    }

    pub fn inspector_json(&self) -> String {
        let images: Vec<&String> = self.doc.assets.keys().filter(|k| { let l = k.to_ascii_lowercase(); l.ends_with(".png") || l.ends_with(".jpg") || l.ends_with(".jpeg") }).collect();
        let mut fonts = self.scene.font_names(); fonts.push("Unifont Regular 16".into()); fonts.sort(); fonts.dedup();
        let styles = self.style_options();
        let opts = |kind: &str, key: &str| -> Value {
            match (kind, key) {
                ("file", _) => json!(images), ("font", _) => json!(fonts), ("style", _) => json!(styles),
                ("select", "align") => json!(["left", "center", "right"]),
                ("select", _) => json!(["stretch", "crop", "fitwidth", "fitheight"]),
                _ => json!([]),
            }
        };
        let field = |key: &str, label: &str, kind: &str, raw: &str| json!({"key": key, "label": label, "kind": kind, "value": if quoted(kind) || kind == "bool" { unq(raw).to_string() } else { raw.to_string() }, "options": opts(kind, key)});
        if let Some(c) = self.selected.and_then(|s| find(&self.doc.root, s)) {
            let geom: Vec<Value> = [("left", "X"), ("top", "Y"), ("width", "Width"), ("height", "Height")].iter().map(|(k, l)| field(k, l, "expr", c.p(k))).collect();
            let mut fields: Vec<Value> = schema(&c.ty).iter().map(|(k, l, kind)| field(k, l, kind, c.p(k))).collect();
            if c.ty == "image" { if let Some(col) = self.rect_colors.get(&c.uid) { fields.insert(0, json!({"key": "__rect", "label": "Fill", "kind": "rectcolor", "value": col, "options": []})); } }
            json!({"mode": "comp", "uid": c.uid, "title": c.ty.replace('_', " "), "geometry": geom, "fields": fields}).to_string()
        } else {
            let g = |k: &str| self.doc.globals.get(k).map(|s| s.as_str()).unwrap_or("");
            let mut fields = vec![json!({"key": "screen", "label": "Preview size", "kind": "select", "value": format!("{}x{}", self.doc.screen.0, self.doc.screen.1), "options": SCREEN_PRESETS.iter().map(|(w, h)| format!("{w}x{h}")).collect::<Vec<_>>()})];
            for (k, l, kind) in THEME_SCHEMA { fields.push(field(k, l, kind, g(k))); }
            let assets: Vec<&String> = self.doc.assets.keys().collect();
            json!({"mode": "theme", "title": "Theme", "geometry": [], "fields": fields, "assets": assets, "fonts": self.scene.font_names(), "missing": missing_assets(&self.doc)}).to_string()
        }
    }

    // ------------------------------------------------------------ rendering
    fn ensure_layout(&mut self) { self.scene.sync(&self.doc.assets); self.rects = self.scene.layout(&self.doc); }

    pub fn fit(&mut self, w: u32, h: u32) {
        let (sw, sh) = (self.doc.screen.0 as f64, self.doc.screen.1 as f64);
        self.zoom = ((w as f64 - 60.0) / sw).min((h as f64 - 60.0) / sh).clamp(0.05, 2.0);
        self.pan = ((w as f64 - sw * self.zoom) / 2.0, (h as f64 - sh * self.zoom) / 2.0);
    }
    /// Zoom to `z`, keeping whatever is at the middle of the viewport (`w` x `h`) in the middle.
    pub fn zoom_to(&mut self, z: f64, w: u32, h: u32) {
        let (cx, cy) = (w as f64 / 2.0, h as f64 / 2.0);
        let (wx, wy) = self.to_world(cx, cy);
        let nz = z.clamp(0.05, 4.0);
        self.pan = (cx - wx * nz, cy - wy * nz); self.zoom = nz;
    }
    pub fn actual_size(&mut self, w: u32, h: u32) { self.zoom_to(1.0, w, h); self.center_view(w, h); }
    /// Next/previous stop of a fixed zoom ladder (so repeated clicks land on round numbers).
    pub fn zoom_step(&mut self, up: bool, w: u32, h: u32) {
        const L: [f64; 15] = [0.05, 0.1, 0.15, 0.25, 0.33, 0.5, 0.67, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0, 4.0];
        let z = self.zoom;
        let nz = if up { L.iter().copied().find(|v| *v > z * 1.02).unwrap_or(4.0) } else { L.iter().rev().copied().find(|v| *v < z / 1.02).unwrap_or(0.05) };
        self.zoom_to(nz, w, h);
    }
    /// Put the screen back in the middle of the viewport without changing the zoom (recovers a view lost by scrolling).
    pub fn center_view(&mut self, w: u32, h: u32) {
        let (sw, sh) = (self.doc.screen.0 as f64, self.doc.screen.1 as f64);
        self.pan = ((w as f64 - sw * self.zoom) / 2.0, (h as f64 - sh * self.zoom) / 2.0);
    }
    pub fn zoom(&self) -> f64 { self.zoom }

    fn rerender_scene(&mut self) {
        let changed = self.scene.sync(&self.doc.assets);
        let key = (self.rev, self.menu_sel, self.progress.to_bits(), changed);
        let size_ok = self.scene_pix.as_ref().map(|p| (p.width() as i32, p.height() as i32) == self.doc.screen).unwrap_or(false);
        if size_ok && key.0 == self.drawn.0 && key.1 == self.drawn.1 && key.2 == self.drawn.2 && !changed { return; }
        self.rects = self.scene.layout(&self.doc);
        if !size_ok { self.scene_pix = Pixmap::new(self.doc.screen.0.max(1) as u32, self.doc.screen.1.max(1) as u32); }
        if let Some(p) = self.scene_pix.as_mut() { self.scene.draw(p, &self.doc, &self.rects, &DrawOpts { menu_sel: self.menu_sel, progress: self.progress }); }
        self.drawn = (self.rev, self.menu_sel, self.progress.to_bits(), false);
    }

    /// Render the editor viewport. Returns premultiplied RGBA8 pixels, width and height.
    pub fn render_view(&mut self, w: u32, h: u32) -> Option<(&[u8], u32, u32)> {
        if w == 0 || h == 0 { return None; }
        self.rerender_scene();
        let ok = self.view_pix.as_ref().map(|p| p.width() == w && p.height() == h).unwrap_or(false);
        if !ok { self.view_pix = Pixmap::new(w, h); }
        let (zoom, pan) = (self.zoom as f32, self.pan);
        let sel_rect = self.selected.and_then(|s| self.rects.get(&s).copied());
        let sel_locked = self.selected.and_then(|s| find(&self.doc.root, s)).map(|c| c.locked).unwrap_or(false);
        let guides = self.guides;
        let screen = self.doc.screen;
        let view = self.view_pix.as_mut()?;
        view.fill(Color::from_rgba8(9, 9, 11, 255));
        if let Some(sp) = self.scene_pix.as_ref() {
            let quality = if zoom < 1.0 { FilterQuality::Bilinear } else { FilterQuality::Nearest };
            view.draw_pixmap(0, 0, sp.as_ref(), &PixmapPaint { quality, ..Default::default() }, Transform::from_row(zoom, 0., 0., zoom, pan.0 as f32, pan.1 as f32), None);
        }
        let rect_px = |view: &mut Pixmap, x: f32, y: f32, w: f32, h: f32, c: (u8, u8, u8)| {
            fill(view, x.round() as i32, y.round() as i32, (w.round() as i32).max(1), (h.round() as i32).max(1), c);
        };
        let frame = |view: &mut Pixmap, x: f32, y: f32, w: f32, h: f32, c: (u8, u8, u8), t: f32| {
            rect_px(view, x, y, w, t, c); rect_px(view, x, y + h - t, w, t, c); rect_px(view, x, y, t, h, c); rect_px(view, x + w - t, y, t, h, c);
        };
        frame(view, pan.0 as f32 - 1., pan.1 as f32 - 1., screen.0 as f32 * zoom + 2., screen.1 as f32 * zoom + 2., (39, 39, 42), 1.);
        if let Some(r) = sel_rect {
            let (x, y, w, h) = (pan.0 as f32 + r.x as f32 * zoom, pan.1 as f32 + r.y as f32 * zoom, r.w as f32 * zoom, r.h as f32 * zoom);
            frame(view, x, y, w, h, (255, 146, 72), 2.);
            if !sel_locked { for (_, fx, fy) in HANDLES { let (hx, hy) = (x + w * fx - 4., y + h * fy - 4.); rect_px(view, hx - 1., hy - 1., 10., 10., (255, 146, 72)); rect_px(view, hx, hy, 8., 8., (255, 255, 255)); } }
        }
        if let Some(gx) = guides.0 { rect_px(view, pan.0 as f32 + gx as f32 * zoom, 0., 1., h as f32, (255, 79, 163)); }
        if let Some(gy) = guides.1 { rect_px(view, 0., pan.1 as f32 + gy as f32 * zoom, w as f32, 1., (255, 79, 163)); }
        Some((view.data(), w, h))
    }

    // ------------------------------------------------------------ input
    pub fn to_world_pub(&self, sx: f64, sy: f64) -> (f64, f64) { self.to_world(sx, sy) }
    fn to_world(&self, sx: f64, sy: f64) -> (f64, f64) { ((sx - self.pan.0) / self.zoom, (sy - self.pan.1) / self.zoom) }
    fn parent_rect(&self, uid: u64) -> Rect {
        match parent_uid(&self.doc.root, uid, None) { Some(Some(p)) => self.rects.get(&p).copied().unwrap_or_default(), _ => Rect { x: 0, y: 0, w: self.doc.screen.0, h: self.doc.screen.1 } }
    }
    fn handle_at(&self, sx: f64, sy: f64) -> Option<&'static str> {
        let uid = self.selected?;
        if find(&self.doc.root, uid)?.locked { return None; }
        let r = self.rects.get(&uid)?;
        for (n, fx, fy) in HANDLES {
            let hx = self.pan.0 + (r.x as f64 + r.w as f64 * fx as f64) * self.zoom;
            let hy = self.pan.1 + (r.y as f64 + r.h as f64 * fy as f64) * self.zoom;
            if (sx - hx).abs() <= 7. && (sy - hy).abs() <= 7. { return Some(n); }
        }
        None
    }

    /// Write a rect back into props, keeping % units where a property already used them.
    fn commit(&mut self, uid: u64, r: Rect, parent: Rect, only: &[&str]) {
        let Some(c) = find_mut(&mut self.doc.root, uid) else { return };
        let mut put = |key: &str, px: i32, reference: i32| {
            if !only.is_empty() && !only.contains(&key) { return; }
            let pct = c.p(key).contains('%');
            let v = if pct { format!("{}%", ((px as f64 / reference.max(1) as f64) * 10000.0).round() / 100.0) } else { px.to_string() };
            c.props.insert(key.into(), v);
        };
        put("left", r.x - parent.x, parent.w); put("top", r.y - parent.y, parent.h);
        put("width", r.w, parent.w); put("height", r.h, parent.h);
    }

    fn snap_to(&mut self, uid: u64, r: Rect, parent: Rect) -> (i32, i32) {
        let t = 6.0 / self.zoom;
        self.guides = (None, None);
        let mut xs = vec![parent.x, parent.x + parent.w / 2, parent.x + parent.w];
        let mut ys = vec![parent.y, parent.y + parent.h / 2, parent.y + parent.h];
        for (id, q) in &self.rects { if *id != uid { xs.extend([q.x, q.x + q.w / 2, q.x + q.w]); ys.extend([q.y, q.y + q.h / 2, q.y + q.h]); } }
        let (mut bx, mut by, mut dx, mut dy) = (t, t, 0, 0);
        for e in [r.x, r.x + r.w / 2, r.x + r.w] { for v in &xs { let d = (*v - e).abs() as f64; if d < bx { bx = d; dx = *v - e; self.guides.0 = Some(*v); } } }
        for e in [r.y, r.y + r.h / 2, r.y + r.h] { for v in &ys { let d = (*v - e).abs() as f64; if d < by { by = d; dy = *v - e; self.guides.1 = Some(*v); } } }
        (dx, dy)
    }

    pub fn pointer_down(&mut self, sx: f64, sy: f64, middle: bool) {
        self.ensure_layout();
        let (wx, wy) = self.to_world(sx, sy);
        if middle || self.space { self.drag = Some(Drag { kind: DragKind::Pan, handle: "", sx, sy, start: Rect::default(), pan0: self.pan, moved: false, uid: 0, parent: Rect::default() }); return; }
        if let (Some(h), Some(uid)) = (self.handle_at(sx, sy), self.selected) {
            let start = self.rects.get(&uid).copied().unwrap_or_default();
            self.drag = Some(Drag { kind: DragKind::Resize, handle: h, sx: wx, sy: wy, start, pan0: (0., 0.), moved: false, uid, parent: self.parent_rect(uid) });
            return;
        }
        let hit = self.scene.hit_test(&self.doc, &self.rects, wx as i32, wy as i32);
        self.selected = hit;
        if let Some(uid) = hit {
            if !find(&self.doc.root, uid).map(|c| c.locked).unwrap_or(true) {
                let start = self.rects.get(&uid).copied().unwrap_or_default();
                self.drag = Some(Drag { kind: DragKind::Move, handle: "", sx: wx, sy: wy, start, pan0: (0., 0.), moved: false, uid, parent: self.parent_rect(uid) });
            }
        }
        self.touch();
    }

    /// Returns true when the document changed (so panels should refresh).
    pub fn pointer_move(&mut self, sx: f64, sy: f64, alt: bool) -> bool {
        let (wx, wy) = self.to_world(sx, sy);
        let Some(d) = self.drag.as_mut() else { return false };
        if d.kind == DragKind::Pan { self.pan = (d.pan0.0 + (sx - d.sx), d.pan0.1 + (sy - d.sy)); return false; }
        let (dx, dy) = (wx - d.sx, wy - d.sy);
        if !d.moved {
            if (dx * dx + dy * dy).sqrt() * self.zoom < 3.0 { return false; }
            d.moved = true;
            let snap = self.snap();
            self.undo.push(snap); self.redo.clear();
        }
        let d = self.drag.as_ref().unwrap();
        let (s, par, uid, handle, kind_move) = (d.start, d.parent, d.uid, d.handle, d.kind == DragKind::Move);
        let mut r = s;
        if kind_move {
            r.x = (s.x as f64 + dx).round() as i32; r.y = (s.y as f64 + dy).round() as i32;
            if !alt { let (sx2, sy2) = self.snap_to(uid, r, par); r.x += sx2; r.y += sy2; }
        } else {
            if handle.contains('e') { r.w = ((s.w as f64 + dx).round() as i32).max(1); }
            if handle.contains('s') { r.h = ((s.h as f64 + dy).round() as i32).max(1); }
            if handle.contains('w') { r.x = (s.x as f64 + dx).round() as i32; r.w = ((s.w as f64 - dx).round() as i32).max(1); }
            if handle.contains('n') { r.y = (s.y as f64 + dy).round() as i32; r.h = ((s.h as f64 - dy).round() as i32).max(1); }
        }
        self.commit(uid, r, par, if kind_move { &["left", "top"] } else { &[] });
        self.touch();
        self.rects = self.scene.layout(&self.doc);
        true
    }
    pub fn pointer_up(&mut self) -> bool { let moved = self.drag.as_ref().map(|d| d.moved).unwrap_or(false); self.drag = None; self.guides = (None, None); moved }

    pub fn wheel(&mut self, dx: f64, dy: f64, ctrl: bool, sx: f64, sy: f64) {
        if ctrl {
            let (wx, wy) = self.to_world(sx, sy);
            let nz = (self.zoom * (-dy * 0.0015).exp()).clamp(0.05, 4.0);
            self.pan = (sx - wx * nz, sy - wy * nz); self.zoom = nz;
        } else { self.pan = (self.pan.0 - dx, self.pan.1 - dy); }
    }

    /// Returns true when the document changed.
    pub fn key(&mut self, key: &str, ctrl: bool, shift: bool) -> bool {
        if ctrl { match key { "z" => { if shift { self.redo() } else { self.undo() } return true; } "y" => { self.redo(); return true; } _ => {} } }
        let Some(uid) = self.selected else { return false };
        match key {
            "d" if ctrl => self.duplicate(uid),
            "Delete" | "Backspace" => self.remove(uid),
            "Escape" => { self.selected = None; self.touch(); }
            "[" => self.reorder(uid, -1), "]" => self.reorder(uid, 1),
            "Left" | "Right" | "Up" | "Down" => {
                self.ensure_layout();
                let n = if shift { 10 } else { 1 };
                let Some(mut r) = self.rects.get(&uid).copied() else { return false };
                match key { "Left" => r.x -= n, "Right" => r.x += n, "Up" => r.y -= n, _ => r.y += n }
                let par = self.parent_rect(uid);
                self.checkpoint(); self.commit(uid, r, par, &["left", "top"]); self.touch();
            }
            _ => return false,
        }
        true
    }
}
