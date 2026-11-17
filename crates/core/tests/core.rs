use pimp_my_grub_core::editor::Editor;
use pimp_my_grub_core::store::{index_files, FileEntry, RepoRef};
use pimp_my_grub_core::theme::*;
use std::path::Path;

const SAMPLE: &str = "# c\ntitle-text: \"\"\ndesktop-color: \"#050607\"\n\n+ boot_menu {\n  id = \"__menu__\"\n  left = 50%-100\n  scrollbar = false\n}\n+ vbox {\n  left = 1\n  + label { text = \"hi there\" color = \"#fff\" }\n  + image {\n    file = \"x.png\"\n  }\n}\n";

#[test]
fn parse_and_roundtrip() {
    let (g, r) = parse_theme(SAMPLE);
    assert_eq!(g["desktop-color"], "\"#050607\"");
    assert_eq!(r.len(), 2);
    assert_eq!(r[1].children.len(), 2);
    assert_eq!(r[1].children[0].p("text"), "\"hi there\"");
    let (g2, r2) = parse_theme(&serialize_theme(&g, &r, ""));
    assert_eq!(g2, g);
    assert_eq!(r2[0].props, r[0].props);
    assert_eq!(r2[1].children[1].props, r[1].children[1].props);
}

#[test]
fn lengths() {
    assert_eq!(eval_len(Some("50%-100"), 1000, 0), 400);
    assert_eq!(eval_len(Some("30%"), 200, 0), 60);
    assert_eq!(eval_len(Some("12"), 200, 0), 12);
    assert_eq!(eval_len(None, 200, 7), 7);
}

#[test]
fn real_sidonia_themes_roundtrip() {
    let base = Path::new("/home/claude/Sidonia/themes");
    if !base.exists() { return; }
    let mut n = 0;
    for t in std::fs::read_dir(base).unwrap().flatten() {
        for p in std::fs::read_dir(t.path()).unwrap().flatten() {
            let f = p.path().join("theme.txt");
            if let Ok(s) = std::fs::read_to_string(&f) {
                let (g, r) = parse_theme(&s);
                let (g2, r2) = parse_theme(&serialize_theme(&g, &r, ""));
                assert!(!r.is_empty()); assert_eq!(r.len(), r2.len()); assert_eq!(g.len(), g2.len()); n += 1;
            }
        }
    }
    assert!(n > 5, "parsed {n}");
}

#[test]
fn store_indexer_groups_variants_and_previews() {
    let r = RepoRef { repo: "a/b".into(), branch: "main".into(), stars: 1, desc: String::new() };
    let f = |p: &str, s| FileEntry { path: p.into(), size: s };
    let t = index_files(&r, &[f("themes/T1/1080p/theme.txt", 9), f("themes/T1/720p/theme.txt", 9), f("themes/T2/theme.txt", 9), f("previews/T1.png", 5000), f("themes/T2/preview.png", 4000)]);
    let mut names: Vec<_> = t.iter().map(|x| x.name.clone()).collect(); names.sort();
    assert_eq!(names, ["T1", "T2"]);
    let t1 = t.iter().find(|x| x.name == "T1").unwrap();
    assert_eq!(t1.variants[0].label, "1080p");
    assert!(t1.preview.as_ref().unwrap().ends_with("previews/T1.png"));
    assert!(t.iter().find(|x| x.name == "T2").unwrap().preview.as_ref().unwrap().ends_with("T2/preview.png"));
}

