//! Pimp my GRUB engine. Everything except the Qt window lives here, so it can be unit-tested headlessly.
pub mod builtin_fonts;
pub mod editor;
pub use ops::preset_list;
pub mod fontconv;
pub mod grubcfg;
pub mod styles;
pub mod installer;
mod ops;
pub mod pf2;
pub mod render;
pub mod store;
pub mod theme;
