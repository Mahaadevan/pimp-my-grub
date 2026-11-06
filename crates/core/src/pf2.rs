//! PF2 (GRUB bitmap font) reader. Drawing the real glyphs makes previews match boot.
use std::collections::HashMap;
use tiny_skia::Pixmap;

pub struct Glyph { pub w: i32, pub h: i32, pub xo: i32, pub yo: i32, pub dw: i32, pub bits: Vec<u8> }
pub struct Pf2 { pub name: String, pub ascent: i32, pub descent: i32, pub maxw: i32, pub glyphs: HashMap<u32, Glyph> }

fn u16be(b: &[u8], o: usize) -> Option<u16> { Some(u16::from_be_bytes([*b.get(o)?, *b.get(o + 1)?])) }
fn u32be(b: &[u8], o: usize) -> Option<u32> { Some(u32::from_be_bytes([*b.get(o)?, *b.get(o + 1)?, *b.get(o + 2)?, *b.get(o + 3)?])) }

pub fn read_name(b: &[u8]) -> String {
    let mut p = 0;
    while p + 8 <= b.len() {
        let tag = &b[p..p + 4];
        let len = u32be(b, p + 4).unwrap_or(0) as usize;
        if tag == b"NAME" { return String::from_utf8_lossy(b.get(p + 8..p + 8 + len).unwrap_or(&[])).trim_end_matches('\0').to_string(); }
        if tag == b"CHIX" || tag == b"DATA" { break; }
        p += 8 + len;
    }
    String::new()
}

pub fn parse(b: &[u8]) -> Option<Pf2> {
    let (mut p, mut name, mut asc, mut desc, mut maxw) = (0usize, String::new(), 0, 0, 0);
    let (mut chix, mut chix_len, mut data) = (None, 0usize, None);
    while p + 8 <= b.len() {
        let tag = &b[p..p + 4];
        let mut len = u32be(b, p + 4)? as usize;
        let body = p + 8;
        match tag {
            b"NAME" => name = String::from_utf8_lossy(b.get(body..body + len)?).trim_end_matches('\0').to_string(),
            b"MAXW" => maxw = u16be(b, body)? as i32,
            b"ASCE" => asc = u16be(b, body)? as i32,
            b"DESC" => desc = u16be(b, body)? as i32,
            b"CHIX" => { chix = Some(body); chix_len = len; }
            b"DATA" => { data = Some(body); if len == 0xffff_ffff { len = b.len() - body; } }
            _ => {}
        }
        p = body + len;
        if tag == b"DATA" { break; }
    }
    let (chix, data) = (chix?, data?);
    let mut glyphs = HashMap::new();
    let mut i = chix;
    while i + 9 <= chix + chix_len {
        let cp = u32be(b, i)?; let off = u32be(b, i + 5)? as usize;
        let _ = data;
        let o = off; // CHIX offsets are absolute file offsets
        if let (Some(w), Some(h)) = (u16be(b, o), u16be(b, o + 2)) {
            let n = ((w as usize * h as usize) + 7) / 8;
            if let Some(bits) = b.get(o + 10..o + 10 + n) {
                glyphs.insert(cp, Glyph { w: w as i32, h: h as i32, xo: u16be(b, o + 4)? as i16 as i32, yo: u16be(b, o + 6)? as i16 as i32, dw: u16be(b, o + 8)? as i16 as i32, bits: bits.to_vec() });
            }
        }
        i += 9;
    }
    Some(Pf2 { name, ascent: asc, descent: desc, maxw, glyphs })
}

impl Pf2 {
    pub fn height(&self) -> i32 { self.ascent + self.descent }
    pub fn measure(&self, text: &str) -> i32 { text.chars().map(|c| self.glyphs.get(&(c as u32)).map(|g| g.dw).unwrap_or(self.maxw / 2)).sum() }
    /// Draw with the top-left of the text box at (x, y). Opaque colour, clipped to the pixmap.
    pub fn draw(&self, pix: &mut Pixmap, text: &str, x: i32, y: i32, rgb: (u8, u8, u8)) {
        let (pw, ph) = (pix.width() as i32, pix.height() as i32);
        let data = pix.data_mut();
        let mut pen = x;
        let base = y + self.ascent;
        for ch in text.chars() {
            let Some(g) = self.glyphs.get(&(ch as u32)) else { pen += self.maxw / 2; continue };
            let (gx, gy) = (pen + g.xo, base - g.yo - g.h);
            for r in 0..g.h {
                for c in 0..g.w {
                    let idx = (r * g.w + c) as usize;
                    if g.bits[idx >> 3] & (0x80 >> (idx & 7)) == 0 { continue; }
                    let (px, py) = (gx + c, gy + r);
                    if px < 0 || py < 0 || px >= pw || py >= ph { continue; }
                    let o = ((py * pw + px) * 4) as usize;
                    data[o] = rgb.0; data[o + 1] = rgb.1; data[o + 2] = rgb.2; data[o + 3] = 255;
                }
            }
            pen += g.dw;
        }
    }
}
