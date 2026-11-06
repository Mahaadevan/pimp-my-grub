import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import dev.pimpmygrub

RowLayout {
    id: page
    property var backend
    signal message(string m)
    spacing: 0

    Pane {
        Layout.preferredWidth: 230; Layout.fillHeight: true; padding: 0
        LayersPanel { anchors.fill: parent; backend: page.backend }
    }
    ToolSeparator { Layout.fillHeight: true; padding: 0 }

    ColumnLayout {
        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: false
            Layout.preferredHeight: bar.implicitHeight + 8
            color: palette.window
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: palette.mid }
            Flow {
                id: bar
                x: 4; y: 4; width: parent.width - 8; spacing: 4
                Repeater {
                    model: [["boot_menu", qsTr("Menu")], ["label", qsTr("Label")], ["image", qsTr("Image")], ["rect", qsTr("Rectangle")],
                            ["progress_bar", qsTr("Progress")], ["circular_progress", qsTr("Circular")], ["canvas", qsTr("Group")]]
                    delegate: Button {
                        text: "＋ " + modelData[1]; flat: true
                        onClicked: modelData[0] === "rect" ? page.backend.call("addRect", "#4aa3ff", "") : page.backend.call("add", modelData[0], "")
                    }
                }
                Label { text: qsTr("Entry"); height: 32; verticalAlignment: Text.AlignVCenter }
                Slider { width: 80; height: 32; from: 0; to: 4; stepSize: 1; value: 0; onMoved: page.backend.call("menuSel", Math.round(value).toString(), "") }
                Label { text: qsTr("Timeout"); height: 32; verticalAlignment: Text.AlignVCenter }
                Slider { width: 80; height: 32; from: 0; to: 1; value: 0.6; onMoved: page.backend.call("progress", value.toString(), "") }
                Button { text: qsTr("Fit"); flat: true; onClicked: { scene.userView = false; scene.input(4, 0, 0, 0, 0, 0) } }
                Button { text: qsTr("100%"); flat: true; onClicked: scene.input(5, 0, 0, 0, 0, 0) }
            }
        }

        SceneItem {
            id: scene
            Layout.fillWidth: true; Layout.fillHeight: true
            focus: true
            property bool userView: false   // once the user zooms or pans, stop auto-fitting
            function autoFit() { if (!userView && width > 100 && height > 100) Qt.callLater(function() { scene.input(4, 0, 0, 0, 0, 0) }) }
            onWidthChanged: autoFit()
            onHeightChanged: autoFit()
            onEdited: page.backend.call("select", "", "")  // no-op call keeps panels in sync through rev
            Connections { target: page.backend; function onRevChanged() { scene.update() } }

            function flags(m) { return (m.modifiers & Qt.ControlModifier ? 1 : 0) | (m.modifiers & Qt.ShiftModifier ? 2 : 0) | (m.modifiers & Qt.AltModifier ? 4 : 0) }
            function keyName(e) {
                switch (e.key) {
                case Qt.Key_Delete: return "Delete"; case Qt.Key_Backspace: return "Backspace"; case Qt.Key_Escape: return "Escape"
                case Qt.Key_Left: return "Left"; case Qt.Key_Right: return "Right"; case Qt.Key_Up: return "Up"; case Qt.Key_Down: return "Down"
                case Qt.Key_BracketLeft: return "["; case Qt.Key_BracketRight: return "]"
                case Qt.Key_D: return "d"; case Qt.Key_Z: return "z"; case Qt.Key_Y: return "y"
                }
                return ""
            }
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Space) { scene.userView = true; if (!e.isAutoRepeat) scene.input(7, 0, 0, 0, 0, 0); e.accepted = true; return }
                var n = keyName(e)
                if (n !== "") { scene.key(n, (e.modifiers & Qt.ControlModifier ? 1 : 0) | (e.modifiers & Qt.ShiftModifier ? 2 : 0)); e.accepted = true }
            }
            Keys.onReleased: (e) => { if (e.key === Qt.Key_Space && !e.isAutoRepeat) scene.input(8, 0, 0, 0, 0, 0) }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                hoverEnabled: false
                onPressed: (m) => { scene.forceActiveFocus(); scene.input(0, m.x, m.y, 0, 0, scene.flags(m) | (m.button === Qt.MiddleButton ? 8 : 0)) }
                onPositionChanged: (m) => scene.input(1, m.x, m.y, 0, 0, scene.flags(m))
                onReleased: (m) => scene.input(2, m.x, m.y, 0, 0, 0)
                onWheel: (w) => { scene.userView = true; scene.input(3, w.x, w.y, w.angleDelta.x, w.angleDelta.y, (w.modifiers & Qt.ControlModifier) ? 1 : 0) }
            }
        }
    }

    ToolSeparator { Layout.fillHeight: true; padding: 0 }
    Pane {
        Layout.preferredWidth: 300; Layout.fillHeight: true; padding: 0
        InspectorPanel { anchors.fill: parent; backend: page.backend }
    }
}
