import QtQuick
import QtQuick.Controls

// highlighted -> solid orange (primary) · flat -> ghost · default -> bordered surface
Button {
    id: c
    readonly property var t: Tokens {}
    implicitHeight: 32; leftPadding: 12; rightPadding: 12; topPadding: 0; bottomPadding: 0
    font.pixelSize: 13; font.weight: highlighted ? Font.DemiBold : Font.Medium
    hoverEnabled: true

    contentItem: Text {
        text: c.text; font: c.font; elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        color: !c.enabled ? t.muted2 : c.highlighted ? t.onAccent : t.text
    }
    background: Rectangle {
        radius: 8
        opacity: c.enabled ? 1 : 0.45
        color: c.highlighted ? (c.down ? t.accentDown : c.hovered ? t.accentHover : t.accent)
             : c.flat ? (c.down ? t.surface3 : c.hovered ? t.surface2 : "transparent")
             : (c.down ? t.surface3 : c.hovered ? t.surface3 : t.surface2)
        border.width: (c.highlighted || c.flat) ? 0 : 1
        border.color: c.hovered ? t.border2 : t.border
        Behavior on color { ColorAnimation { duration: 90 } }
    }
}
