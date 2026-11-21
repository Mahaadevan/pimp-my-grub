import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import dev.stylemygrub

// Drag the thin handle between the panels to make the layers list, the canvas or the inspector wider or narrower.
SplitView {
    readonly property var t: Tokens {}
    id: page
    property var backend
    property int entryCount: 5
    signal message(string m)
    signal livePreview()
    function addPlain(kind) { kind === "rect" ? backend.call("addRect", "#ff6b6b", "") : backend.call("add", kind, "") }
    function addPreset(kind, id) { var r = backend.call("addPreset", kind, id); if (r.indexOf("ERR:") === 0) page.message(r.substring(4)) }
    Shortcut { sequence: "F5"; onActivated: page.livePreview() }
    Connections { target: page.backend; function onRevChanged() { try { page.entryCount = JSON.parse(page.backend.call("status", "", "")).entries } catch (e) { } } }
    ItemMenu { id: ctx; backend: page.backend; onEdited: page.backend.call("touch", "", "")
        onStyleRequested: (k, l) => sdes.openFor(ctx.uid, k, l)
        onPresetRequested: (kind, id) => page.addPreset(kind, id); onPlainRequested: (kind) => page.addPlain(kind) }
    StyleDesigner { id: sdes; backend: page.backend; onCreated: page.backend.call("touch", "", "") }
    orientation: Qt.Horizontal
    // A SplitView handle must stay purely visual: a HoverHandler here took the hover away from the SplitView,
    // which then no longer knew which handle was grabbed and dragging did nothing. Use SplitHandle.hovered instead.
    handle: Rectangle {
        id: hHandle
        implicitWidth: 6; implicitHeight: 5; color: "transparent"
        containmentMask: Item { x: (hHandle.width - width) / 2; width: 12; height: hHandle.height }
        Rectangle {
            anchors.centerIn: parent; width: 1; height: parent.height
            color: SplitHandle.pressed ? t.accent : (SplitHandle.hovered ? t.muted2 : t.border)
        }
    }

    Pane {
        SplitView.preferredWidth: 240; SplitView.minimumWidth: 160; SplitView.maximumWidth: 460
        padding: 0
        background: Rectangle { color: t.surface }
        LayersPanel { anchors.fill: parent; backend: page.backend; ctxMenu: ctx }
    }

    ColumnLayout {
        SplitView.fillWidth: true; SplitView.minimumWidth: 380; spacing: 0
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: false
            Layout.preferredHeight: bar.implicitHeight + 12
            color: t.surface
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: t.border }
            Flow {
                id: bar
                x: 8; y: 6; width: parent.width - 16; spacing: 6
                Repeater {
                    model: [["boot_menu", qsTr("Menu"), "boot_menu", qsTr("The list of boot entries. Click for ready-made menus.")],
                            ["label", qsTr("Label"), "label", qsTr("A piece of text: titles, hints, a countdown. Click for ready-made labels.")],
                            ["image", qsTr("Image"), "", qsTr("A picture from your computer (logo, artwork).")],
                            ["rect", qsTr("Rectangle"), "rectangle", qsTr("A coloured box, panel, line or fade. Click for ready-made ones.")],
                            ["progress_bar", qsTr("Progress"), "progress_bar", qsTr("The countdown bar. Click for ready-made bars.")],
                            ["circular_progress", qsTr("Circular"), "circular_progress", qsTr("A ring or spinner that follows the countdown.")],
                            ["canvas", qsTr("Group"), "canvas", qsTr("A container that moves its contents together. Click for ready-made layouts.")]]
                    delegate: AppButton {
                        id: tb
                        readonly property string pk: modelData[2]
                        text: "+ " + modelData[1] + (pk !== "" ? "  ▾" : "")
                        tip: modelData[3]
                        onClicked: pk === "" ? page.addPlain(modelData[0]) : pmenu.popup(tb, 0, tb.height + 2)
                        PresetMenu {
                            id: pmenu; backend: page.backend; kind: tb.pk; plainText: modelData[0] === "rect" ? qsTr("Plain colour rectangle") : qsTr("Standard ") + modelData[1].toLowerCase()
                            onPlain: page.addPlain(modelData[0])
                            onChosen: (id) => page.addPreset(tb.pk, id)
                        }
                    }
                }
                Row {
                    spacing: 4; height: 32
                    Label { text: qsTr("Entry"); height: 32; leftPadding: 8; verticalAlignment: Text.AlignVCenter; color: t.muted }
                    AppSlider { id: entrySlider; width: 80; height: 32; from: 0; to: Math.max(1, page.entryCount - 1); stepSize: 1; value: 0; onMoved: page.backend.call("menuSel", Math.round(value).toString(), "") }
                }
                Row {
                    spacing: 6; height: 32
                    Label { text: qsTr("Timeout (s)"); height: 32; leftPadding: 4; verticalAlignment: Text.AlignVCenter; color: t.muted
                        ToolTip.visible: tma.containsMouse; ToolTip.text: qsTr("Seconds left on the countdown, shown by progress bars, circular spinners and labels such as \"Booting in %d s\". Default 5."); ToolTip.delay: 400
                        MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true } }
                    AppStepper {
                        id: timeoutBox; width: 76; height: 32; horizontalAlignment: TextInput.AlignHCenter
                        text: "5"; inputMethodHints: Qt.ImhDigitsOnly
                        step: 1; bigStep: 5; minValue: 0; maxValue: 3600
                        validator: IntValidator { bottom: 0; top: 3600 }
                        function apply(v) { v = Math.max(0, Math.min(3600, v)); text = v.toString(); page.backend.call("timeout", v.toString(), "") }
                        onStepped: (v) => apply(parseInt(v))
                        onTextEdited: if (text !== "") page.backend.call("timeout", Math.min(3600, parseInt(text)).toString(), "")
                        onEditingFinished: apply(text === "" ? 0 : parseInt(text))
                        WheelHandler { onWheel: function(ev) { timeoutBox.apply((parseInt(timeoutBox.text) || 0) + (ev.angleDelta.y > 0 ? 1 : -1)) } }
                    }
                }
                AppButton { text: qsTr("Load Sample Theme")
                    tip: qsTr("Open “Midnight”, the finished demo theme that ships with the app: its own background, styles, countdown bar and key hints. Undo brings your theme back.")
                    onClicked: { var r = page.backend.call("loadSample", "", ""); if (r.indexOf("ERR:") === 0) page.message(r.substring(4)) } }
                AppButton { text: qsTr("Load Current Theme")
                    tip: qsTr("Open the theme GRUB uses on this computer right now (GRUB_THEME in /etc/default/grub). It is only read; if the file is root-only the administrator password is asked once.")
                    onClicked: { var r = page.backend.call("loadCurrent", "", ""); if (r.indexOf("ERR:") === 0) page.message(r.substring(4)) } }
                AppButton { text: qsTr("Load Default Theme")
                    tip: qsTr("Start over from GRUB's own plain menu: black screen, its built-in font, a plain list whose selected row is inverted, like a freshly installed system. Undo brings your theme back.")
                    onClicked: { var r = page.backend.call("loadDefault", "", ""); if (r.indexOf("ERR:") === 0) page.message(r.substring(4)) } }
                AppButton { text: "▶  " + qsTr("Live preview"); highlighted: false
                    tip: qsTr("Show the theme full screen and try it like the real GRUB: arrow keys move, Enter picks, the countdown runs. Uses this computer's boot entries when they can be read. (F5)")
                    onClicked: page.livePreview() }
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
                if (e.modifiers & Qt.ControlModifier) {
                    var u = ""; ctx.refresh(); u = ctx.uid
                    if (e.key === Qt.Key_C && u !== "") { page.backend.call("copy", u, ""); e.accepted = true; return }
                    if (e.key === Qt.Key_X && u !== "") { page.backend.call("cut", u, ""); e.accepted = true; return }
                    if (e.key === Qt.Key_V) { page.backend.call("paste", "", ""); e.accepted = true; return }
                    if (e.key === Qt.Key_G && u !== "") { page.backend.call((e.modifiers & Qt.ShiftModifier) ? "ungroup" : "group", u, ""); e.accepted = true; return }
                }
                var n = keyName(e)
                if (n !== "") { scene.key(n, (e.modifiers & Qt.ControlModifier ? 1 : 0) | (e.modifiers & Qt.ShiftModifier ? 2 : 0)); e.accepted = true }
            }
            Keys.onReleased: (e) => { if (e.key === Qt.Key_Space && !e.isAutoRepeat) scene.input(8, 0, 0, 0, 0, 0) }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                hoverEnabled: false
                onPressed: (m) => {
                    scene.forceActiveFocus()
                    if (m.button === Qt.RightButton) { scene.input(0, m.x, m.y, 0, 0, 0); scene.input(2, m.x, m.y, 0, 0, 0); ctx.openAt(scene, m.x, m.y); return }
                    scene.input(0, m.x, m.y, 0, 0, scene.flags(m) | (m.button === Qt.MiddleButton ? 8 : 0)) }
                onPositionChanged: (m) => scene.input(1, m.x, m.y, 0, 0, scene.flags(m))
                onReleased: (m) => { if (m.button !== Qt.RightButton) scene.input(2, m.x, m.y, 0, 0, 0) }
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

    Pane {
        SplitView.preferredWidth: 310; SplitView.minimumWidth: 250; SplitView.maximumWidth: 520
        padding: 0
        background: Rectangle { color: t.surface }
        InspectorPanel { anchors.fill: parent; backend: page.backend; designer: sdes }
    }
}
