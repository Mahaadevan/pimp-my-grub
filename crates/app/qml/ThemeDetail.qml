import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Full view of one store theme: large preview, description, source link and resolution choice.
AppDialog {
    id: dlg
    property var store            // StorePage
    property string tid: ""
    property int variantIndex: 0
    readonly property var theme: store ? store.themeById(tid) : null
    readonly property var variants: theme ? theme.variants : []
    readonly property bool busy: store && store.sd.busy !== ""
    title: theme ? theme.name : ""
    width: Math.min(760, (parent ? parent.width : 760) - 60)
    height: Math.min(contentItem.implicitHeight + 150, (parent ? parent.height : 700) - 40)
    onAboutToShow: variantIndex = 0
    onOpened: if (theme && theme.hasPreview && theme.preview === "") store.backend.call("preview", tid, "")

    function go(mode) { store.backend.call("storeGet", tid, mode + ":" + variantIndex); close() }

    contentItem: ScrollView {
        id: sv; clip: true; contentWidth: availableWidth
        ColumnLayout {
            width: sv.availableWidth; spacing: 12
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: Math.min(width * 9 / 16, 300); radius: 10; color: t.bg; clip: true
                border.width: 1; border.color: t.border
                Label { anchors.centerIn: parent; visible: big.status !== Image.Ready; color: t.muted
                    text: !dlg.theme ? "" : (dlg.theme.hasPreview ? qsTr("Loading preview…") : qsTr("This repository has no preview image.")) }
                Image { id: big; anchors.fill: parent; source: dlg.theme ? dlg.theme.preview : ""; asynchronous: true; cache: false
                    fillMode: Image.PreserveAspectFit; sourceSize.width: 1280; visible: status === Image.Ready }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Label { text: dlg.theme ? dlg.theme.repo : ""; color: t.text; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                Label { text: dlg.theme ? "★ " + dlg.theme.stars : ""; color: t.muted }
                AppButton { text: qsTr("Open on GitHub ↗"); flat: true; onClicked: Qt.openUrlExternally("https://github.com/" + dlg.theme.repo) }
            }
            Label { text: qsTr("Description"); color: t.muted; font.pixelSize: 11; font.bold: true; font.capitalization: Font.AllUppercase }
            Label {
                Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.text
                text: dlg.theme && dlg.theme.desc !== "" ? dlg.theme.desc : qsTr("The repository does not provide a description.")
            }
            Label { visible: dlg.variants.length > 0; text: qsTr("Resolution"); color: t.muted; font.pixelSize: 11; font.bold: true; font.capitalization: Font.AllUppercase }
            AppComboBox {
                Layout.fillWidth: true; visible: dlg.variants.length > 1
                model: dlg.variants; currentIndex: dlg.variantIndex
                onActivated: dlg.variantIndex = currentIndex
            }
            Label { visible: dlg.variants.length === 1; text: dlg.variants.length ? dlg.variants[0] : ""; color: t.text }
            Label {
                Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.muted2; font.pixelSize: 12
                text: qsTr("Edit opens a copy in the editor. Install shows every system change for review first. Only theme files (txt, png, jpg, tga, pf2) are downloaded, and only when you press a button.")
            }
        }
    }
    footer: RowLayout {
        spacing: 8
        Item { Layout.fillWidth: true; Layout.leftMargin: 18 }
        AppButton { text: qsTr("Close"); onClicked: dlg.close() }
        AppButton { enabled: !dlg.busy; text: qsTr("Edit"); onClicked: dlg.go("edit") }
        AppButton { Layout.rightMargin: 18; Layout.topMargin: 12; Layout.bottomMargin: 14; enabled: !dlg.busy; highlighted: true; text: qsTr("Install"); onClicked: dlg.go("install") }
    }
}
