import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Theme.js" as Theme
import dev.pimpmygrub

ApplicationWindow {
    readonly property var t: Tokens {}
    id: win
    width: 1280; height: 800; minimumWidth: 1120; minimumHeight: 600
    visible: true
    title: "Pimp my GRUB"
    color: t.bg
    font.pixelSize: 13
    // The app ships its own fonts (Inter for the UI, a symbol font for the icons) so it looks the same on a machine with no fonts installed.
    FontLoader { id: fInter; source: "qrc:/qt/qml/dev/pimpmygrub/fonts/Inter-Regular.otf" }
    FontLoader { source: "qrc:/qt/qml/dev/pimpmygrub/fonts/Inter-Bold.otf" }
    FontLoader { source: "qrc:/qt/qml/dev/pimpmygrub/fonts/JetBrainsMono-Regular.ttf" }
    FontLoader { source: "qrc:/qt/qml/dev/pimpmygrub/fonts/DejaVuSans-Symbols.ttf" }
    font.family: fInter.status === FontLoader.Ready ? fInter.name : "sans-serif"
    palette {
        window: t.bg; windowText: t.text; base: t.bg; alternateBase: t.surface; text: t.text
        button: t.surface2; buttonText: t.text; highlight: t.accent; highlightedText: t.accentFg
        mid: t.border; midlight: t.border2; dark: t.border; light: t.border2; shadow: "#000000"
        placeholderText: t.muted2; link: t.accent; toolTipBase: t.surface3; toolTipText: t.text
    }

    Backend { id: backend }
    property var st: ({ undo: false, redo: false, name: "" })
    property string appVersion: ""
    property bool classic: false           // the classic (GRUB Customizer style) layout
    function refresh() { st = JSON.parse(backend.call("status", "", "")) }
    Connections { target: backend; function onRevChanged() { win.refresh() } }
    Component.onCompleted: { refresh(); appVersion = backend.call("version", "", ""); Theme.set(backend.call("getSetting", "accent", "")); backend.call("accent", Theme.accent, ""); classic = backend.call("getSetting", "layout", "") === "classic"; backend.call("storeInit", "", "") }

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
                Text { anchors.centerIn: parent; text: "›_"; color: t.accentFg; font.bold: true; font.pixelSize: 13; font.family: t.mono }
            }
            Label { text: "Pimp my <font color='" + t.accent + "'>GRUB</font>"; textFormat: Text.StyledText; font.bold: true; font.pixelSize: 16; Layout.rightMargin: 10 }
            TabBar {
                id: tabs
                visible: !win.classic
                background: null
                NavTab { text: qsTr("Editor"); width: implicitWidth }
                NavTab { text: qsTr("Store"); width: implicitWidth }
                NavTab { text: qsTr("GRUB settings"); width: implicitWidth }
            }
            Item { Layout.fillWidth: true }
            AppField {
                visible: !win.classic; Layout.preferredWidth: 150; text: win.st.name; placeholderText: qsTr("Theme name")
                onEditingFinished: backend.call("setName", text, "")
            }
            AppIconButton { visible: !win.classic; text: "↶"; enabled: win.st.undo; onClicked: backend.call("undo", "", ""); tip: qsTr("Undo the last edit (Ctrl+Z)") }
            AppIconButton { visible: !win.classic; text: "↷"; enabled: win.st.redo; onClicked: backend.call("redo", "", ""); tip: qsTr("Redo (Ctrl+Y)") }
            Rectangle { width: 1; height: 20; color: t.border; Layout.leftMargin: 2; Layout.rightMargin: 2 }
            AppButton { visible: !win.classic; text: qsTr("New"); tip: qsTr("Start an empty theme"); onClicked: backend.call("new", "", "") }
            AppButton { visible: !win.classic; text: qsTr("Open…"); tip: qsTr("Open a theme folder or a .zip to edit"); onClicked: openMenu.open()
                Menu { id: openMenu
                    MenuItem { text: qsTr("Theme folder…"); onTriggered: openFolderDlg.open() }
                    MenuItem { text: qsTr("Zip archive…"); onTriggered: openZipDlg.open() }
                } }
            AppButton { visible: !win.classic; text: qsTr("Export…"); tip: qsTr("Save the theme as a folder you can copy to /boot/grub/themes yourself"); onClicked: exportDlg.open() }
            AppButton { flat: true; text: qsTr("Manage"); onClicked: installDialog.openFor("manage"); tip: qsTr("Undo the last GRUB change, or remove everything this app installed") }
            AppButton { text: qsTr("Install…"); highlighted: true; tip: qsTr("Put this theme on GRUB. You review every file and change first; a backup is made and you can undo it."); onClicked: installDialog.openFor("install") }
            Rectangle { width: 1; height: 20; color: t.border; Layout.leftMargin: 2; Layout.rightMargin: 2 }
            HeaderIcon { kind: "palette"; tip: qsTr("Appearance: change the colour of this app"); onClicked: appearanceDlg.open() }
            AppButton { flat: true; text: win.classic ? qsTr("Modern") : qsTr("Classic")
                tip: win.classic ? qsTr("Back to the editor layout") : qsTr("Switch to the classic layout, arranged like the original GRUB Customizer: list configuration, general settings, appearance settings")
                onClicked: { win.classic = !win.classic; backend.call("setSetting", "layout", win.classic ? "classic" : "modern"); if (win.classic) classicPage.reload() } }
            HeaderIcon { kind: "github"; tip: qsTr("Pimp my GRUB on GitHub"); onClicked: Qt.openUrlExternally("https://github.com/Mahaadevan/pimp-my-grub") }
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
            Label { text: "•"; font.pixelSize: 11; color: t.muted2; visible: win.appVersion !== "" }
            Label { text: "v" + win.appVersion; font.pixelSize: 11; color: t.muted; visible: win.appVersion !== "" }
        }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: win.classic ? 3 : tabs.currentIndex
        EditorPage { backend: backend; onMessage: (m) => win.say(m); onLivePreview: live.start() }
        StorePage { backend: backend }
        ConfigPanel { id: cfgTab; backend: backend; onReview: (e) => installDialog.openSettings(e) }
        ClassicPage { id: classicPage; backend: backend; onInstallTheme: installDialog.openFor("install"); onLivePreview: live.start(); onMessage: (m) => win.say(m)
            onReviewSettings: (e) => installDialog.openSettings(e) }
    }

    LivePreview { id: live; backend: backend }
    InstallDialog { id: installDialog; backend: backend
        onClosed: { cfgTab.reload(); classicPage.reload() } }

    // System choosers (zenity / kdialog); Qt's own dialog only if neither exists.
    NativePick { id: openFolderDlg; backend: backend; kind: "dir"; title: qsTr("Open theme folder"); onAccepted: (p) => win.result(backend.call("openFolder", p, ""), qsTr("Theme opened")) }
    NativePick { id: openZipDlg; backend: backend; kind: "file"; title: qsTr("Open theme archive"); filter: "Zip archives|*.zip"; onAccepted: (p) => win.result(backend.call("openZip", p, ""), qsTr("Theme opened")) }
    NativePick { id: exportDlg; backend: backend; kind: "dir"; title: qsTr("Choose where to save the theme folder")
        onAccepted: (p) => { var r = backend.call("exportTo", p, ""); if (r.indexOf("ERR:") === 0) win.say(r.substring(4)); else win.say(qsTr("Saved to %1").arg(r)) } }
    AppearanceDialog { id: appearanceDlg; backend: backend }

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
