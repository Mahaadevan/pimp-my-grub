use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(
        QmlModule::new("dev.pimpmygrub")
            .qml_files([
                "qml/Main.qml", "qml/EditorPage.qml", "qml/LayersPanel.qml", "qml/InspectorPanel.qml",
                "qml/StorePage.qml", "qml/InstallDialog.qml",
                "qml/Tokens.qml", "qml/AppButton.qml", "qml/AppIconButton.qml", "qml/AppField.qml", "qml/AppSlider.qml", "qml/NavTab.qml",
                "qml/AppComboBox.qml", "qml/AppCheckBox.qml", "qml/AppDialog.qml", "qml/ThemeDetail.qml", "qml/ZoomBar.qml",
            ])
            .depend("QtQuick"),
    )
    .qt_module("Quick")
    .qt_module("QuickControls2")
    .files(["src/backend.rs", "src/scene_item.rs"])
    .build();
}
