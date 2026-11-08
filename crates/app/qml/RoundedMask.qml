import QtQuick

// Paints the area outside rounded corners in the colour behind the card, so an image that fills a rounded frame does not
// poke its square corners out over the frame's curve and border. Place it on top of the image.
Item {
    id: m
    property real radius: 12
    property color color: "#09090b"
    property bool topOnly: false
    enabled: false
    component Corner: Canvas {
        property bool atRight: false
        property bool atBottom: false
        width: m.radius; height: m.radius
        x: atRight ? m.width - width : 0; y: atBottom ? m.height - height : 0
        onWidthChanged: requestPaint()
        Connections { target: m; function onColorChanged() { requestPaint() } }
        onPaint: {
            var c = getContext("2d"); c.reset()
            var r = width
            c.fillStyle = m.color
            if (atRight) { c.translate(r, 0); c.scale(-1, 1) }
            if (atBottom) { c.translate(0, r); c.scale(1, -1) }
            c.beginPath(); c.moveTo(0, 0); c.lineTo(r, 0); c.arc(r, r, r, -Math.PI / 2, Math.PI, true); c.lineTo(0, 0); c.closePath(); c.fill()
        }
    }
    Corner { }
    Corner { atRight: true }
    Corner { atBottom: true; visible: !m.topOnly }
    Corner { atRight: true; atBottom: true; visible: !m.topOnly }
}
