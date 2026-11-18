import QtQuick
import QtQuick.Controls

TabBar {
    id: c
    readonly property var t: Tokens {}
    spacing: 4; padding: 4
    background: Rectangle { color: t.surface; border.width: 1; border.color: t.border }
}
