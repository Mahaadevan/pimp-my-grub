import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import dev.pimpmygrub

RowLayout {
    readonly property var t: Tokens {}
    id: page
    property var backend
    signal message(string m)
    spacing: 0

    Pane {
        Layout.preferredWidth: 240; Layout.fillHeight: true; padding: 0
        background: Rectangle { color: t.surface }
        LayersPanel { anchors.fill: parent; backend: page.backend }
    }
    Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: t.border }

    ColumnLayout {
        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: false
            Layout.preferredHeight: bar.implicitHeight + 12
            color: t.surface
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: t.border }
            Flow {
                id: bar
                x: 8; y: 6; width: parent.width - 16; spacing: 6
                Repeater {
                    model: [["boot_menu", qsTr("Menu")], ["label", qsTr("Label")], ["image", qsTr("Image")], ["rect", qsTr("Rectangle")],
                            ["progress_bar", qsTr("Progress")], ["circular_progress", qsTr("Circular")], ["canvas", qsTr("Group")]]
                    delegate: AppButton {
                        text: "＋ " + modelData[1]
                        onClicked: modelData[0] === "rect" ? page.backend.call("addRect", "#ff9248", "") : page.backend.call("add", modelData[0], "")
                    }
                }
                Row {
                    spacing: 4; height: 32
                    Label { text: qsTr("Entry"); height: 32; leftPadding: 8; verticalAlignment: Text.AlignVCenter; color: t.muted }
                    AppSlider { width: 80; height: 32; from: 0; to: 4; stepSize: 1; value: 0; onMoved: page.backend.call("menuSel", Math.round(value).toString(), "") }
                }
                Row {
                    spacing: 4; height: 32
                    Label { text: qsTr("Timeout"); height: 32; leftPadding: 4; verticalAlignment: Text.AlignVCenter; color: t.muted }
                    AppSlider { width: 80; height: 32; from: 0; to: 1; value: 0.6; onMoved: page.backend.call("progress", value.toString(), "") }
                }
                AppButton { text: qsTr("Fit"); flat: true; onClicked: { scene.userView = false; scene.input(4, 0, 0, 0, 0, 0) } }
                AppButton { text: qsTr("100%"); flat: true; onClicked: scene.input(5, 0, 0, 0, 0, 0) }
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
            onEdited: page.backend.call("touch", "", "")  // changes nothing; bumps rev so the panels refresh
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

    Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: t.border }
    Pane {
        Layout.preferredWidth: 310; Layout.fillHeight: true; padding: 0
        background: Rectangle { color: t.surface }
        InspectorPanel { anchors.fill: parent; backend: page.backend }
    }
}