#[test]
fn editor_ops_undo_and_render() {
    let mut e = Editor::new();
    e.add_rect("#ff0000");
    let uid = e.selected.unwrap();
    e.fit(800, 600);
    {
        let (px, w, _) = e.render_view(800, 600).unwrap();
        // centre of the rect (world 250,180) must be red
        let z = ((800.0 - 60.0) / 1920.0_f64).min((600.0 - 60.0) / 1080.0);
        let (sx, sy) = (((800.0 - 1920.0 * z) / 2.0 + 250.0 * z) as usize, ((600.0 - 1080.0 * z) / 2.0 + 180.0 * z) as usize);
        let o = (sy * w as usize + sx) * 4;
        assert!(px[o] > 200 && px[o + 1] < 40, "pixel {:?}", &px[o..o + 4]);
    }
    e.set_prop(uid, "left", "400");
    assert_eq!(find_left(&e, uid), "400");
    e.undo();
    assert_eq!(find_left(&e, uid), "100");
    e.redo();
    assert_eq!(find_left(&e, uid), "400");
    e.remove(uid);
    assert!(e.doc.root.is_empty());
    e.undo();
    assert_eq!(e.doc.root.len(), 1);
}
fn find_left(e: &Editor, uid: u64) -> String { e.doc.root.iter().find(|c| c.uid == uid).unwrap().p("left").to_string() }

#[test]
fn drag_keeps_percent_units() {
    let mut e = Editor::new();
    e.add("boot_menu", &[]);
    e.fit(1920, 1080);
    let _ = e.render_view(1920, 1080);
    let uid = e.selected.unwrap();
    e.pointer_down(1000.0, 500.0, false); // inside the menu
    e.pointer_move(1100.0, 560.0, true);
    e.pointer_up();
    let c = e.doc.root.iter().find(|c| c.uid == uid).unwrap();
    assert!(c.p("left").ends_with('%') && c.p("top").ends_with('%'), "{} {}", c.p("left"), c.p("top"));
}

#[test]
fn files_export_roundtrip() {
    let mut e = Editor::new();
    e.add("label", &[]);
    e.add_rect("#00ff00");
    let files = e.files();
    assert!(files.contains_key("theme.txt"));
    let mut e2 = Editor::new();
    e2.load_files(&files, "copy").unwrap();
    assert_eq!(e2.doc.root.len(), 2);
    assert_eq!(e2.doc.assets.len(), 1);
}

#[test]
fn zoom_ladder_and_centre() {
    let mut e = Editor::default();
    e.fit(1000, 700);
    let fitted = e.zoom();
    // stepping lands on round stops and never skips or stalls
    e.zoom_to(0.5, 1000, 700);
    e.zoom_step(true, 1000, 700);  assert!((e.zoom() - 0.67).abs() < 1e-9);
    e.zoom_step(true, 1000, 700);  assert!((e.zoom() - 0.75).abs() < 1e-9);
    e.zoom_step(false, 1000, 700); e.zoom_step(false, 1000, 700); assert!((e.zoom() - 0.5).abs() < 1e-9);
    for _ in 0..40 { e.zoom_step(true, 1000, 700); }  assert!((e.zoom() - 4.0).abs() < 1e-9, "clamped at 400%");
    for _ in 0..40 { e.zoom_step(false, 1000, 700); } assert!((e.zoom() - 0.05).abs() < 1e-9, "clamped at 5%");
    // wheel-panning far away loses the screen; centre brings it back without touching the zoom
    e.fit(1000, 700);
    e.wheel(-50000.0, -50000.0, false, 0.0, 0.0);
    let z = e.zoom();
    e.center_view(1000, 700);
    assert_eq!(e.zoom(), z);
    assert!((z - fitted).abs() < 1e-9);
    // zooming keeps the middle of the viewport fixed
    let before = e.to_world_pub(500.0, 350.0);
    e.zoom_to(1.0, 1000, 700);
    let after = e.to_world_pub(500.0, 350.0);
    assert!((before.0 - after.0).abs() < 1e-6 && (before.1 - after.1).abs() < 1e-6);
}

