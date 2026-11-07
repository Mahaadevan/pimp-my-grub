import QtQuick
import QtQuick.Controls

// Small modal dialog in the app's look (used for font size, solid-colour style ...).
Dialog {
    id: c
    readonly property var t: Tokens {}
    modal: true; padding: 18
    anchors.centerIn: Overlay.overlay
    background: Rectangle { radius: 14; color: t.surface; border.width: 1; border.color: t.border2 }
    Overlay.modal: Rectangle { color: "#b0000000" }
    header: Label { text: c.title; color: t.text; font.bold: true; font.pixelSize: 15; leftPadding: 18; topPadding: 16; bottomPadding: 4 }
    footer: DialogButtonBox {
        background: null; padding: 12; spacing: 8
        delegate: AppButton { highlighted: DialogButtonBox.buttonRole === DialogButtonBox.AcceptRole }
    }
}
