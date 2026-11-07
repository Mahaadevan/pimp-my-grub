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
                    spacing: 6; height: 32
                    Label { text: qsTr("Timeout"); height: 32; leftPadding: 4; verticalAlignment: Text.AlignVCenter; color: t.muted }
                    // Type the countdown progress to preview (0-100 %), or use the arrow buttons / Up / Down / mouse wheel (step 5).
                    AppStepper {
                        id: timeoutBox; width: 76; height: 32; horizontalAlignment: TextInput.AlignHCenter
                        text: "60"; inputMethodHints: Qt.ImhDigitsOnly
                        step: 5; bigStep: 10; minValue: 0; maxValue: 100
                        validator: IntValidator { bottom: 0; top: 100 }
                        function apply(v) { v = Math.max(0, Math.min(100, v)); text = v.toString(); page.backend.call("progress", (v / 100).toString(), "") }
                        onStepped: (v) => apply(parseInt(v))
                        onTextEdited: if (text !== "") page.backend.call("progress", (Math.min(100, parseInt(text)) / 100).toString(), "")
                        onEditingFinished: apply(text === "" ? 0 : parseInt(text))
                        WheelHandler { onWheel: function(ev) { timeoutBox.apply((parseInt(timeoutBox.text) || 0) + (ev.angleDelta.y > 0 ? 5 : -5)) } }
                    }
                    Label { text: "%"; height: 32; verticalAlignment: Text.AlignVCenter; color: t.muted }
                }
            }
        }

        SceneItem {
            id: scene
            Layout.fillWidth: true; Layout.fillHeight: true
            focus: true
            property bool userView: false   // once the user zooms or pans, stop auto-fitting
            property int zoomPct: 50
            onViewChanged: zoomPct = zoomPercent()
            function viewCmd(kind) { if (kind !== 4) userView = true; else userView = false; input(kind, 0, 0, 0, 0, 0) }
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
                if (!(e.modifiers & Qt.ControlModifier) && (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal)) { viewCmd(9); e.accepted = true; return }
                if (!(e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_Minus) { viewCmd(10); e.accepted = true; return }
                if (!(e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_0) { viewCmd(4); e.accepted = true; return }
                if (!(e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_C) { viewCmd(11); e.accepted = true; return }
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
            ZoomBar {
                anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 14
                zoom: scene.zoomPct
                onZoomIn: scene.viewCmd(9)
                onZoomOut: scene.viewCmd(10)
                onActualSize: scene.viewCmd(5)
                onFit: scene.viewCmd(4)
                onCenter: scene.viewCmd(11)
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
