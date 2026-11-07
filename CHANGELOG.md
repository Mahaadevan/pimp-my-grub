# Changelog

## 0.2.1
- **Fix:** the app no longer fails silently when a Qt QML module is missing. It now prints what to install and exits
  with a non-zero code, so the launcher shows an error dialog instead of nothing.
- **Fix:** clicking the canvas no longer clears the selection (the canvas refresh used to call `select` with an empty id).
- **Fix:** previews show real text on systems without GRUB's `unicode.pf2` (a compact built-in font is used as fallback).
- **Fix:** builds with clang no longer fail (the GCC-only `-fpermissive` workaround was replaced by a proper constructor).
- **Fix:** opening a path with a `%` followed by a non-ASCII character could crash the app.
- **Fix:** taskbar/dock icon now matches the app (`StartupWMClass`, desktop file name).
- UI: styled dropdowns, checkboxes, dialogs, progress and busy indicators; toolbar labels stay next to their sliders;
  empty dropdowns read "None"; clearer message when the theme list cannot be loaded; version shown in the status bar.
- README screenshots retaken for the new look.

## 0.2.0-dev changes (included in 0.2.1)
- New app icon (monitor with wrench and screwdriver), installed at 512/256/128/64/48/32 px.
- New dark UI modelled on GrubStudio: near-black surfaces, hairline borders, orange `#ff9248` accent, brand header with
  underlined Editor/Store tabs, status bar, restyled panels, store cards and install dialog.
- The app now uses Qt Quick's Basic style with its own palette instead of following the desktop theme
  (set `QT_QUICK_CONTROLS_STYLE` to override).
- Editor canvas, selection frame and new-item defaults use the orange accent.

## 0.2.0
- Native rewrite: Qt 6 + Rust (no webview). Core engine in `crates/core`, Qt Quick shell in `crates/app`.
- Renamed to **Pimp my grub**.
- Software preview renderer with real PF2 fonts and 9-slice styles; editor with layers, snapping, undo/redo.
- Store with search, sorting, thumbnails, GitHub topic search.
- Reversible installer: backup, marked block, validated `grub.cfg` swap, automatic restore, polkit action.
- Packaging for deb, rpm, Arch and AppImage.

## 0.1.0 (prototype, discontinued)
- Tauri + Svelte + Canvas2D web-UI prototype.
