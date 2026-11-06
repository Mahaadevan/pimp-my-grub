import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    property var backend
    property var rows: []
    property int rev: backend ? backend.rev : 0
    onRevChanged: reload()
    Component.onCompleted: reload()
    function reload() { rows = JSON.parse(backend.call("layers", "", "")) }
    readonly property var icons: ({ boot_menu: "☰", label: "T", image: "▣", progress_bar: "▬", circular_progress: "◔", canvas: "▢", vbox: "⫶", hbox: "⋯" })
    spacing: 0

    Label { text: qsTr("Layers"); font.bold: true; padding: 10 }
    ListView {
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
        model: root.rows
        ScrollBar.vertical: ScrollBar {}
        delegate: ItemDelegate {
            width: ListView.view.width; height: 30
            highlighted: modelData.selected
            leftPadding: 8 + modelData.depth * 14
            onClicked: root.backend.call("select", modelData.uid.toString(), "")
            contentItem: RowLayout {
                spacing: 6
                Label { text: root.icons[modelData.type] || "?"; Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter; opacity: 0.7 }
                Label { text: modelData.label; Layout.fillWidth: true; elide: Text.ElideRight; opacity: modelData.hidden ? 0.4 : 1 }
                ToolButton { text: modelData.locked ? "🔒" : "·"; padding: 2; implicitWidth: 22; implicitHeight: 22; flat: true; onClicked: root.backend.call("toggle", modelData.uid.toString(), "locked") }
                ToolButton { text: modelData.hidden ? "○" : "●"; padding: 2; implicitWidth: 22; implicitHeight: 22; flat: true; onClicked: root.backend.call("toggle", modelData.uid.toString(), "hidden") }
            }
        }
        Label { anchors.centerIn: parent; width: parent.width - 30; visible: root.rows.length === 0; wrapMode: Text.Wrap; opacity: 0.6
            text: qsTr("Empty theme. Add components with the toolbar above the canvas."); horizontalAlignment: Text.AlignHCenter }
    }
    Flow {
        Layout.fillWidth: true; Layout.margins: 8; spacing: 4
        visible: root.rows.some(function(r) { return r.selected })
        Button { text: "↑"; onClicked: root.backend.call("reorder", "1", ""); ToolTip.text: qsTr("Bring forward ( ] )"); ToolTip.visible: hovered }
        Button { text: "↓"; onClicked: root.backend.call("reorder", "-1", ""); ToolTip.text: qsTr("Send backward ( [ )"); ToolTip.visible: hovered }
        Button { text: qsTr("Duplicate"); onClicked: root.backend.call("duplicate", "", "") }
        Button { text: qsTr("Delete"); onClicked: root.backend.call("remove", "", "") }
    }
}
