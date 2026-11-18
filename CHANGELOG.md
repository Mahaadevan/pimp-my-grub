# Changelog

## 0.6.4
- **Wayland and X11 use the GPU again.** 0.6.2/0.6.3 forced Qt Quick's software renderer to survive machines without a working
  graphics driver. That is not how the app should draw on a normal desktop: on Wayland it meant a software-drawn window scaled by
  the compositor, no VSync and blurry output on HiDPI screens. Qt's own graphics stack (EGL/OpenGL, Vulkan where Qt picks it) is
  used again on both display servers; `PIMPMYGRUB_SOFTWARE=1` (or `QT_QUICK_BACKEND=software`) still forces the CPU path, and the
  launcher's automatic safe mode (software drawing over X11) is unchanged.
- **A square interface.** Every rounded corner is gone, not just on buttons: dialogs, menus, fields, combo boxes, sliders,
  scrollbars, tabs, tab bar, stepper, zoom bar, preview frames, colour swatches, badges, the loading spinner and the status dots are
  all plain rectangles now (43 `radius` properties removed across the QML). The `RoundedMask` Canvas hack that painted fake rounded
  corners over store thumbnails went with them, so nothing needs a Canvas repaint to look right. The Style designer's own
  "Corner radius" field stays: that sets the corner radius of the GRUB theme you are building, not of the app.
- **Checkboxes instead of toggle switches.** The GRUB settings and the Style designer's gradient option use the checkbox component;
  `AppSwitch.qml` and the switch code in it are removed (the `/etc/default/grub` values it edits are unchanged).
- **Leftovers removed.** `antialiasing: true` was only ever there to smooth rounded corners; it is gone from the 80 places that
  still asked for it on plain rectangles. The header is just the name (*Pimp My GRUB*, no mark beside it), and the theme-name field
  shrinks instead of pushing the right-hand icons out of the window on a narrow screen. In the Store the card grid reserves room for
  the scroll bar, so the last column is no longer cut off at the window edge.
- **Clearer wording.** The Store buttons say *Edit Theme* and *Install Theme*, and the classic layout's *Save…* / *Reload* lost
  their emoji.
- **Load the default theme.** A new button in the editor toolbar starts over from GRUB's own plain look (black background, default
  font, a plain menu) instead of an empty canvas.
- **Reading GRUB settings needs root on most systems.** When `/etc/default/grub` and `grub.cfg` cannot be read as your user, the GRUB
  settings page offers *Read as administrator…*: the helper (the same polkit action, so one password prompt) copies the two files into
  a private temporary folder and they are parsed from there. It changes nothing on the system, and the whole UI never runs as root.
- The native-dialog probe no longer forks `dbus-send` when the portal plugin is not installed or there is no session bus, so it can
  never delay the window at start.

## 0.6.3
- **Look:** every box and button is now a smooth rounded rectangle. The software renderer (the default since 0.6.2) only smooths rounded
  corners and borders when asked, so every rectangle now asks for it. The controls that still had Qt's square grey default look were
  restyled to match: tabs (Classic layout, Style designer), right-click / preset / Open menus (rounded panel, clear disabled state,
  slim separators), scrollbars (slim rounded) and two frames in the install dialog.

