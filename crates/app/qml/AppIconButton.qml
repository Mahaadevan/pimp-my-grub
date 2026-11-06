import QtQuick
import QtQuick.Controls

// small square ghost button for glyphs (undo, lock, eye, upload ...)
Button {
    id: c
    readonly property var t: Tokens {}
    flat: true; hoverEnabled: true
    implicitWidth: 30; implicitHeight: 30; padding: 2
    font.pixelSize: 14
    contentItem: Text {
        text: c.text; font: c.font
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        color: !c.enabled ? t.muted2 : c.hovered ? t.text : t.muted
    }
    background: Rectangle {
        radius: 6
        color: c.down ? t.surface3 : c.hovered ? t.surface2 : "transparent"
        opacity: c.enabled ? 1 : 0.5
    }
}
