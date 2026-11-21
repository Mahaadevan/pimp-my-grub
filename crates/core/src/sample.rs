//! The demo theme that ships with the app ("Midnight", the same files as `examples/midnight`), so the editor can offer a
//! real, finished theme with one click instead of an empty canvas.
use std::collections::BTreeMap;

fn entry(name: &'static str, bytes: &'static [u8]) -> (String, Vec<u8>) { (name.to_string(), bytes.to_vec()) }

pub fn files() -> BTreeMap<String, Vec<u8>> {
    let mut m = BTreeMap::new();
    for (k, v) in [
        entry("theme.txt", include_bytes!("../../../examples/midnight/theme.txt")),
        entry("background.png", include_bytes!("../../../examples/midnight/background.png")),
        entry("bar_c.png", include_bytes!("../../../examples/midnight/bar_c.png")),
        entry("fill_c.png", include_bytes!("../../../examples/midnight/fill_c.png")),
        entry("select_c.png", include_bytes!("../../../examples/midnight/select_c.png")),
    ] {
        m.insert(k, v);
    }
    m
}
