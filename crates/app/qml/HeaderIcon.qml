import QtQuick
import QtQuick.Controls

// Small icon button for the header: "github" opens the project page, "palette" opens the appearance dialog.
Item {
    id: h
    readonly property var t: Tokens {}
    property string kind: "github"
    property string tip: ""
    signal clicked()
    implicitWidth: 34; implicitHeight: 34
    Rectangle { anchors.fill: parent; anchors.margins: 1; radius: 9; color: ma.pressed ? t.surface3 : ma.containsMouse ? t.surface2 : "transparent" }
    Image {
        visible: h.kind === "github"; anchors.centerIn: parent; width: 18; height: 18
        sourceSize.width: 36; sourceSize.height: 36; smooth: true; mipmap: true
        opacity: ma.containsMouse ? 1.0 : 0.72
        source: "data:image/png;base64,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"
    }
    Canvas {
        id: pal; visible: h.kind === "palette"; anchors.centerIn: parent; width: 18; height: 18
        property color col: ma.containsMouse ? t.accent : t.muted
        onColChanged: requestPaint()
        onPaint: {
            var c = getContext("2d"); c.reset(); c.strokeStyle = col; c.fillStyle = col; c.lineWidth = 1.7; c.lineCap = "round"
            c.beginPath(); c.arc(9, 9, 7.2, 0, Math.PI * 2); c.stroke()
            var d = [[5.6, 7.4], [9, 5], [12.4, 7.4], [11.6, 11.6]]
            for (var i = 0; i < d.length; i++) { c.beginPath(); c.arc(d[i][0], d[i][1], 1.25, 0, Math.PI * 2); c.fill() }
        }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: h.clicked() }
    ToolTip.visible: ma.containsMouse; ToolTip.delay: 400; ToolTip.text: h.tip
}
