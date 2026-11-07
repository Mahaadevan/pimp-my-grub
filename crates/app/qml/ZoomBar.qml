import QtQuick
import QtQuick.Controls

// Floating view controls for the canvas: zoom out / zoom level / zoom in, fit to window, and centre.
// "Centre" recovers a view that was scrolled or panned away without changing the zoom.
Rectangle {
    id: bar
    readonly property var t: Tokens {}
    property int zoom: 100
    signal zoomIn()
    signal zoomOut()
    signal actualSize()
    signal fit()
    signal center()

    implicitWidth: row.implicitWidth + 12; implicitHeight: 40
    radius: 14; color: "#ea121214"
    border.width: 1; border.color: t.border2

    component IconBtn: Item {
        id: b
        property string kind
        property string tip
        signal clicked()
        implicitWidth: 32; implicitHeight: 32
        Rectangle {
            anchors.fill: parent; anchors.margins: 1; radius: 9
            color: ma.pressed ? t.surface3 : ma.containsMouse ? t.surface2 : "transparent"
            Behavior on color { ColorAnimation { duration: 90 } }
        }
        Canvas {
            id: cv; anchors.centerIn: parent; width: 16; height: 16
            property color col: ma.containsMouse ? t.accent : t.text
            onColChanged: requestPaint()
            onPaint: {
                var c = getContext("2d"); c.reset()
                c.strokeStyle = col; c.lineWidth = 1.8; c.lineCap = "round"; c.lineJoin = "round"
                c.beginPath()
                if (b.kind === "minus") { c.moveTo(3, 8); c.lineTo(13, 8) }
                else if (b.kind === "plus") { c.moveTo(3, 8); c.lineTo(13, 8); c.moveTo(8, 3); c.lineTo(8, 13) }
                else if (b.kind === "fit") {   // four corner brackets
                    c.moveTo(2, 6); c.lineTo(2, 2); c.lineTo(6, 2); c.moveTo(10, 2); c.lineTo(14, 2); c.lineTo(14, 6)
                    c.moveTo(14, 10); c.lineTo(14, 14); c.lineTo(10, 14); c.moveTo(6, 14); c.lineTo(2, 14); c.lineTo(2, 10)
                } else {                       // centre: ring with four ticks
                    c.arc(8, 8, 3, 0, Math.PI * 2)
                    c.moveTo(8, 1); c.lineTo(8, 4); c.moveTo(8, 12); c.lineTo(8, 15); c.moveTo(1, 8); c.lineTo(4, 8); c.moveTo(12, 8); c.lineTo(15, 8)
                }
                c.stroke()
            }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
        ToolTip.visible: ma.containsMouse; ToolTip.delay: 450; ToolTip.text: b.tip
    }

    Row {
        id: row
        anchors.centerIn: parent; spacing: 2
        IconBtn { kind: "minus"; tip: qsTr("Zoom out  (−)"); onClicked: bar.zoomOut() }
        Item {
            width: 56; height: 32
            Rectangle { anchors.fill: parent; anchors.margins: 1; radius: 9; color: zma.pressed ? t.surface3 : zma.containsMouse ? t.surface2 : "transparent" }
            Text { anchors.centerIn: parent; text: bar.zoom + "%"; color: zma.containsMouse ? t.accent : t.text; font.pixelSize: 12; font.bold: true; font.family: t.mono }
            MouseArea { id: zma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bar.actualSize() }
            ToolTip.visible: zma.containsMouse; ToolTip.delay: 450; ToolTip.text: qsTr("Actual size (100%)")
        }
        IconBtn { kind: "plus"; tip: qsTr("Zoom in  (+)"); onClicked: bar.zoomIn() }
        Rectangle { width: 1; height: 18; anchors.verticalCenter: parent.verticalCenter; color: t.border2 }
        IconBtn { kind: "fit"; tip: qsTr("Fit to window  (0)"); onClicked: bar.fit() }
        IconBtn { kind: "center"; tip: qsTr("Centre the screen  (C)"); onClicked: bar.center() }
    }
}
