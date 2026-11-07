import QtQuick
import QtQuick.Controls

// Dark dropdown that matches AppField/AppButton (the stock Basic ComboBox is light grey with a doubled chevron).
ComboBox {
    id: c
    readonly property var t: Tokens {}
    implicitHeight: 32; leftPadding: 10; rightPadding: 30; topPadding: 0; bottomPadding: 0
    font.pixelSize: 13
    hoverEnabled: true
    // An empty entry (no style/image chosen) reads as "None" instead of a blank box.
    displayText: currentText === "" && !editable ? qsTr("None") : currentText

    contentItem: Text {
        visible: !c.editable
        text: c.displayText; font: c.font; elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
        color: !c.enabled ? t.muted2 : (c.currentText === "" ? t.muted2 : t.text)
    }
    indicator: Canvas {
        x: c.width - width - 10; y: (c.height - height) / 2; width: 10; height: 6
        property color col: c.hovered || c.popup.visible ? t.text : t.muted
        onColChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d"); ctx.reset()
            ctx.strokeStyle = col; ctx.lineWidth = 1.6; ctx.lineCap = "round"; ctx.lineJoin = "round"
            ctx.beginPath(); ctx.moveTo(1, 1); ctx.lineTo(5, 5); ctx.lineTo(9, 1); ctx.stroke()
        }
    }
    background: Rectangle {
        radius: 8; color: t.bg; opacity: c.enabled ? 1 : 0.5
        border.width: 1; border.color: c.activeFocus || c.popup.visible ? t.accent : c.hovered ? t.border2 : t.border
    }
    delegate: ItemDelegate {
        id: item
        required property var modelData
        required property int index
        width: ListView.view ? ListView.view.width : c.width; height: 30
        leftPadding: 10; rightPadding: 10; topPadding: 0; bottomPadding: 0
        highlighted: c.highlightedIndex === index
        contentItem: Text {
            text: item.modelData === "" ? qsTr("None") : (typeof item.modelData === "string" ? item.modelData : (item.modelData[c.textRole] || ""))
            font: c.font; elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
            color: item.modelData === "" ? t.muted2 : (c.currentIndex === item.index ? t.accent : t.text)
        }
        background: Rectangle { radius: 6; color: item.highlighted ? t.surface3 : "transparent" }
    }
    popup: Popup {
        y: c.height + 4; width: c.width; padding: 4
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 280)
        contentItem: ListView {
            clip: true; implicitHeight: contentHeight
            model: c.popup.visible ? c.delegateModel : null
            currentIndex: c.highlightedIndex
            ScrollBar.vertical: ScrollBar {}
        }
        background: Rectangle { radius: 10; color: t.surface2; border.width: 1; border.color: t.border2 }
    }
}
