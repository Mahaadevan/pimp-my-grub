import QtQuick
import QtQuick.Controls

// A small warning triangle that explains, on hover, how a setting could stop GRUB (or the system) from working.
Item {
    id: c
    readonly property var t: Tokens {}
    property string text: ""
    property bool strong: false          // red instead of amber for the most dangerous settings
    visible: text !== ""
    implicitWidth: visible ? 22 : 0; implicitHeight: 22
    Text {
        anchors.centerIn: parent; text: "⚠"; font.pixelSize: 15
        color: c.strong ? t.danger : t.warn
        opacity: ma.containsMouse ? 1 : 0.85
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.WhatsThisCursor }
    ToolTip.visible: ma.containsMouse; ToolTip.delay: 150; ToolTip.timeout: 20000
    ToolTip.text: "<b>Careful:</b> " + c.text
}
