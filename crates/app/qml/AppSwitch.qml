import QtQuick
import QtQuick.Controls

// On/off toggle (used for every true/false setting).
Switch {
    id: c
    readonly property var t: Tokens {}
    property string tip: ""
    implicitHeight: 28; implicitWidth: 46; padding: 0; hoverEnabled: true
    ToolTip.visible: hovered && tip !== ""; ToolTip.delay: 500; ToolTip.text: tip
    indicator: Rectangle {
        x: c.leftPadding; y: (c.height - height) / 2
        implicitWidth: 42; implicitHeight: 22; radius: 11
        color: c.checked ? t.accent : t.surface3
        border.width: 1; border.color: c.checked ? t.accent : (c.hovered ? t.border2 : t.border)
        opacity: c.enabled ? 1 : 0.45
        Behavior on color { ColorAnimation { duration: 110 } }
        Rectangle {
            y: 3; x: c.checked ? parent.width - width - 3 : 3
            width: 16; height: 16; radius: 8
            color: c.checked ? t.accentFg : t.text
            Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
        }
    }
    contentItem: Item { }
}
