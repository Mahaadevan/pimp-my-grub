# Changelog

## Unreleased
- New app icon (monitor with wrench and screwdriver), installed at 512/256/128/64/48/32 px.
- New dark UI modelled on GrubStudio: near-black surfaces, hairline borders, orange `#ff9248` accent, brand header with
  underlined Editor/Store tabs, status bar, restyled panels, store cards and install dialog.
- The app now uses Qt Quick's Basic style with its own palette instead of following the desktop theme
  (set `QT_QUICK_CONTROLS_STYLE` to override).
- Editor canvas, selection frame and new-item defaults use the orange accent.
- README screenshots predate this restyle and still need to be retaken.

## 0.2.0
- Native rewrite: Qt 6 + Rust (no webview). Core engine in `crates/core`, Qt Quick shell in `crates/app`.
- Renamed to **Pimp my grub**.
- Software preview renderer with real PF2 fonts and 9-slice styles; editor with layers, snapping, undo/redo.
- Store with search, sorting, thumbnails, GitHub topic search.
- Reversible installer: backup, marked block, validated `grub.cfg` swap, automatic restore, polkit action.
- Packaging for deb, rpm, Arch and AppImage.

## 0.1.0 (prototype, discontinued)
- Tauri + Svelte + Canvas2D web-UI prototype.
