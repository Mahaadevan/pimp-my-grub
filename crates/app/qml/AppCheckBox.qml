import QtQuick
import QtQuick.Controls

// Checkbox for every true/false setting. Square, like the buttons.
CheckBox {
    id: c
    readonly property var t: Tokens {}
    property string tip: ""
    spacing: 8; padding: 2
    font.pixelSize: 13
    hoverEnabled: true
    ToolTip.visible: hovered && tip !== ""; ToolTip.delay: 500; ToolTip.text: tip
    indicator: Rectangle {
        x: c.leftPadding; y: c.topPadding + (c.availableHeight - height) / 2
        implicitWidth: 18; implicitHeight: 18
        color: c.checked ? t.accent : t.bg
        border.width: 1; border.color: c.checked ? t.accent : c.hovered ? t.border2 : t.border
        opacity: c.enabled ? 1 : 0.45
        Text { anchors.centerIn: parent; text: "✓"; visible: c.checked; color: t.accentFg; font.pixelSize: 12; font.bold: true }
    }
    contentItem: Text {
        text: c.text; font: c.font; color: c.enabled ? t.text : t.muted2; wrapMode: Text.Wrap
        verticalAlignment: Text.AlignVCenter; leftPadding: c.indicator.width + c.spacing
    }
}
