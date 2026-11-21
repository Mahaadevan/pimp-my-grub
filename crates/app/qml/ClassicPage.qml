import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import dev.stylemygrub

// The "classic" layout: the same features arranged like the original GRUB Customizer, as three tabs:
// list configuration (boot entries), general settings (timeout, default entry ...) and appearance settings (the theme).
Item {
    id: root
    readonly property var t: Tokens { }
    property var backend
    signal installTheme()
    signal livePreview()
    signal message(string m)
    function reload() { settings.reload(); list.reload() }
    Component.onCompleted: backend.call("select", "", "")
    property alias settingsPanel: settings
    signal reviewSettings(var edits)

    StyleDesigner { id: classicDesigner; backend: root.backend; onCreated: root.backend.call("touch", "", "") }

    ColumnLayout {
        anchors.fill: parent; spacing: 0
        // toolbar, as in the original program: Save / Reload on the left
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 52; color: t.surface
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: t.border }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 8
                AppButton { text: qsTr("Save…"); highlighted: true; enabled: settings.pending > 0
                    tip: qsTr("Review and save the changes made on the General settings tab. You see the exact difference first.")
                    onClicked: settings.review(settings.edits) }
                AppButton { text: qsTr("Reload"); tip: qsTr("Read the GRUB settings from this computer again"); onClicked: root.reload() }
                Rectangle { width: 1; height: 22; color: t.border }
                AppButton { text: qsTr("Install theme…"); tip: qsTr("Put the theme from the Appearance tab on this computer's GRUB (with a backup, and a review first)."); onClicked: root.installTheme() }
                AppButton { text: "▶  " + qsTr("Live preview"); tip: qsTr("Full-screen simulation of the menu with this computer's entries"); onClicked: root.livePreview() }
                Item { Layout.fillWidth: true }
                Label { text: settings.pending > 0 ? qsTr("%n unsaved change(s)", "", settings.pending) : ""; color: t.accent; font.pixelSize: 12 }
            }
        }
        AppTabBar { id: tabs; Layout.leftMargin: 14; Layout.topMargin: 10; Layout.bottomMargin: 8
            AppTabButton { text: qsTr("List Config"); width: implicitWidth + 24 }
            AppTabButton { text: qsTr("General settings"); width: implicitWidth + 24 }
            AppTabButton { text: qsTr("Appearance settings"); width: implicitWidth + 24 }
        }
        StackLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: tabs.currentIndex
            // ---- list configuration (the same panel as the List Config tab)
            HostEntriesPanel { id: list; backend: root.backend; grubSettings: settings; onMessage: (m) => root.message(m) }
            // ---- general settings (the same panel as the General tab)
            ConfigPanel { id: settings; backend: root.backend; compact: true; onReview: (e) => root.reviewSettings(e); onStatus: (m) => root.message(m) }
            // ---- appearance settings: the theme-wide options next to a finished-look preview (drag the divider
            // between them, like on the modern Appearance tab)
            SplitView {
                orientation: Qt.Horizontal
                handle: Rectangle {
                    id: aHandle
                    implicitWidth: 6; implicitHeight: 6; color: "transparent"
                    containmentMask: Item { x: (aHandle.width - width) / 2; width: 12; height: aHandle.height }
                    Rectangle { anchors.centerIn: parent; width: 1; height: parent.height
                        color: SplitHandle.pressed ? t.accent : (SplitHandle.hovered ? t.muted2 : t.border) }
                }
                Item {
                    SplitView.fillWidth: true; SplitView.minimumWidth: 380
                    Rectangle { anchors.fill: parent; color: "black"; z: -1 }
                    SceneItem { id: thumb; anchors.fill: parent; anchors.margins: 12; live: true
                        Connections { target: root.backend; function onRevChanged() { thumb.input(6, 0, 0, 0, 0, 0) } }
                        Component.onCompleted: input(6, 0, 0, 0, 0, 0) }
                }
                Pane { SplitView.preferredWidth: 340; SplitView.minimumWidth: 260; SplitView.maximumWidth: 560
                    padding: 0; background: Rectangle { color: t.surface }
                    InspectorPanel { anchors.fill: parent; backend: root.backend; designer: classicDesigner } }
            }
        }
    }
}
