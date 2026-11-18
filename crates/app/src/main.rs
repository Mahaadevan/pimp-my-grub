//! Pimp my GRUB: native Qt 6 GRUB theme builder. All logic lives in pimp-my-grub-core; this crate is the Qt Quick shell.
mod backend;
mod scene_item;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QString, QUrl};

/// Qt only opens the system's own file chooser when a platform theme that provides one is active; otherwise it falls back
/// to its built-in QML dialog. Pick the best available one unless the user chose (QT_QPA_PLATFORMTHEME) or opted out
/// (PIMPMYGRUB_NATIVE_DIALOGS=0). KDE is left alone: plasma-integration already provides native dialogs.
fn prefer_native_dialogs() {
    use std::process::Command;
    if std::env::var_os("QT_QPA_PLATFORMTHEME").is_some() || std::env::var("PIMPMYGRUB_NATIVE_DIALOGS").map(|v| v == "0").unwrap_or(false) { return; }
    let desktop = std::env::var("XDG_CURRENT_DESKTOP").unwrap_or_default().to_lowercase();
    if desktop.contains("kde") { return; }
    let mut dirs: Vec<std::path::PathBuf> = std::env::var("QT_PLUGIN_PATH").unwrap_or_default().split(':').filter(|d| !d.is_empty()).map(Into::into).collect();
    for d in ["/usr/lib/qt6/plugins", "/usr/lib64/qt6/plugins", "/usr/lib/x86_64-linux-gnu/qt6/plugins", "/usr/lib/aarch64-linux-gnu/qt6/plugins"] { dirs.push(d.into()); }
    let has = |lib: &str| dirs.iter().any(|d| d.join("platformthemes").join(lib).is_file());
    let gtk_desktop = ["gnome", "xfce", "cinnamon", "mate", "budgie", "unity", "pantheon", "lxde", "lxqt", "ubuntu", "x-cinnamon"].iter().any(|d| desktop.contains(d));
    // Probing the portal starts a process before the window exists, so only do it when the plugin that uses it is installed and
    // there is a session bus to ask.
    let bus = std::env::var_os("DBUS_SESSION_BUS_ADDRESS").is_some()
        || std::env::var_os("XDG_RUNTIME_DIR").map(|d| std::path::Path::new(&d).join("bus").exists()).unwrap_or(false);
    let portal_up = bus && has("libqxdgdesktopportal.so") && Command::new("dbus-send")
        .args(["--session", "--dest=org.freedesktop.DBus", "--print-reply", "/org/freedesktop/DBus", "org.freedesktop.DBus.NameHasOwner", "string:org.freedesktop.portal.Desktop"])
        .output().map(|o| String::from_utf8_lossy(&o.stdout).contains("boolean true")).unwrap_or(false);
    if portal_up { std::env::set_var("QT_QPA_PLATFORMTHEME", "xdgdesktopportal"); }
    else if gtk_desktop && has("libqgtk3.so") { std::env::set_var("QT_QPA_PLATFORMTHEME", "gtk3"); }
}

/// Where diagnostics go (~/.cache/pimp-my-grub), so a user can send them when something goes wrong.
fn cache_dir() -> std::path::PathBuf {
    let base = std::env::var_os("XDG_CACHE_HOME").map(std::path::PathBuf::from).filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::Path::new(&h).join(".cache"))).unwrap_or_else(|| "/tmp".into());
    base.join("pimp-my-grub")
}

fn main() {
    // Log every Rust panic (with where it happened and a backtrace) to crash.log; the app itself keeps running.
    std::panic::set_hook(Box::new(|info| {
        use std::io::Write;
        let dir = cache_dir();
        let _ = std::fs::create_dir_all(&dir);
        if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(dir.join("crash.log")) {
            let _ = writeln!(f, "--- pimp-my-grub {} panic ---\n{info}\n{}\n", env!("CARGO_PKG_VERSION"), std::backtrace::Backtrace::force_capture());
        }
        eprintln!("pimp-my-grub: internal error: {info}");
    }));
    // Draw through the platform's own graphics stack, which is what Qt Quick does by default: EGL/OpenGL on a Wayland session,
    // GLX/EGL on X11, Vulkan where Qt prefers it. That is what makes the window tear-free, correctly scaled on HiDPI screens and
    // smooth on both display servers; the editor preview is still rendered by the CPU and reaches the screen as one texture.
    // PIMPMYGRUB_SOFTWARE=1 (or QT_QUICK_BACKEND=software) forces the old CPU-only path for machines whose driver cannot create a
    // context; the launcher also switches to it automatically when the first start fails (see helper/pimp-my-grub-launcher.sh).
    if std::env::var_os("QT_QUICK_BACKEND").is_none() && std::env::var("PIMPMYGRUB_SOFTWARE").map(|v| v == "1").unwrap_or(false) {
        std::env::set_var("QT_QUICK_BACKEND", "software");
    }
    prefer_native_dialogs();
    // The UI draws its own dark GrubStudio-style look, which needs a style that allows full customisation.
    // Basic ships with every Qt 6 install; set QT_QUICK_CONTROLS_STYLE yourself to override.
    if std::env::var_os("QT_QUICK_CONTROLS_STYLE").is_none() {
        std::env::set_var("QT_QUICK_CONTROLS_STYLE", "Basic");
        std::env::set_var("QT_QUICK_CONTROLS_FALLBACK_STYLE", "Basic");
    }
    // `pimp-my-grub <theme-folder>` opens a theme straight away (handy from a file manager).
    if let Some(dir) = std::env::args().nth(1).filter(|a| std::path::Path::new(a).is_dir()) {
        let p = std::path::Path::new(&dir);
        match pimp_my_grub_core::installer::read_dir_files(p).and_then(|f| backend::ed().load_files(&f, &p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default())) {
            Ok(()) => {}
            Err(e) => eprintln!("could not open {dir}: {e}"),
        }
    }
    let mut app = QGuiApplication::new();
    // Lets Wayland/X11 shells match the window to dev.pimpmygrub.PimpMyGrub.desktop (icon, name) even though the
    // real binary is called pimp-my-grub-bin.
    QGuiApplication::set_desktop_file_name(&QString::from("dev.pimpmygrub.PimpMyGrub"));
    let mut engine = QQmlApplicationEngine::new();
    if let Some(mut engine) = engine.as_mut() {
        // Without this a QML load failure (typically a missing qml6-module-* package) leaves the process with no
        // window and exit code 0, so the app "does nothing". Fail loudly and non-zero instead; the launcher turns
        // that into a dialog.
        engine.as_mut().on_object_creation_failed(|_, url| {
            eprintln!("pimp-my-grub: could not load the user interface ({}).", url.to_string());
            eprintln!("pimp-my-grub: a Qt 6 QML module is probably missing. On Debian/Ubuntu install: qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-dialogs qml6-module-qtquick-templates qml6-module-qtquick-window qml6-module-qtqml-workerscript");
            std::process::exit(1);
        }).release();
        engine.load(&QUrl::from("qrc:/qt/qml/dev/pimpmygrub/qml/Main.qml"));
    }
    if let Some(app) = app.as_mut() {
        std::process::exit(app.exec());
    }
}
