//! Fonts on this computer -> GRUB PF2 fonts, without GRUB's `grub-mkfont`.
//! `list_system_fonts` finds the installed fonts; `to_pf2` rasterises one at a pixel size into a PF2 bitmap font
//! (1 bit per pixel, like grub-mkfont's output) covering Latin, Greek, Cyrillic and common punctuation.
use serde::Serialize;
use std::path::Path;
use std::process::Command;

#[derive(Clone, Serialize, Debug, PartialEq)]
pub struct SysFont { pub family: String, pub style: String, pub path: String, pub index: u32 }

fn wanted(cp: u32) -> bool {
    matches!(cp, 0x20..=0x7e | 0xa0..=0x17f | 0x370..=0x3ff | 0x400..=0x4ff | 0x2013..=0x2014 | 0x2018..=0x201d | 0x2022 | 0x2026 | 0x20ac)
}

fn section(out: &mut Vec<u8>, tag: &[u8; 4], body: &[u8]) { out.extend_from_slice(tag); out.extend_from_slice(&(body.len() as u32).to_be_bytes()); out.extend_from_slice(body); }
fn cstr(s: &str) -> Vec<u8> { let mut v = s.as_bytes().to_vec(); v.push(0); v }

/// Rasterise `data` (TTF/OTF/TTC) at `size` px into a PF2. The font is named "<family> <style> <size>" like grub-mkfont does.
pub fn to_pf2(data: &[u8], index: u32, size: u32, family: &str, style: &str) -> Result<Vec<u8>, String> {
    if !(8..=160).contains(&size) { return Err("font size must be between 8 and 160".into()); }
    let font = fontdue::Font::from_bytes(data, fontdue::FontSettings { collection_index: index, ..Default::default() }).map_err(|e| e.to_string())?;
    let px = size as f32;
    let lm = font.horizontal_line_metrics(px).ok_or("this font has no horizontal metrics")?;
    let (asc, desc) = (lm.ascent.ceil() as i32, (-lm.descent).ceil() as i32);
    struct G { cp: u32, w: i32, h: i32, xo: i32, yo: i32, dw: i32, bits: Vec<u8> }
    let mut glyphs: Vec<G> = vec![];
    for cp in (0x20u32..=0x20ac).filter(|c| wanted(*c)) {
        let Some(ch) = char::from_u32(cp) else { continue };
        if cp != 0x20 && font.lookup_glyph_index(ch) == 0 { continue; }
        let (m, cov) = font.rasterize(ch, px);
        let (w, h) = (m.width as i32, m.height as i32);
        let mut bits = vec![0u8; ((w * h + 7) / 8) as usize];
        for (i, c) in cov.iter().enumerate() { if *c >= 100 { bits[i >> 3] |= 0x80 >> (i & 7); } }
        glyphs.push(G { cp, w, h, xo: m.xmin, yo: m.ymin, dw: m.advance_width.round() as i32, bits });
    }
    if glyphs.len() < 20 { return Err("this font has almost no Latin letters, so it cannot be used for a GRUB menu".into()); }
    let name = if style.is_empty() { format!("{family} {size}") } else { format!("{family} {style} {size}") };
    let maxw = glyphs.iter().map(|g| g.dw.max(g.w + g.xo.max(0))).max().unwrap_or(size as i32).max(1);
    let maxh = glyphs.iter().map(|g| g.h).max().unwrap_or(size as i32).max(1);
    let bold = (style.to_ascii_lowercase() + &family.to_ascii_lowercase()).contains("bold");
    let italic = { let s = (style.to_ascii_lowercase() + &family.to_ascii_lowercase()); s.contains("italic") || s.contains("oblique") };
    let mut head = Vec::new();
    section(&mut head, b"FILE", b"PFF2");
    section(&mut head, b"NAME", &cstr(&name));
    section(&mut head, b"FAMI", &cstr(family));
    section(&mut head, b"WEIG", &cstr(if bold { "bold" } else { "normal" }));
    section(&mut head, b"SLAN", &cstr(if italic { "italic" } else { "normal" }));
    for (tag, v) in [(b"PTSZ", size as i32), (b"MAXW", maxw), (b"MAXH", maxh), (b"ASCE", asc), (b"DESC", desc)] { section(&mut head, tag, &(v.clamp(0, 65535) as u16).to_be_bytes()); }
    let chix_len = glyphs.len() * 9;
    let data_start = head.len() + 8 + chix_len + 8; // + CHIX header + body + DATA header
    let mut chix = Vec::with_capacity(chix_len);
    let mut body = Vec::new();
    for g in &glyphs {
        chix.extend_from_slice(&g.cp.to_be_bytes()); chix.push(0);
        chix.extend_from_slice(&((data_start + body.len()) as u32).to_be_bytes());
        body.extend_from_slice(&(g.w as u16).to_be_bytes()); body.extend_from_slice(&(g.h as u16).to_be_bytes());
        body.extend_from_slice(&(g.xo as i16).to_be_bytes()); body.extend_from_slice(&(g.yo as i16).to_be_bytes());
        body.extend_from_slice(&(g.dw as i16).to_be_bytes()); body.extend_from_slice(&g.bits);
    }
    section(&mut head, b"CHIX", &chix);
    head.extend_from_slice(b"DATA"); head.extend_from_slice(&0xffff_ffffu32.to_be_bytes());
    debug_assert_eq!(head.len(), data_start);
    head.extend_from_slice(&body);
    Ok(head)
}

