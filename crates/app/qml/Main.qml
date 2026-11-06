import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import dev.pimpmygrub

ApplicationWindow {
    readonly property var t: Tokens {}
    id: win
    width: 1280; height: 800; minimumWidth: 960; minimumHeight: 600
    visible: true
    title: "Pimp my grub"
    color: t.bg
    font.pixelSize: 13
    palette {
        window: t.bg; windowText: t.text; base: t.bg; alternateBase: t.surface; text: t.text
        button: t.surface2; buttonText: t.text; highlight: t.accent; highlightedText: t.onAccent
        mid: t.border; midlight: t.border2; dark: t.border; light: t.border2; shadow: "#000000"
        placeholderText: t.muted2; link: t.accent; toolTipBase: t.surface3; toolTipText: t.text
    }

    Backend { id: backend }
    property var st: ({ undo: false, redo: false, name: "" })
    function refresh() { st = JSON.parse(backend.call("status", "", "")) }
    Connections { target: backend; function onRevChanged() { win.refresh() } }
    Component.onCompleted: { refresh(); backend.call("storeInit", "", "") }

    function say(msg) { toast.text = msg; toast.visible = true; toastTimer.restart() }
    function result(r, ok) { if (r.indexOf("ERR:") === 0) say(r.substring(4)); else if (ok) say(ok) }

    // an event from the store: "edit:<n>:<name>" or "install:<n>:<name>"
    Connections {
        target: backend
        function onEventChanged() {
            var p = backend.event.split(":")
            if (p[0] === "edit") { tabs.currentIndex = 0; say(qsTr("Opened “%1” in the editor").arg(p.slice(2).join(":"))) }
            else if (p[0] === "install") { tabs.currentIndex = 0; installDialog.openFor("install") }
        }
    }

    header: ToolBar {
        implicitHeight: 48
        background: Rectangle {
            color: t.surface
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: t.border }
        }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 12; spacing: 8
            // brand
            Rectangle {
                width: 26; height: 26; radius: 7; color: t.accent
                Text { anchors.centerIn: parent; text: "›_"; color: t.onAccent; font.bold: true; font.pixelSize: 13; font.family: t.mono }
            }
            Label { text: "Pimp my <font color='" + t.accent + "'>grub</font>"; textFormat: Text.StyledText; font.bold: true; font.pixelSize: 16; Layout.rightMargin: 10 }
            TabBar {
                id: tabs
                background: null
                NavTab { text: qsTr("Editor"); width: implicitWidth }
                NavTab { text: qsTr("Store"); width: implicitWidth }
            }
            Item { Layout.fillWidth: true }
            AppField {
                Layout.preferredWidth: 170; text: win.st.name; placeholderText: qsTr("Theme name")
                onEditingFinished: backend.call("setName", text, "")
            }
            AppIconButton { text: "↶"; enabled: win.st.undo; onClicked: backend.call("undo", "", ""); ToolTip.text: qsTr("Undo (Ctrl+Z)"); ToolTip.visible: hovered }
            AppIconButton { text: "↷"; enabled: win.st.redo; onClicked: backend.call("redo", "", ""); ToolTip.text: qsTr("Redo (Ctrl+Y)"); ToolTip.visible: hovered }
            Rectangle { width: 1; height: 20; color: t.border; Layout.leftMargin: 2; Layout.rightMargin: 2 }
            AppButton { text: qsTr("New"); onClicked: backend.call("new", "", "") }
            AppButton { text: qsTr("Open…"); onClicked: openMenu.open()
                Menu { id: openMenu
                    MenuItem { text: qsTr("Theme folder…"); onTriggered: openFolderDlg.open() }
                    MenuItem { text: qsTr("Zip archive…"); onTriggered: openZipDlg.open() }
                } }
            AppButton { text: qsTr("Export…"); onClicked: exportDlg.open() }
            AppButton { flat: true; text: qsTr("Manage"); onClicked: installDialog.openFor("manage"); ToolTip.text: qsTr("Undo or remove installed themes"); ToolTip.visible: hovered }
            AppButton { text: qsTr("Install…"); highlighted: true; onClicked: installDialog.openFor("install") }
        }
    }

    // status bar, like the GrubStudio editor footer
    footer: Rectangle {
        implicitHeight: 26; color: t.surface
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: t.border }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 8
            Rectangle { width: 7; height: 7; radius: 4; color: t.ok }
            Label { text: qsTr("Ready"); font.pixelSize: 11; color: t.muted }
            Label { text: "•"; font.pixelSize: 11; color: t.muted2 }
            Label { text: qsTr("Live preview active"); font.pixelSize: 11; color: t.muted }
            Item { Layout.fillWidth: true }
            Label { text: win.st.name !== "" ? win.st.name : qsTr("Untitled theme"); font.pixelSize: 11; color: t.muted; elide: Text.ElideRight; Layout.maximumWidth: 260 }
            Label { text: "•"; font.pixelSize: 11; color: t.muted2 }
            Label { text: qsTr("GRUB theme"); font.pixelSize: 11; color: t.muted }
        }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: tabs.currentIndex
        EditorPage { backend: backend; onMessage: (m) => win.say(m) }
        StorePage { backend: backend }
    }

    InstallDialog { id: installDialog; backend: backend }

    FolderDialog { id: openFolderDlg; title: qsTr("Open theme folder"); onAccepted: win.result(backend.call("openFolder", selectedFolder.toString(), ""), qsTr("Theme opened")) }
    FileDialog { id: openZipDlg; title: qsTr("Open theme archive"); nameFilters: ["Zip archives (*.zip)"]; onAccepted: win.result(backend.call("openZip", selectedFile.toString(), ""), qsTr("Theme opened")) }
    FolderDialog { id: exportDlg; title: qsTr("Choose where to save the theme folder")
        onAccepted: { var r = backend.call("exportTo", selectedFolder.toString(), ""); if (r.indexOf("ERR:") === 0) win.say(r.substring(4)); else win.say(qsTr("Saved to %1").arg(r)) } }

    Label {
        id: toast; visible: false; z: 10; padding: 10
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 18
        leftPadding: 14; rightPadding: 14
        background: Rectangle { radius: 10; color: t.surface3; border.color: t.border2
            Rectangle { x: 0; y: 8; width: 3; height: parent.height - 16; radius: 2; color: t.accent } }
        color: t.text
        Timer { id: toastTimer; interval: 3500; onTriggered: toast.visible = false }
    }
}
