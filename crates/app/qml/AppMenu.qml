import QtQuick
import QtQuick.Controls

// Popup menu with a smooth rounded panel (Qt's default is a square box).
Menu {
    id: c
    readonly property var t: Tokens {}
    padding: 6; overlap: 2
    delegate: AppMenuItem { }
    background: Rectangle { implicitWidth: 220; implicitHeight: 36; color: t.surface2; border.width: 1; border.color: t.border2 }
}
