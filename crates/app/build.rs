use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    // SAFETY: the closure only adds a compiler flag.
    unsafe { CxxQtBuilder::new_qml_module(
        QmlModule::new("dev.pimpmygrub")
            .qml_files([
                "qml/Main.qml", "qml/EditorPage.qml", "qml/LayersPanel.qml", "qml/InspectorPanel.qml",
                "qml/StorePage.qml", "qml/InstallDialog.qml",
            ])
            .depend("QtQuick"),
    )
    .qt_module("Quick")
    .qt_module("QuickControls2")
    .files(["src/backend.rs", "src/scene_item.rs"])
    // cxx-qt always generates `Item(QObject* parent)`; QQuickPaintedItem wants QQuickItem*. QML always passes null here.
    .cc_builder(|cc| { cc.flag_if_supported("-fpermissive"); })
    .build(); }
}
