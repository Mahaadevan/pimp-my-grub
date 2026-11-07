# Changelog

## 0.3.2
- **New:** up/down arrow buttons on every numeric field: Timeout, position and size (X, Y, Width, Height), item height,
  padding, spacing, icon sizes, ticks, start angle, and the font size when adding a font. Click to step by 1 (Timeout by 5),
  hold to repeat, Shift for a bigger step; the Up/Down keys work too. Percentages (`30%`) and GRUB expressions (`50%-300`)
  are stepped as well (for an expression the pixel offset changes).
- **Fix:** the inspector no longer rebuilds all its fields after each edit, so a field keeps keyboard focus (Tab works) and
  a held arrow button keeps repeating.

## 0.3.1
- **New:** floating view controls on the editor canvas: zoom out (−), a zoom read-out (click it for 100 %), zoom in (+),
  fit to window and **Centre**. Centre puts the screen back in the middle of the view without changing the zoom, which
  recovers a canvas that was scrolled or panned out of sight. Zoom steps land on round values (25, 33, 50, 67, 75, 100 %, ...)
  and zoom around the middle of the view.
- **New:** keyboard shortcuts on the canvas: `+` / `-` zoom, `0` fit, `C` centre.
- The old Fit and 100 % buttons in the toolbar moved into the new control; "100 %" now also centres the screen.
- Test: zoom ladder, clamping and centring are covered by a unit test.

## 0.3.0
- **New:** theme detail view in the Store. Click a card (or its thumbnail) to see a large preview, the repository description,
  star count, a link to the GitHub page and the resolution choice, with Edit and Install buttons.
- **New:** the editor's Timeout preview is a typed number (0-100 %; Up/Down or the mouse wheel step by 5) instead of a slider.
- **New:** native file, folder and colour dialogs. The app now selects an XDG-portal or GTK3 platform theme when one is
  available, so Open/Export/Add font use your desktop's own chooser. Set `QT_QPA_PLATFORMTHEME` to choose another one, or
  `PIMPMYGRUB_NATIVE_DIALOGS=0` to keep Qt's built-in dialogs.
- **Fix:** store cards with a resolution dropdown overflowed their frame (Edit/Install spilled over the border) and had uneven
  heights. Cards are now taller, fixed-layout and aligned; single-resolution themes show their resolution as text.

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
