import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import dev.pimpmygrub

ApplicationWindow {
    id: win
    width: 1280; height: 800; minimumWidth: 960; minimumHeight: 600
    visible: true
    title: "Pimp my grub"

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
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 6
            Label { text: "Pimp my grub"; font.bold: true; font.pixelSize: 15 }
            TabBar {
                id: tabs
                background: null
                TabButton { text: qsTr("Editor"); width: implicitWidth }
                TabButton { text: qsTr("Store"); width: implicitWidth }
            }
            Item { Layout.fillWidth: true }
            TextField {
                Layout.preferredWidth: 150; text: win.st.name; placeholderText: qsTr("Theme name")
                onEditingFinished: backend.call("setName", text, "")
            }
            ToolButton { text: "↶"; enabled: win.st.undo; onClicked: backend.call("undo", "", ""); ToolTip.text: qsTr("Undo (Ctrl+Z)"); ToolTip.visible: hovered }
            ToolButton { text: "↷"; enabled: win.st.redo; onClicked: backend.call("redo", "", ""); ToolTip.text: qsTr("Redo (Ctrl+Y)"); ToolTip.visible: hovered }
            Button { text: qsTr("New"); onClicked: backend.call("new", "", "") }
            Button { text: qsTr("Open…"); onClicked: openMenu.open()
                Menu { id: openMenu
                    MenuItem { text: qsTr("Theme folder…"); onTriggered: openFolderDlg.open() }
                    MenuItem { text: qsTr("Zip archive…"); onTriggered: openZipDlg.open() }
                } }
            Button { text: qsTr("Export…"); onClicked: exportDlg.open() }
            Button { text: qsTr("Install…"); highlighted: true; onClicked: installDialog.openFor("install") }
            ToolButton { text: qsTr("Manage"); onClicked: installDialog.openFor("manage"); ToolTip.text: qsTr("Undo or remove installed themes"); ToolTip.visible: hovered }
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
        anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 16
        background: Rectangle { radius: 6; color: palette.toolTipBase; border.color: palette.mid }
        color: palette.toolTipText
        Timer { id: toastTimer; interval: 3500; onTriggered: toast.visible = false }
    }
}
