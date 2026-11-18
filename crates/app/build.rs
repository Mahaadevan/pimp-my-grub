use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(
        QmlModule::new("dev.pimpmygrub")
            .qml_files([
                "qml/Main.qml", "qml/EditorPage.qml", "qml/LayersPanel.qml", "qml/InspectorPanel.qml",
                "qml/StorePage.qml", "qml/InstallDialog.qml",
                "qml/Tokens.qml", "qml/AppButton.qml", "qml/AppIconButton.qml", "qml/AppField.qml", "qml/AppSlider.qml", "qml/NavTab.qml",
                "qml/AppComboBox.qml", "qml/AppCheckBox.qml", "qml/AppDialog.qml", "qml/ThemeDetail.qml", "qml/ZoomBar.qml", "qml/AppStepper.qml",
                "qml/NativePick.qml", "qml/HeaderIcon.qml", "qml/AppearanceDialog.qml", "qml/ConfigPanel.qml", "qml/AppMenuItem.qml", "qml/AppMenu.qml", "qml/AppMenuSeparator.qml", "qml/AppTabButton.qml", "qml/AppTabBar.qml", "qml/AppScrollBar.qml", "qml/PresetMenu.qml", "qml/ItemMenu.qml", "qml/StyleDesigner.qml", "qml/FontPicker.qml", "qml/LivePreview.qml", "qml/ClassicPage.qml", "qml/WarnBadge.qml",
            ])
            .depend("QtQuick"),
    )
    .qt_module("Quick")
    .qt_module("QuickControls2")
    .files(["src/backend.rs", "src/scene_item.rs"])
    .qrc("resources.qrc")
    .build();
}
