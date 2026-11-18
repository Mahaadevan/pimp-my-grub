import QtQuick
import QtQuick.Controls

// Slim rounded scrollbar.
ScrollBar {
    id: c
    readonly property var t: Tokens {}
    implicitWidth: 10; implicitHeight: 10; padding: 2; minimumSize: 0.08
    contentItem: Rectangle {
         implicitWidth: 6; implicitHeight: 6
        color: c.pressed ? t.muted : t.border2
        opacity: c.size < 1 ? (c.hovered || c.pressed || c.active ? 1 : 0.7) : 0
    }
    background: null
}