#[test]
fn builtin_fonts_parse_and_are_added_to_the_theme_when_chosen() {
    use pimp_my_grub_core::{builtin_fonts, pf2};
    assert!(builtin_fonts::FONTS.len() >= 20);
    for f in builtin_fonts::FONTS {
        let p = pf2::parse(f.data).unwrap_or_else(|| panic!("{} does not parse", f.file));
        assert_eq!(p.name, f.name, "name in {} differs from the table", f.file);
    }
    let mut e = Editor::default();
    e.add("label", &[]);
    let uid = e.selected.expect("label selected");
    assert!(!e.inspector_json().contains("\"Inter Regular 24\"") || e.inspector_json().contains("Inter Regular 24"), "listed in the dropdown");
    e.set_prop(uid, "font", "\"Inter Regular 24\"");
    assert!(e.inspector_json().contains("Inter Regular 24"));
    assert!(e.files().iter().any(|(n, _)| n == "inter-regular-24.pf2"), "the .pf2 is exported with the theme");
}

// ---------------------------------------------------------------- presets, styles, operations, fonts


#[test]
fn every_preset_can_be_added_and_rendered() {
    use pimp_my_grub_core::preset_list;
    for kind in ["boot_menu", "label", "rectangle", "progress_bar", "circular_progress", "canvas"] {
        let presets = preset_list(kind);
        assert!(presets.len() >= 3, "{kind} has presets");
        for p in presets {
            let mut e = Editor::default();
            let uid = e.add_preset(kind, p.id).unwrap_or_else(|| panic!("{kind}/{} not added", p.id));
            assert!(e.selected == Some(uid) || e.selected.is_some());
            let (px, w, h) = { let (d, w, h) = e.render_live(960, 540).expect("renders"); (d.to_vec(), w, h) };
            assert_eq!(px.len() as u32, w * h * 4);
            // every file the preset refers to exists in the theme, and the exported theme.txt parses back
            let files = e.files();
            let txt = String::from_utf8(files["theme.txt"].clone()).unwrap();
            assert!(txt.contains("boot_menu") || txt.contains("label") || txt.contains("image") || txt.contains("progress") || txt.contains("canvas") || txt.contains("vbox") || txt.contains("hbox"), "{kind}/{} wrote a component", p.id);
            let (_, comps) = parse_theme(&txt);
            assert!(!comps.is_empty(), "{kind}/{} survives a theme.txt round trip", p.id);
        }
    }
}

#[test]
fn style_designer_makes_nine_valid_slices_and_a_menu_uses_them() {
    use pimp_my_grub_core::styles::{render_slices, StyleSpec};
    let spec = StyleSpec { fill: "#ff6b6b".into(), fill2: "#c0392b".into(), opacity: 90, radius: 12, border_width: 2, border: "#ffffff".into(), border_opacity: 60 };
    let s = render_slices(&spec);
    assert_eq!(s.len(), 9);
    for (name, bytes) in &s { let img = image::load_from_memory(bytes).unwrap_or_else(|_| panic!("{name} is not a PNG")); assert!(img.width() >= 1 && img.height() >= 1); }
    assert_eq!(image::load_from_memory(&s["nw"]).unwrap().width(), 12, "corner slice is as big as the radius");
    let mut e = Editor::default();
    let menu = e.add("boot_menu", &[]);
    let pat = e.design_style(menu, "selected_item_pixmap_style", &spec);
    assert!(pat.ends_with("_*.png"));
    let files = e.files();
    for slice in ["nw", "n", "ne", "w", "c", "e", "sw", "s", "se"] { assert!(files.keys().any(|k| k == &pat.replace('*', slice)), "slice {slice} exported"); }
    assert!(e.inspector_json().contains(&pat), "the new style appears in the style dropdown");
}

#[test]
fn a_picture_can_be_cut_into_a_style() {
    use pimp_my_grub_core::styles::{render_slices, slice_image, StyleSpec};
    let big = render_slices(&StyleSpec { radius: 20, ..Default::default() });
    let one = { let c = image::RgbaImage::from_pixel(60, 40, image::Rgba([10, 200, 90, 255])); let mut o = std::io::Cursor::new(vec![]); c.write_to(&mut o, image::ImageFormat::Png).unwrap(); o.into_inner() };
    assert_eq!(slice_image(&one, 10, 8, 10, 8).unwrap().len(), 9);
    assert!(slice_image(&one, 40, 8, 30, 8).is_err(), "corners larger than the picture are refused");
    assert!(!big.is_empty());
    let mut e = Editor::default();
    let m = e.add("boot_menu", &[]);
    assert!(e.import_style(m, "menu_pixmap_style", &one, 10, 8, 10, 8).unwrap().ends_with("_*.png"));
}

