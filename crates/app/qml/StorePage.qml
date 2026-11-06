import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    property var backend
    property var sd: ({ themes: [], pending: 0, note: "", busy: "", progress: "" })
    spacing: 0

    Connections {
        target: root.backend
        function onStoreJsonChanged() { root.sd = JSON.parse(root.backend.storeJson); root.syncModel() }
    }
    ListModel { id: model }
    // update in place when the set of cards is unchanged, so scrolling does not jump while previews arrive
    function syncModel() {
        var t = sd.themes, same = t.length === model.count
        for (var i = 0; same && i < t.length; i++) if (model.get(i).tid !== t[i].id) same = false
        if (!same) { model.clear(); for (var j = 0; j < t.length; j++) model.append({ tid: t[j].id, name: t[j].name, repo: t[j].repo, stars: t[j].stars, preview: t[j].preview, hasPreview: t[j].hasPreview, variants: t[j].variants.join("|") }) }
        else for (var k = 0; k < t.length; k++) if (model.get(k).preview !== t[k].preview) model.setProperty(k, "preview", t[k].preview)
    }
    function query() { backend.call("storeQuery", search.text, sort.currentIndex === 0 ? "stars" : "name") }

    RowLayout {
        Layout.fillWidth: true; Layout.margins: 12; spacing: 8
        TextField { id: search; Layout.fillWidth: true; placeholderText: qsTr("Search themes (name, repo, style)…"); onTextChanged: root.query(); leftPadding: 12 }
        ComboBox { id: sort; model: [qsTr("Most popular"), qsTr("Name")]; onActivated: root.query() }
        Button { text: qsTr("Search GitHub"); onClicked: root.backend.call("storeGithub", search.text, "")
            ToolTip.text: qsTr("Search every GitHub repository tagged grub-theme"); ToolTip.visible: hovered }
    }
    Label { Layout.fillWidth: true; Layout.leftMargin: 12; visible: root.sd.note !== ""; text: root.sd.note; color: "#e0a030"; wrapMode: Text.Wrap }
    BusyIndicator { Layout.alignment: Qt.AlignHCenter; running: root.sd.pending > 0; visible: running; implicitHeight: 28 }

    GridView {
        id: grid
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
        property int cols: Math.max(1, Math.floor(width / 250))
        cellWidth: Math.floor(width / cols); cellHeight: 250
        model: model
        ScrollBar.vertical: ScrollBar {}
        delegate: Item {
            id: card
            width: grid.cellWidth; height: grid.cellHeight
            property int variantIndex: 0
            readonly property string variantList: model.variants
            Component.onCompleted: if (model.hasPreview && model.preview === "") root.backend.call("preview", model.tid, "")
            Pane {
                anchors.fill: parent; anchors.margins: 7; padding: 0
                background: Rectangle { radius: 8; color: palette.base; border.color: palette.mid }
                ColumnLayout {
                    anchors.fill: parent; spacing: 0
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: width * 9 / 16; color: palette.alternateBase; radius: 8
                        Label { anchors.centerIn: parent; text: model.name.substring(0, 2).toUpperCase(); font.pixelSize: 26; font.bold: true; opacity: 0.35; visible: img.status !== Image.Ready }
                        Image { id: img; anchors.fill: parent; source: model.preview; asynchronous: true; cache: false; fillMode: Image.PreserveAspectCrop; sourceSize.width: 480; visible: status === Image.Ready }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.margins: 8; spacing: 3
                        Label { text: model.name; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: model.repo + "  ★ " + model.stars; opacity: 0.6; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                        ComboBox { visible: card.variantList.indexOf("|") >= 0; Layout.fillWidth: true; model: card.variantList.split("|"); onActivated: card.variantIndex = currentIndex }
                        Item { Layout.fillHeight: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Button { Layout.fillWidth: true; enabled: root.sd.busy === ""; text: root.sd.busy === model.tid ? root.sd.progress : qsTr("Edit")
                                onClicked: root.backend.call("storeGet", model.tid, "edit:" + card.variantIndex) }
                            Button { Layout.fillWidth: true; highlighted: true; enabled: root.sd.busy === ""; text: qsTr("Install")
                                onClicked: root.backend.call("storeGet", model.tid, "install:" + card.variantIndex) }
                        }
                    }
                }
            }
        }
    }
    Label { Layout.alignment: Qt.AlignHCenter; visible: root.sd.pending === 0 && model.count === 0; opacity: 0.6; text: qsTr("No themes match. Press “Search GitHub” to look beyond the curated list."); padding: 20 }
}