## 0.6.2
- **Fix (crash on Wayland: the app aborted at start, reproduced with the user's core dump):** the bundle included Qt's Wayland platform
  plugin but not its *graphics integration* plugin (`wayland-graphics-integration-client`). On a Wayland session Qt then logged
  `Failed to load client buffer integration: "wayland-egl"` and `Failed to create RHI (backend 2)` and aborted. The folder is now
  bundled, and the build fails if Wayland support is bundled without it.
- **Changed: the software renderer is the default.** The interface is light and the theme preview is already drawn by the CPU, so Qt Quick
  now uses its software renderer unless you set `PIMPMYGRUB_GPU=1`. It needs no GPU driver, so VMs, remote sessions, unusual drivers and
  Wayland without working EGL can no longer take the program down at start.
- The launcher only treats real crash signals (segfault, abort, illegal instruction, bus error, ...) as crashes. Closing the program with
  Ctrl+C or a task manager during the first seconds no longer restarts it.
- Tested on a headless Wayland compositor that has an input seat (wlroots/cage) and on X11, without GPU.

## 0.6.1
- **Fix (crash at start: "has encountered a fatal error and was closed"):** the bundle (AppImage, .deb) always forced its own copy of
  the C++ runtime (`libstdc++`). On a distribution with a *newer* one, the graphics driver (Mesa) could then fail to load, and Qt
  aborts when it cannot create a graphics context. The bundle now keeps its copy in `lib/cxx` and the launcher uses it only when the
  system's is older than what the app needs (it records the level it needs).
- **New: automatic safe mode.** If the app crashes, or reports a graphics / window-system error, within its first seconds, the launcher
  starts it again with software drawing and X11 instead of Wayland. When that works it remembers the choice
  (`~/.cache/pimp-my-grub/safe-mode`; delete the file to try normal mode again, or set `PIMPMYGRUB_SAFE=1` / `0`).
  If even that fails, the error dialog now lists which files to send.
- **Fix:** an internal error can no longer take the whole program down. Every call into the engine and the canvas is guarded; a Rust
  panic is written to `~/.cache/pimp-my-grub/crash.log` (with a backtrace) and shown as a message instead of aborting Qt.
- `PIMPMYGRUB_PRINT_ENV=1 pimp-my-grub` prints the library path the launcher chose, for diagnosis.

## 0.6.0
- **Renamed** "Pimp my grub" to **Pimp my GRUB**. The default accent colour is now coral (#ff6b6b); icons were recoloured to match.
- **Timeout** is now in seconds and defaults to 5 (the stray "%" is gone). The preview's countdown labels (`T-%02d`, `%d`) and the
  `@TIMEOUT_NOTIFICATION_*@` texts follow it, and the progress bar drains accordingly.
- **GRUB settings** (new tab): everything that lives in `/etc/default/grub`, read from this computer and shown as switches,
  numbers and choices: wait time, menu style, boot the previously selected entry, default entry, detect other operating systems,
  advanced-options submenu, recovery entries, quiet/splash, kernel options, name, video mode. Each option has help text and, where it can
  stop GRUB or the system from working, a warning. Changes go through a review dialog with the exact diff, a backup and one-click undo.
  The helper got `cplan`/`capply` (validated key and value whitelist, one marked block, merged across changes, rollback chain,
  `uninstall` removes it).
- **Live preview** (full screen, F5): the finished theme with this computer's boot entries and timeout (read from `grub.cfg` and
  `/etc/default/grub`), a running countdown, ↑/↓/Home/End, Enter (simulated), e, c, F1, Esc. The countdown items disappear after a key press, like GRUB.
- **Right-click menu** on the canvas and the layers list: cut, copy, paste, duplicate, delete, arrange (front/back), align, group/ungroup,
  lock, hide, create a style, add. Ctrl+C/X/V/G shortcuts.
- **Presets** for menu (6), label (5), rectangle (5), progress bar (4), circular progress (3) and group (4); each button has a ▾ menu.
- **Style designer**: make the nine-piece box styles GRUB uses (selection bar, menu panel, progress track, scrollbar) from parameters
  (fill, gradient, opacity, rounded corners, border) or cut one from a picture. Until now only plain colours were possible.
- **More of theme.txt**: scrollbar styling, `highlight_overlay`, `id`, `message-*`, `terminal-*`, image alignment, icons from `icons/`.
  Boot menus now scroll and show a scrollbar when there are more entries than fit.
- **System fonts**: any font installed on the computer (or a .ttf/.otf file) can be added to a theme. It is converted to a GRUB
  font inside the app, without `grub-mkfont`.
- **Classic layout** (button next to GitHub): list configuration, general settings and appearance settings in the style of the
  original GRUB Customizer. The choice is remembered.
- **Tooltips** on every button, every inspector property and every setting.
- Disabled menu entries now look disabled. Selection handles follow the accent colour.

## 0.5.0
- **Fix (AppImage did not start: `undefined symbol: _ZNK11QQmlProperty...`):** the AppImage never used the Qt it carried. The
  binary was installed under `libexec/`, so its library path (`$ORIGIN/../lib`) and `qt.conf` pointed nowhere and `AppRun` was a
  bare symlink to the launcher, so the system's Qt (a different version) was loaded instead. The app now lives in `usr/bin`
  with a relative library path, and the launcher points the loader, the Qt plugins and the QML modules at the bundled copies
  and ignores the system's.
- **Changed:** the `.deb` is now self-contained as well: it installs the app with its own Qt 6 into `/usr/lib/pimp-my-grub`
  and no longer depends on the distribution's `libqt6*` / `qml6-module-*` packages (and no longer breaks when those are another
  version). Its `Depends` list is generated from the libraries it really loads, with `t64` alternatives for older/newer Debian.
  The `.rpm` and Arch packages still use the distribution's own Qt (they are built on that distribution).
- **Changed:** the bundle also carries the C++ runtime (`libstdc++`, `libgcc_s`), so a binary built with a recent compiler runs on
  older systems, plus Wayland support and Qt's QML file-dialog modules (the fallback used to crash when they were missing).
- **New:** `packaging/bundle.sh` (shared by both formats), `.github/workflows/release.yml` (builds the portable packages in an
  Ubuntu 20.04 container with official Qt binaries so they run on older systems too) and a check that fails the build if any
  library would be resolved from outside the bundle. The launcher gives a clear message for "glibc too old" and similar failures.
- **New:** the app ships its own fonts, so the interface looks right on systems with no fonts installed: Inter (UI), JetBrains
  Mono and a small symbol font for the icons. Tested with an empty fontconfig.
- **New:** 24 ready-made GRUB fonts (Inter, JetBrains Mono, DejaVu Sans; regular and bold; 16, 24, 32 and 48 px) appear in every
  font dropdown. Choosing one adds its `.pf2` to the theme, so no `grub-mkfont` / GRUB install is needed to give a theme a real font.
- **Fix:** font and other dropdowns in the inspector showed the wrong entry after the selection changed; the default font is
  listed first, so "no font set" shows what GRUB will really use. Dropdown lists are wider so long names fit.
- **Fix:** icons that used glyphs missing from many fonts (a fullwidth plus, a lock emoji, two rare symbols) were replaced.

## 0.4.0
- **New:** change the app's colour. The palette button in the header opens *Appearance*: eight presets, a hex field and the
  system colour chooser. The choice is saved to `~/.config/pimp-my-grub/settings.json` and applied to buttons, highlights, the
  logo and the zoom bar. It only affects the app, not the GRUB theme being built.
- **New:** a GitHub button in the header opens https://github.com/Mahaadevan/pimp-my-grub.
- **Changed:** Open, Export, Add font, Upload image and the colour pickers now start the system's own chooser (zenity on
  GTK/GNOME/other desktops, kdialog on KDE) and only fall back to Qt's built-in dialog when neither is installed or
  `PIMPMYGRUB_NATIVE_DIALOGS=0` is set. The chooser remembers the last folder. Packages now recommend zenity or kdialog.
- **Fix:** store thumbnails no longer poke square corners out of the rounded card or hide its top border (the hover outline
  was cut off over the image); the same fix is applied to the detail-view preview, and the "i" badge no longer has colour fringes.

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
