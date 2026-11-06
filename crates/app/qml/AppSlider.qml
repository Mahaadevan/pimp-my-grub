import QtQuick
import QtQuick.Controls

Slider {
    id: c
    readonly property var t: Tokens {}
    background: Rectangle {
        x: c.leftPadding; y: c.topPadding + c.availableHeight / 2 - height / 2
        implicitWidth: 80; implicitHeight: 4; width: c.availableWidth; height: 4; radius: 2
        color: t.border2
        Rectangle { width: c.visualPosition * parent.width; height: parent.height; radius: 2; color: t.accent }
    }
    handle: Rectangle {
        x: c.leftPadding + c.visualPosition * (c.availableWidth - width)
        y: c.topPadding + c.availableHeight / 2 - height / 2
        implicitWidth: 14; implicitHeight: 14; radius: 7
        color: t.text; border.width: 2; border.color: c.pressed ? t.accentDown : t.accent
    }
}