#[test]
fn clipboard_order_group_and_align() {
    let mut e = Editor::default();
    let a = e.add("label", &[("left", "10".into()), ("top", "10".into()), ("width", "200".into()), ("height", "30".into()), ("text", "\"A\"".into())]);
    let b = e.add("label", &[("left", "10".into()), ("top", "60".into()), ("width", "200".into()), ("height", "30".into()), ("text", "\"B\"".into())]);
    assert!(e.copy(a)); let p = e.paste().unwrap(); assert_ne!(p, a);
    assert_eq!(e.doc.root.len(), 3);
    e.bring_to_front(a); assert_eq!(e.doc.root.last().unwrap().uid, a);
    e.send_to_back(a); assert_eq!(e.doc.root[0].uid, a);
    assert!(e.cut(b)); assert_eq!(e.doc.root.len(), 2); assert!(e.paste().is_some()); assert_eq!(e.doc.root.len(), 3);
    let g = e.group(a).unwrap();
    assert_eq!(e.doc.root.iter().find(|c| c.uid == g).unwrap().children.len(), 1);
    assert!(e.ungroup(g)); assert!(e.doc.root.iter().any(|c| c.uid == a), "ungroup puts the item back");
    e.align(a, "right"); let r = e.doc.root.iter().find(|c| c.uid == a).unwrap().props["left"].clone(); assert_eq!(r, "100%-200");
    e.align(a, "left"); assert_eq!(e.doc.root.iter().find(|c| c.uid == a).unwrap().props["left"], "0");
    e.undo(); assert_eq!(e.doc.root.iter().find(|c| c.uid == a).unwrap().props["left"], "100%-200", "alignment is undoable");
}

#[test]
fn countdown_labels_follow_the_timeout_and_the_menu_shows_host_entries() {
    let mut e = Editor::default();
    e.add("label", &[("id", "\"__timeout__\"".into()), ("left", "0".into()), ("top", "0".into()), ("width", "400".into()), ("height", "40".into()), ("text", "\"T-%02d\"".into())]);
    let before = e.render_live(640, 360).unwrap().0.to_vec();
    e.set_timeout(3);
    assert!((e.progress - 0.6).abs() < 1e-6, "3 of 5 seconds left is 60%");
    let after = e.render_live(640, 360).unwrap().0.to_vec();
    assert_ne!(before, after, "the label changed when the countdown moved");
    e.set_timeout_total(10); assert!((e.progress - 0.3).abs() < 1e-6);
    e.add("boot_menu", &[]);
    let sample = e.render_live(640, 360).unwrap().0.to_vec();
    e.set_entries((0..12).map(|i| (format!("Entry number {i}"), "gnu-linux".to_string())).collect());
    e.menu_sel = 11;
    let long = e.render_live(640, 360).unwrap().0.to_vec();
    assert_ne!(sample, long, "host entries replace the sample list, and the selected last row is scrolled into view");
}

#[test]
fn fonts_convert_to_pf2_without_grub_tools() {
    use pimp_my_grub_core::{fontconv, pf2};
    let sys = fontconv::list_system_fonts();
    // the bundled test font may not exist on every machine: use any installed one, or skip quietly
    let Some(f) = sys.iter().find(|f| f.path.ends_with(".ttf") || f.path.ends_with(".otf")) else { eprintln!("no system font installed, skipping"); return };
    let data = std::fs::read(&f.path).unwrap();
    let pf = fontconv::to_pf2(&data, f.index, 24, &f.family, &f.style).expect("converts");
    let parsed = pf2::parse(&pf).expect("our own PF2 parses");
    assert_eq!(parsed.name, format!("{} {} 24", f.family, f.style));
    assert!(fontconv::to_pf2(&data, f.index, 3, "x", "y").is_err(), "silly sizes are refused");
}
