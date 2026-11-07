import QtQuick
import QtQuick.Controls

// Number field with small up/down arrow buttons (click, or hold to repeat; Shift = bigger step; Up/Down keys work too).
// Plain numbers ("36"), percentages ("30%") and GRUB expressions ("50%-300") are all stepped; for an expression the
// pixel offset is what changes. Anything it cannot read is left alone.
AppField {
    id: c
    property real step: 1
    property real bigStep: 10
    property real minValue: -100000
    property real maxValue: 100000
    signal stepped(string value)     // emitted after an arrow click / key press; the owner applies the new text

    rightPadding: 28
    selectByMouse: true

    function clampPx(v) { return Math.max(minValue, Math.min(maxValue, v)) }
    function fmt(v) { return (Math.round(v * 100) / 100).toString() }
    function next(s, d) {
        s = s.trim(); if (s === "") s = "0"
        var m = /^(-?\d+(?:\.\d+)?)(%?)$/.exec(s)
        if (m) { var v = parseFloat(m[1]) + d; return fmt(m[2] === "%" ? v : clampPx(v)) + m[2] }
        m = /^(.*\d%)\s*([+-])\s*(\d+(?:\.\d+)?)$/.exec(s)           // 50%-300
        if (m) { var off = (m[2] === "-" ? -1 : 1) * parseFloat(m[3]) + d; return off === 0 ? m[1] : m[1] + (off < 0 ? "-" : "+") + fmt(Math.abs(off)) }
        return null
    }
    function stepBy(dir, big) {
        var r = next(text, dir * (big ? bigStep : step))
        if (r === null) return
        text = r; stepped(r)
    }
    Keys.onUpPressed: (e) => stepBy(1, e.modifiers & Qt.ShiftModifier)
    Keys.onDownPressed: (e) => stepBy(-1, e.modifiers & Qt.ShiftModifier)

    component Arrow: Item {
        id: a
        property bool up
        width: 20; height: 13
        Rectangle { anchors.fill: parent; radius: 4; color: ma.pressed ? c.t.surface3 : ma.containsMouse ? c.t.surface2 : "transparent" }
        Canvas {
            anchors.centerIn: parent; width: 8; height: 5
            property color col: ma.containsMouse ? c.t.accent : c.t.muted
            onColChanged: requestPaint()
            onPaint: {
                var g = getContext("2d"); g.reset()
                g.strokeStyle = col; g.lineWidth = 1.6; g.lineCap = "round"; g.lineJoin = "round"
                g.beginPath()
                if (a.up) { g.moveTo(1, 4); g.lineTo(4, 1); g.lineTo(7, 4) } else { g.moveTo(1, 1); g.lineTo(4, 4); g.lineTo(7, 1) }
                g.stroke()
            }
        }
        Timer { id: rep; interval: 380; repeat: true; onTriggered: { interval = 70; c.stepBy(a.up ? 1 : -1, false) } }
        MouseArea {
            id: ma; anchors.fill: parent; hoverEnabled: true; preventStealing: true; cursorShape: Qt.PointingHandCursor
            onPressed: (m) => { c.forceActiveFocus(); c.stepBy(a.up ? 1 : -1, m.modifiers & Qt.ShiftModifier); rep.interval = 380; rep.start() }
            onReleased: rep.stop()
            onCanceled: rep.stop()
        }
    }
    Column {
        anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter
        spacing: 1
        Arrow { up: true }
        Arrow { up: false }
    }
}
