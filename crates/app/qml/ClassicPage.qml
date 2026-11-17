import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import dev.pimpmygrub

// The "classic" layout: the same features arranged like the original GRUB Customizer, as three tabs:
// list configuration (boot entries), general settings (timeout, default entry ...) and appearance settings (the theme).
Item {
    id: root
    readonly property var t: Tokens {}
    property var backend
    signal installTheme()
    signal livePreview()
    signal message(string m)
    function reload() { settings.reload(); loadEntries() }
    property var entries: []
    property string cfgFile: ""
    function loadEntries() { try { var h = JSON.parse(backend.call("hostInfo", "", "")); entries = h.entries; cfgFile = h.cfg } catch (e) { entries = [] } }
    Component.onCompleted: { backend.call("select", "", ""); loadEntries() }
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
                AppButton { text: "💾  " + qsTr("Save…"); highlighted: true; enabled: settings.pending > 0
                    tip: qsTr("Review and save the changes made on the General settings tab. You see the exact difference first.")
                    onClicked: settings.review(settings.edits) }
                AppButton { text: "⟳  " + qsTr("Reload"); tip: qsTr("Read the GRUB settings from this computer again"); onClicked: root.reload() }
                Rectangle { width: 1; height: 22; color: t.border }
                AppButton { text: qsTr("Install theme…"); tip: qsTr("Put the theme from the Appearance tab on this computer's GRUB (with a backup, and a review first)."); onClicked: root.installTheme() }
                AppButton { text: "▶  " + qsTr("Live preview"); tip: qsTr("Full-screen simulation of the menu with this computer's entries"); onClicked: root.livePreview() }
                Item { Layout.fillWidth: true }
                Label { text: settings.pending > 0 ? qsTr("%n unsaved change(s)", "", settings.pending) : ""; color: t.accent; font.pixelSize: 12 }
            }
        }
        TabBar {
            id: tabs; Layout.fillWidth: true; background: Rectangle { color: t.bg }
            TabButton { text: qsTr("List configuration"); width: implicitWidth + 24 }
            TabButton { text: qsTr("General settings"); width: implicitWidth + 24 }
            TabButton { text: qsTr("Appearance settings"); width: implicitWidth + 24 }
        }
        StackLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: tabs.currentIndex
            // ---- list configuration
            Item {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 10
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.muted; font.pixelSize: 12
                        text: root.entries.length > 0
                              ? qsTr("The entries below are what GRUB lists on this computer (from %1). Their order and names come from your distribution's scripts in /etc/grub.d, so they are shown here but not edited. You can choose which one boots by default.").arg(root.cfgFile)
                              : qsTr("The boot entries could not be read (grub.cfg is missing or not readable by your user). The settings still work.") }
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true; radius: 12; color: t.surface; border.width: 1; border.color: t.border; clip: true
                        ListView {
                            id: lv; anchors.fill: parent; anchors.margins: 4; model: root.entries; clip: true; boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { }
                            delegate: ItemDelegate {
                                required property var modelData
                                width: lv.width - 8; height: 42; hoverEnabled: true
                                readonly property bool isDefault: settings.val("remember_last") !== "true" && settings.val("default_entry") === modelData.id
                                background: Rectangle { radius: 8; color: parent.hovered ? t.surface2 : "transparent" }
                                contentItem: RowLayout {
                                    spacing: 10
                                    Item { Layout.preferredWidth: 14 + modelData.depth * 22 }
                                    Label { text: modelData.submenu ? "▸" : "◆"; color: isDefault ? t.accent : t.muted2 }
                                    Label { text: modelData.title; Layout.fillWidth: true; elide: Text.ElideRight; color: t.text }
                                    Label { visible: isDefault; text: qsTr("default"); color: t.accent; font.pixelSize: 11 }
                                    Label { text: modelData.id; color: t.muted2; font.family: t.mono; font.pixelSize: 11 }
                                    AppButton { visible: modelData.depth === 0 && !isDefault; text: qsTr("Make default")
                                        tip: qsTr("Boot this entry when you do nothing. This turns off \"Boot the previously selected entry\".")
                                        onClicked: { settings.setVal("remember_last", "false"); settings.setVal("default_entry", modelData.id) } }
                                }
                            }
                        }
                    }
                }
            }
            // ---- general settings (the same panel as the GRUB settings tab)
            ConfigPanel { id: settings; backend: root.backend; compact: true; onReview: (e) => root.reviewSettings(e) }
            // ---- appearance settings: the theme-wide options next to a finished-look preview
            RowLayout {
                spacing: 0
                Rectangle { Layout.fillWidth: true; Layout.fillHeight: true; color: "black"
                    SceneItem { id: thumb; anchors.fill: parent; anchors.margins: 12; live: true
                        Connections { target: root.backend; function onRevChanged() { thumb.input(6, 0, 0, 0, 0, 0) } }
                        Component.onCompleted: input(6, 0, 0, 0, 0, 0) } }
                Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: t.border }
                Pane { Layout.preferredWidth: 340; Layout.fillHeight: true; padding: 0; background: Rectangle { color: t.surface }
                    InspectorPanel { anchors.fill: parent; backend: root.backend; designer: classicDesigner } }
            }
        }
    }
}
