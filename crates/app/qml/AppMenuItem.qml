import QtQuick
import QtQuick.Controls

// Menu entry that clearly looks disabled when it does not apply (Qt's default barely changes).
MenuItem {
    id: c
    readonly property var t: Tokens {}
    implicitHeight: 32; leftPadding: 12; rightPadding: 12
    contentItem: Text { text: c.text; font: c.font; verticalAlignment: Text.AlignVCenter; color: c.enabled ? t.text : t.muted2; elide: Text.ElideRight }
    background: Rectangle { anchors.fill: parent; anchors.margins: 2; color: c.highlighted && c.enabled ? t.surface3 : "transparent" }
}