/// Installed fonts (TTF/OTF/TTC). Uses fontconfig's `fc-list` when present; otherwise walks the usual font folders.
pub fn list_system_fonts() -> Vec<SysFont> {
    let mut out: Vec<SysFont> = vec![];
    if let Ok(o) = Command::new("fc-list").args(["--format", "%{file}\t%{family[0]}\t%{style[0]}\t%{index}\n"]).output() {
        for l in String::from_utf8_lossy(&o.stdout).lines() {
            let p: Vec<&str> = l.split('\t').collect();
            if p.len() < 4 { continue; }
            let ext = Path::new(p[0]).extension().map(|e| e.to_string_lossy().to_ascii_lowercase()).unwrap_or_default();
            if !["ttf", "otf", "ttc", "otc"].contains(&ext.as_str()) { continue; }
            let (family, style) = (p[1].split(',').next().unwrap_or("").trim().to_string(), p[2].split(',').next().unwrap_or("Regular").trim().to_string());
            if family.is_empty() { continue; }
            out.push(SysFont { family, style: if style.is_empty() { "Regular".into() } else { style }, path: p[0].to_string(), index: p[3].trim().parse::<u32>().unwrap_or(0) & 0xffff });
        }
    }
    if out.is_empty() {
        let mut dirs: Vec<std::path::PathBuf> = vec!["/usr/share/fonts".into(), "/usr/local/share/fonts".into()];
        if let Some(h) = std::env::var_os("HOME") { dirs.push(Path::new(&h).join(".local/share/fonts")); dirs.push(Path::new(&h).join(".fonts")); }
        fn walk(d: &Path, depth: usize, out: &mut Vec<SysFont>) {
            if depth > 6 || out.len() > 5000 { return; }
            let Ok(rd) = std::fs::read_dir(d) else { return };
            for e in rd.flatten() {
                let p = e.path();
                if p.is_dir() { walk(&p, depth + 1, out); continue; }
                let ext = p.extension().map(|e| e.to_string_lossy().to_ascii_lowercase()).unwrap_or_default();
                if !["ttf", "otf"].contains(&ext.as_str()) { continue; }
                let stem = p.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
                let (fam, sty) = stem.split_once('-').map(|(a, b)| (a.to_string(), b.to_string())).unwrap_or((stem.clone(), "Regular".into()));
                out.push(SysFont { family: fam, style: sty, path: p.to_string_lossy().into_owned(), index: 0 });
            }
        }
        for d in dirs { walk(&d, 0, &mut out); }
    }
    out.sort_by(|a, b| (a.family.to_lowercase(), &a.style).cmp(&(b.family.to_lowercase(), &b.style)));
    out.dedup_by(|a, b| a.family == b.family && a.style == b.style);
    out
}

/// Convert a font file whose names we do not know: the name inside the font (or `fallback`) becomes the PF2's name.
pub fn to_pf2_named_by_font(data: &[u8], size: u32, fallback: &str) -> Result<Vec<u8>, String> {
    let font = fontdue::Font::from_bytes(data, fontdue::FontSettings::default()).map_err(|e| e.to_string())?;
    let name = font.name().map(|n| n.to_string()).filter(|n| !n.trim().is_empty()).unwrap_or_else(|| fallback.to_string());
    to_pf2(data, 0, size, &name, "")
}
