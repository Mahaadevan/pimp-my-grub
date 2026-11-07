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
