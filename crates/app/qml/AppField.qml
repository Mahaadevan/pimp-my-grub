import QtQuick
import QtQuick.Controls

TextField {
    id: c
    readonly property var t: Tokens {}
    implicitHeight: 32; leftPadding: 10; rightPadding: 10; topPadding: 0; bottomPadding: 0
    font.pixelSize: 13
    color: t.text; placeholderTextColor: t.muted2
    selectionColor: t.accent; selectedTextColor: t.onAccent
    verticalAlignment: TextInput.AlignVCenter
    background: Rectangle {
        radius: 8; color: t.bg
        border.width: 1; border.color: c.activeFocus ? t.accent : c.hovered ? t.border2 : t.border
    }
}
