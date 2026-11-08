import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Theme.js" as Theme

// Pick the app's accent colour: presets, a hex field, or the system colour chooser. Saved between runs.
AppDialog {
    id: dlg
    property var backend
    readonly property string defaultAccent: "#ff9248"
    readonly property var presets: ["#ff9248", "#ff6b6b", "#f472b6", "#a78bfa", "#60a5fa", "#22d3ee", "#4ade80", "#facc15"]
    property string accent: Theme.accent
    title: qsTr("Appearance")
    standardButtons: Dialog.Close
    width: 400

    function setAccent(c) {
        if (!Theme.isHex(c)) return
        Theme.set(c); accent = Theme.accent
        backend.call("setSetting", "accent", c.toLowerCase())
    }
    onAboutToShow: { accent = Theme.accent; hex.text = accent }

    NativePick { id: picker; backend: dlg.backend; kind: "color"; title: qsTr("Choose the accent colour"); current: dlg.accent; onAccepted: (c) => { dlg.setAccent(c); hex.text = dlg.accent } }

    ColumnLayout {
        width: dlg.availableWidth; spacing: 12
        Label { text: qsTr("ACCENT COLOUR"); color: t.muted; font.pixelSize: 11; font.bold: true; font.letterSpacing: 0.8 }
        Flow {
            Layout.fillWidth: true; spacing: 10
            Repeater {
                model: dlg.presets
                delegate: Rectangle {
                    required property string modelData
                    width: 34; height: 34; radius: 17; color: modelData
                    border.width: dlg.accent.toLowerCase() === modelData ? 3 : 1
                    border.color: dlg.accent.toLowerCase() === modelData ? t.text : t.border2
                    scale: sw.containsMouse ? 1.08 : 1.0
                    Behavior on scale { NumberAnimation { duration: 90 } }
                    MouseArea { id: sw; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { dlg.setAccent(parent.modelData); hex.text = dlg.accent } }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Rectangle { width: 32; height: 32; radius: 8; color: dlg.accent; border.width: 1; border.color: t.border2 }
            AppField {
                id: hex; Layout.fillWidth: true; text: dlg.accent; placeholderText: "#rrggbb"; selectByMouse: true
                color: Theme.isHex(text) ? t.text : t.danger
                onTextEdited: if (Theme.isHex(text)) dlg.setAccent(text)
                onEditingFinished: if (Theme.isHex(text)) dlg.setAccent(text); else text = dlg.accent
            }
            AppButton { text: qsTr("Pick…"); onClicked: picker.open() }
        }
        AppButton { flat: true; text: qsTr("Reset to default orange"); onClicked: { dlg.setAccent(dlg.defaultAccent); hex.text = dlg.accent } }
        Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.muted2; font.pixelSize: 12
            text: qsTr("Changes buttons, highlights, links and the logo. It only affects this app, not the GRUB theme you are building.") }
    }
}
