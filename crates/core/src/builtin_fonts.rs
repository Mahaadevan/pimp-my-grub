//! Ready-made GRUB fonts (PF2), so a theme can use a real font without `grub-mkfont` (which needs GRUB's tools installed).
//! Generated once with `grub-mkfont -s <16|24|32|48>` from Inter, JetBrains Mono and DejaVu Sans (Latin, Latin Extended-A and
//! common punctuation). Licences: see `assets/fonts/LICENSES.md`.

pub struct BuiltinFont {
    /// The name GRUB uses in `theme.txt`, e.g. "Inter Regular 24" (read from the font itself).
    pub name: &'static str,
    pub file: &'static str,
    pub data: &'static [u8],
}

pub static FONTS: &[BuiltinFont] = &[
    BuiltinFont { name: "DejaVu Sans Bold 16", file: "dejavu-sans-bold-16.pf2", data: include_bytes!("../assets/fonts/dejavu-sans-bold-16.pf2") },
    BuiltinFont { name: "DejaVu Sans Bold 24", file: "dejavu-sans-bold-24.pf2", data: include_bytes!("../assets/fonts/dejavu-sans-bold-24.pf2") },
    BuiltinFont { name: "DejaVu Sans Bold 32", file: "dejavu-sans-bold-32.pf2", data: include_bytes!("../assets/fonts/dejavu-sans-bold-32.pf2") },
    BuiltinFont { name: "DejaVu Sans Bold 48", file: "dejavu-sans-bold-48.pf2", data: include_bytes!("../assets/fonts/dejavu-sans-bold-48.pf2") },
    BuiltinFont { name: "DejaVu Sans Regular 16", file: "dejavu-sans-regular-16.pf2", data: include_bytes!("../assets/fonts/dejavu-sans-regular-16.pf2") },
    BuiltinFont { name: "DejaVu Sans Regular 24", file: "dejavu-sans-regular-24.pf2", data: include_bytes!("../assets/fonts/dejavu-sans-regular-24.pf2") },
    BuiltinFont { name: "DejaVu Sans Regular 32", file: "dejavu-sans-regular-32.pf2", data: include_bytes!("../assets/fonts/dejavu-sans-regular-32.pf2") },
    BuiltinFont { name: "DejaVu Sans Regular 48", file: "dejavu-sans-regular-48.pf2", data: include_bytes!("../assets/fonts/dejavu-sans-regular-48.pf2") },
    BuiltinFont { name: "Inter Bold 16", file: "inter-bold-16.pf2", data: include_bytes!("../assets/fonts/inter-bold-16.pf2") },
    BuiltinFont { name: "Inter Bold 24", file: "inter-bold-24.pf2", data: include_bytes!("../assets/fonts/inter-bold-24.pf2") },
    BuiltinFont { name: "Inter Bold 32", file: "inter-bold-32.pf2", data: include_bytes!("../assets/fonts/inter-bold-32.pf2") },
    BuiltinFont { name: "Inter Bold 48", file: "inter-bold-48.pf2", data: include_bytes!("../assets/fonts/inter-bold-48.pf2") },
    BuiltinFont { name: "Inter Regular 16", file: "inter-regular-16.pf2", data: include_bytes!("../assets/fonts/inter-regular-16.pf2") },
    BuiltinFont { name: "Inter Regular 24", file: "inter-regular-24.pf2", data: include_bytes!("../assets/fonts/inter-regular-24.pf2") },
    BuiltinFont { name: "Inter Regular 32", file: "inter-regular-32.pf2", data: include_bytes!("../assets/fonts/inter-regular-32.pf2") },
    BuiltinFont { name: "Inter Regular 48", file: "inter-regular-48.pf2", data: include_bytes!("../assets/fonts/inter-regular-48.pf2") },
    BuiltinFont { name: "JetBrains Mono Bold 16", file: "jetbrains-mono-bold-16.pf2", data: include_bytes!("../assets/fonts/jetbrains-mono-bold-16.pf2") },
    BuiltinFont { name: "JetBrains Mono Bold 24", file: "jetbrains-mono-bold-24.pf2", data: include_bytes!("../assets/fonts/jetbrains-mono-bold-24.pf2") },
    BuiltinFont { name: "JetBrains Mono Bold 32", file: "jetbrains-mono-bold-32.pf2", data: include_bytes!("../assets/fonts/jetbrains-mono-bold-32.pf2") },
    BuiltinFont { name: "JetBrains Mono Bold 48", file: "jetbrains-mono-bold-48.pf2", data: include_bytes!("../assets/fonts/jetbrains-mono-bold-48.pf2") },
    BuiltinFont { name: "JetBrains Mono Regular 16", file: "jetbrains-mono-regular-16.pf2", data: include_bytes!("../assets/fonts/jetbrains-mono-regular-16.pf2") },
    BuiltinFont { name: "JetBrains Mono Regular 24", file: "jetbrains-mono-regular-24.pf2", data: include_bytes!("../assets/fonts/jetbrains-mono-regular-24.pf2") },
    BuiltinFont { name: "JetBrains Mono Regular 32", file: "jetbrains-mono-regular-32.pf2", data: include_bytes!("../assets/fonts/jetbrains-mono-regular-32.pf2") },
    BuiltinFont { name: "JetBrains Mono Regular 48", file: "jetbrains-mono-regular-48.pf2", data: include_bytes!("../assets/fonts/jetbrains-mono-regular-48.pf2") },
];

pub fn find(name: &str) -> Option<&'static BuiltinFont> { FONTS.iter().find(|f| f.name == name) }
pub fn names() -> impl Iterator<Item = &'static str> { FONTS.iter().map(|f| f.name) }
