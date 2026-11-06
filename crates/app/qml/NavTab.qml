import QtQuick
import QtQuick.Controls

// top-bar tab with an orange underline, like the GrubStudio nav
TabButton {
    id: c
    readonly property var t: Tokens {}
    implicitHeight: 40; leftPadding: 14; rightPadding: 14
    hoverEnabled: true; font.pixelSize: 13; font.weight: Font.Medium
    contentItem: Text {
        text: c.text; font: c.font
        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        color: c.checked ? t.text : c.hovered ? t.text : t.muted
    }
    background: Item {
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 2
            color: t.accent; visible: c.checked }
    }
}
