import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    readonly property var t: Tokens {}
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
    function themeById(id) { var t = sd.themes; for (var i = 0; i < t.length; i++) if (t[i].id === id) return t[i]; return null }
    function openDetail(id, variant) { detail.tid = id; detail.open(); detail.variantIndex = variant }
    ThemeDetail { id: detail; store: root }
    function query() { backend.call("storeQuery", search.text, sort.currentIndex === 0 ? "stars" : "name") }

    RowLayout {
        Layout.fillWidth: true; Layout.margins: 16; spacing: 8
        AppField { id: search; Layout.fillWidth: true; placeholderText: qsTr("Search themes (name, repo, style)…"); onTextChanged: root.query() }
        AppComboBox { id: sort; implicitWidth: 150; model: [qsTr("Most popular"), qsTr("Name")]; onActivated: root.query() }
        AppButton { text: qsTr("Search GitHub"); onClicked: root.backend.call("storeGithub", search.text, "")
            ToolTip.text: qsTr("Search every GitHub repository tagged grub-theme"); ToolTip.visible: hovered }
    }
    Label { Layout.fillWidth: true; Layout.leftMargin: 16; visible: root.sd.note !== ""; text: root.sd.note; color: t.warn; wrapMode: Text.Wrap }
    BusyIndicator { id: spin; Layout.alignment: Qt.AlignHCenter; running: root.sd.pending > 0; visible: running; implicitHeight: 28; implicitWidth: 28
        contentItem: Item { implicitWidth: 28; implicitHeight: 28
            Rectangle { anchors.centerIn: parent; width: 22; height: 22; radius: 11; color: "transparent"; border.width: 3; border.color: t.border2
                Rectangle { width: 6; height: 6; radius: 3; color: t.accent; x: 8; y: -1 }
                RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: spin.running } } } }

    GridView {
        id: grid
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
        property int cols: Math.max(1, Math.floor((width - 18) / 250))
        // keep the grid inside the margins
        cellWidth: Math.floor((width - 18) / cols); cellHeight: 300
        leftMargin: 9; rightMargin: 9
        model: model
        ScrollBar.vertical: ScrollBar {}
        delegate: Item {
            id: card
            width: grid.cellWidth; height: grid.cellHeight
            property int variantIndex: 0
            readonly property string variantList: model.variants
            Component.onCompleted: if (model.hasPreview && model.preview === "") root.backend.call("preview", model.tid, "")
            HoverHandler { id: hov }
            Pane {
                anchors.fill: parent; anchors.margins: 7; padding: 0; clip: true
                background: Rectangle { radius: 12; color: t.surface; border.width: 1; border.color: hov.hovered ? t.accent : t.border
                    Behavior on border.color { ColorAnimation { duration: 120 } } }
                // Clicking anywhere on the card (the thumbnail, the title) opens the detail view.
                TapHandler { onTapped: root.openDetail(model.tid, card.variantIndex); cursorShape: Qt.PointingHandCursor }
                ColumnLayout {
                    anchors.fill: parent; spacing: 0
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: width * 9 / 16; color: t.surface2; radius: 12
                        Label { anchors.centerIn: parent; text: model.name.substring(0, 2).toUpperCase(); font.pixelSize: 26; font.bold: true; color: t.accent; opacity: 0.55; visible: img.status !== Image.Ready }
                        Image { id: img; anchors.fill: parent; source: model.preview; asynchronous: true; cache: false; fillMode: Image.PreserveAspectCrop; sourceSize.width: 480; visible: status === Image.Ready }
                        Rectangle {
                            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 8
                            width: 26; height: 26; radius: 13; color: "#b0000000"; border.width: 1; border.color: t.border2
                            visible: hov.hovered
                            Label { anchors.centerIn: parent; text: "i"; font.bold: true; font.pixelSize: 13; color: t.text }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 10; spacing: 4
                        Label { text: model.name; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                        Label { text: model.repo + "  ★ " + model.stars; color: t.muted; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                        Item { Layout.fillHeight: true }
                        // Same height whether or not the theme has several resolutions, so cards line up and nothing overflows.
                        Item {
                            Layout.fillWidth: true; Layout.preferredHeight: 32
                            AppComboBox { anchors.fill: parent; visible: card.variantList.indexOf("|") >= 0; model: card.variantList.split("|"); currentIndex: card.variantIndex; onActivated: card.variantIndex = currentIndex }
                            Label { anchors.verticalCenter: parent.verticalCenter; visible: card.variantList.indexOf("|") < 0; text: card.variantList; color: t.muted2; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width }
                        }
                        RowLayout {
                            Layout.fillWidth: true; Layout.preferredHeight: 32
                            AppButton { Layout.fillWidth: true; enabled: root.sd.busy === ""; text: root.sd.busy === model.tid ? root.sd.progress : qsTr("Edit")
                                onClicked: root.backend.call("storeGet", model.tid, "edit:" + card.variantIndex) }
                            AppButton { Layout.fillWidth: true; highlighted: true; enabled: root.sd.busy === ""; text: qsTr("Install")
                                onClicked: root.backend.call("storeGet", model.tid, "install:" + card.variantIndex) }
                        }
                    }
                }
            }
        }
    }
    Label { Layout.alignment: Qt.AlignHCenter; visible: root.sd.pending === 0 && model.count === 0; color: t.muted; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; width: parent.width - 40; text: root.sd.note !== "" ? qsTr("Couldn’t load the theme list. Check your internet connection, then restart the Store tab or press “Search GitHub”.") : qsTr("No themes match. Press “Search GitHub” to look beyond the curated list."); padding: 20 }
}
