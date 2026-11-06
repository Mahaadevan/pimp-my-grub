//! Pimp my grub: native Qt 6 GRUB theme builder. All logic lives in pimp-my-grub-core; this crate is the Qt Quick shell.
mod backend;
mod scene_item;

use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QUrl};

fn main() {
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
    let mut engine = QQmlApplicationEngine::new();
    if let Some(engine) = engine.as_mut() {
        engine.load(&QUrl::from("qrc:/qt/qml/dev/pimpmygrub/qml/Main.qml"));
    }
    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
