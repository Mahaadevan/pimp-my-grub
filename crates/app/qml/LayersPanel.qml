import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    readonly property var t: Tokens {}
    id: root
    property var backend
    property var rows: []
    property int rev: backend ? backend.rev : 0
    onRevChanged: reload()
    Component.onCompleted: reload()
    function reload() { rows = JSON.parse(backend.call("layers", "", "")) }
    readonly property var icons: ({ boot_menu: "☰", label: "T", image: "▣", progress_bar: "▬", circular_progress: "◔", canvas: "▢", vbox: "⫶", hbox: "⋯" })
    spacing: 0

    Label { text: qsTr("LAYERS"); font.bold: true; font.pixelSize: 11; font.letterSpacing: 0.8; color: t.muted
        Layout.fillWidth: true; leftPadding: 14; topPadding: 14; bottomPadding: 10 }
    Rectangle { Layout.fillWidth: true; height: 1; color: t.border }
    ListView {
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
        model: root.rows
        ScrollBar.vertical: ScrollBar {}
        delegate: ItemDelegate {
            id: rowDelegate
            width: ListView.view.width; height: 32
            highlighted: modelData.selected
            hoverEnabled: true
            leftPadding: 10 + modelData.depth * 14; rightPadding: 6
            background: Rectangle {
                color: modelData.selected ? t.accentSoft : rowDelegate.hovered ? t.surface2 : "transparent"
                Rectangle { width: 2; height: parent.height; color: t.accent; visible: modelData.selected }
            }
            onClicked: root.backend.call("select", modelData.uid.toString(), "")
            contentItem: RowLayout {
                spacing: 6
                Label { text: root.icons[modelData.type] || "?"; Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter; color: modelData.selected ? t.accent : t.muted }
                Label { text: modelData.label; Layout.fillWidth: true; elide: Text.ElideRight; opacity: modelData.hidden ? 0.4 : 1 }
                AppIconButton { text: modelData.locked ? "🔒" : "·"; padding: 2; implicitWidth: 22; implicitHeight: 22; flat: true; onClicked: root.backend.call("toggle", modelData.uid.toString(), "locked") }
                AppIconButton { text: modelData.hidden ? "○" : "●"; padding: 2; implicitWidth: 22; implicitHeight: 22; flat: true; onClicked: root.backend.call("toggle", modelData.uid.toString(), "hidden") }
            }
        }
        Label { anchors.centerIn: parent; width: parent.width - 30; visible: root.rows.length === 0; wrapMode: Text.Wrap; color: t.muted2
            text: qsTr("Empty theme. Add components with the toolbar above the canvas."); horizontalAlignment: Text.AlignHCenter }
    }
    Flow {
        Layout.fillWidth: true; Layout.margins: 10; spacing: 6
        visible: root.rows.some(function(r) { return r.selected })
        AppButton { text: "↑"; onClicked: root.backend.call("reorder", "1", ""); ToolTip.text: qsTr("Bring forward ( ] )"); ToolTip.visible: hovered }
        AppButton { text: "↓"; onClicked: root.backend.call("reorder", "-1", ""); ToolTip.text: qsTr("Send backward ( [ )"); ToolTip.visible: hovered }
        AppButton { text: qsTr("Duplicate"); onClicked: root.backend.call("duplicate", "", "") }
        AppButton { text: qsTr("Delete"); onClicked: root.backend.call("remove", "", "") }
    }
}
