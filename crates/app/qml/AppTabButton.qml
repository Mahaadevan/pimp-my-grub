import QtQuick
import QtQuick.Controls

// A tab shaped like the other controls: a plain rectangle, tinted in the accent colour when selected.
TabButton {
    id: c
    readonly property var t: Tokens {}
    implicitHeight: 34; leftPadding: 16; rightPadding: 16; hoverEnabled: true
    font.pixelSize: 13
    contentItem: Text {
        text: c.text; font: c.font; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        color: c.checked ? t.accent : (c.hovered ? t.text : t.muted)
    }
    background: Rectangle {
        color: c.checked ? t.accentSoft : (c.hovered ? t.surface2 : "transparent")
        border.width: c.checked ? 1 : 0; border.color: Qt.rgba(t.accent.r, t.accent.g, t.accent.b, 0.45)
    }
}
