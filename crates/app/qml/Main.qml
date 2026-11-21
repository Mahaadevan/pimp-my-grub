import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Theme.js" as Theme
import dev.stylemygrub

ApplicationWindow {
    readonly property var t: Tokens {}
    id: win
    width: 1280; height: 800; minimumWidth: 900; minimumHeight: 600
    visible: true
    title: "Style My GRUB"
    color: t.bg
    font.pixelSize: 13
    // The app ships its own fonts (Inter for the UI, a symbol font for the icons) so it looks the same on a machine with no fonts installed.
    FontLoader { id: fInter; source: "qrc:/qt/qml/dev/stylemygrub/fonts/Inter-Regular.otf" }
    FontLoader { source: "qrc:/qt/qml/dev/stylemygrub/fonts/Inter-Bold.otf" }
    FontLoader { source: "qrc:/qt/qml/dev/stylemygrub/fonts/JetBrainsMono-Regular.ttf" }
    FontLoader { source: "qrc:/qt/qml/dev/stylemygrub/fonts/DejaVuSans-Symbols.ttf" }
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
    // The toolbar cannot fit everything on a narrow window, so it drops the least useful parts before the right-hand
    // buttons fall off the edge: the theme-name field first (the footer still shows the name), then the wordmark
    // (the window title bar still names the app). Measured needs: 977 px with both, 864 px without the field,
    // 738 px without the wordmark too.
    readonly property bool headerName: width >= 995
    readonly property bool headerTitle: width >= 880 || classic
    function refresh() { st = JSON.parse(backend.call("status", "", "")) }
    Connections { target: backend; function onRevChanged() { win.refresh() } }
    Component.onCompleted: { refresh(); appVersion = backend.call("version", "", ""); Theme.set(backend.call("getSetting", "accent", "")); backend.call("accent", Theme.accent, ""); classic = backend.call("getSetting", "layout", "") === "classic"; backend.call("storeInit", "", "") }

    // Messages go to the footer, so nothing floats over the canvas or the settings page.
    property string statusText: ""
    property bool statusError: false
    function say(msg) { statusText = msg; statusError = false }
    // New and Open replace everything that is open, and the editor cannot undo that, so ask first.
    function askDiscard(what) { discardDlg.doing = what; discardDlg.open() }

    function result(r, ok) { if (r.indexOf("ERR:") === 0) { statusText = r.substring(4); statusError = true } else if (ok) say(ok) }

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
            id: hdr
            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 3
            Label { visible: win.headerTitle; text: "Style My <font color='" + t.accent + "'>GRUB</font>"; textFormat: Text.StyledText; font.bold: true; font.pixelSize: 16; Layout.rightMargin: 6 }
            AppIconButton { visible: !win.classic; text: "↶"; enabled: win.st.undo; onClicked: backend.call("undo", "", ""); tip: qsTr("Undo the last edit (Ctrl+Z)") }
            AppIconButton { visible: !win.classic; text: "↷"; enabled: win.st.redo; onClicked: backend.call("redo", "", ""); tip: qsTr("Redo (Ctrl+Y)") }
            Rectangle { width: 1; height: 20; color: t.border; Layout.leftMargin: 2; Layout.rightMargin: 2 }
            TabBar {
                id: tabs
                visible: !win.classic
                background: null
                NavTab { text: qsTr("Appearance"); width: implicitWidth }
                NavTab { text: qsTr("General"); width: implicitWidth }
                NavTab { text: qsTr("List Config"); width: implicitWidth }
                NavTab { text: qsTr("Themes"); width: implicitWidth }
            }
            Item { Layout.fillWidth: true }
            // A fixed width: it steps aside entirely on a narrow window, so it never has to shrink.
            AppField {
                visible: !win.classic && win.headerName; Layout.preferredWidth: 110
                text: win.st.name; placeholderText: qsTr("Theme name")
                onEditingFinished: backend.call("setName", text, "")
            }
            Rectangle { width: 1; height: 20; color: t.border; Layout.leftMargin: 2; Layout.rightMargin: 2 }
            AppButton { visible: !win.classic; text: qsTr("File…"); leftPadding: 10; rightPadding: 10; tip: qsTr("New, open or export a theme"); onClicked: fileMenu.open()
                AppMenu {
                    id: fileMenu; y: parent.height + 2
                    AppMenuItem { text: qsTr("New theme"); onTriggered: win.askDiscard("new") }
                    AppMenuItem { text: qsTr("Open theme folder…"); onTriggered: win.askDiscard("folder") }
                    AppMenuItem { text: qsTr("Open zip archive…"); onTriggered: win.askDiscard("zip") }
                    AppMenuSeparator { }
                    AppMenuItem { text: qsTr("Export…"); onTriggered: exportDlg.open() }
                } }
            AppButton { flat: true; text: qsTr("Manage"); leftPadding: 10; rightPadding: 10; onClicked: installDialog.openFor("manage"); tip: qsTr("Undo the last GRUB change, or remove everything this app installed") }
            AppButton { text: qsTr("Install"); leftPadding: 10; rightPadding: 10; highlighted: true; tip: qsTr("Put this theme on GRUB. You review every file and change first; a backup is made and you can undo it."); onClicked: installDialog.openFor("install") }
            Rectangle { width: 1; height: 20; color: t.border; Layout.leftMargin: 2; Layout.rightMargin: 2 }
            HeaderIcon { kind: "palette"; tip: qsTr("Appearance: change the colour of this app"); onClicked: appearanceDlg.open() }
            AppButton { flat: true; text: win.classic ? qsTr("Modern") : qsTr("Classic"); leftPadding: 10; rightPadding: 10
                tip: win.classic ? qsTr("Back to the editor layout") : qsTr("Switch to the classic layout, arranged like the original GRUB Customizer: list configuration, general settings, appearance settings")
                onClicked: { win.classic = !win.classic; backend.call("setSetting", "layout", win.classic ? "classic" : "modern"); if (win.classic) classicPage.reload() } }
            HeaderIcon { kind: "github"; tip: qsTr("Style My GRUB on GitHub"); onClicked: Qt.openUrlExternally("https://github.com/Mahaadevan/style-my-grub") }
        }
    }

    // status bar, like the GrubStudio editor footer
    footer: Rectangle {
        implicitHeight: 26; color: t.surface
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: t.border }
        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 8
            Label {
                Layout.fillWidth: true; Layout.minimumWidth: 0
                text: win.statusText; color: win.statusError ? t.warn : t.muted; font.pixelSize: 11; elide: Text.ElideRight
            }
            Label { text: win.st.name !== "" ? win.st.name : qsTr("Untitled theme"); font.pixelSize: 11; color: t.muted; elide: Text.ElideRight; Layout.maximumWidth: 260 }
            Label { text: "•"; font.pixelSize: 11; color: t.muted2 }
            Label { text: qsTr("GRUB theme"); font.pixelSize: 11; color: t.muted }
            Label { text: "•"; font.pixelSize: 11; color: t.muted2; visible: win.appVersion !== "" }
            Label { text: "v" + win.appVersion; font.pixelSize: 11; color: t.muted; visible: win.appVersion !== "" }
        }
    }

    StackLayout {
        anchors.fill: parent
        currentIndex: win.classic ? 4 : tabs.currentIndex
        EditorPage { backend: backend; onMessage: (m) => win.say(m); onLivePreview: live.start() }
        ConfigPanel { id: cfgTab; backend: backend; onReview: (e) => installDialog.openSettings(e); onStatus: (m) => win.say(m) }
        HostEntriesPanel { id: entriesTab; backend: backend; grubSettings: cfgTab; onMessage: (m) => win.say(m) }
        StorePage { backend: backend }
        ClassicPage { id: classicPage; backend: backend; onInstallTheme: installDialog.openFor("install"); onLivePreview: live.start(); onMessage: (m) => win.say(m)
            onReviewSettings: (e) => installDialog.openSettings(e) }
    }

    LivePreview { id: live; backend: backend }
    InstallDialog { id: installDialog; backend: backend
        onClosed: { cfgTab.reload(); entriesTab.reload(); classicPage.reload() } }

    // System choosers (zenity / kdialog); Qt's own dialog only if neither exists.
    NativePick { id: openFolderDlg; backend: backend; kind: "dir"; title: qsTr("Open theme folder"); onAccepted: (p) => win.result(backend.call("openFolder", p, ""), qsTr("Theme opened")) }
    NativePick { id: openZipDlg; backend: backend; kind: "file"; title: qsTr("Open theme archive"); filter: "Zip archives|*.zip"; onAccepted: (p) => win.result(backend.call("openZip", p, ""), qsTr("Theme opened")) }
    NativePick { id: exportDlg; backend: backend; kind: "dir"; title: qsTr("Choose where to save the theme folder")
        onAccepted: (p) => { var r = backend.call("exportTo", p, ""); if (r.indexOf("ERR:") === 0) win.say(r.substring(4)); else win.say(qsTr("Saved to %1").arg(r)) } }
    AppearanceDialog { id: appearanceDlg; backend: backend }

    // Shown before New and Open: both throw the open theme away and the editor cannot undo that.
    // A plain Popup with its own buttons, not a Dialog: the confirm button names the action, and a Dialog's standard
    // buttons cannot be relabelled reliably (Dialog.footer is final, and Dialog.standardButton() may be null while
    // the footer is still being built, which left the button saying "OK").
    Popup {
        id: discardDlg
        property string doing: ""           // "new", "folder" or "zip"
        readonly property string currentName: win.st.name !== "" ? win.st.name : qsTr("Untitled theme")
        parent: Overlay.overlay; anchors.centerIn: Overlay.overlay
        modal: true; padding: 18; width: 470
        closePolicy: Popup.CloseOnEscape
        background: Rectangle { color: t.surface; border.width: 1; border.color: t.border2 }
        Overlay.modal: Rectangle { color: "#b0000000" }
        contentItem: ColumnLayout {
            spacing: 12
            Label { Layout.fillWidth: true; text: qsTr("The current theme will be lost"); color: t.text; font.bold: true; font.pixelSize: 15 }
            Label {
                // Plain text, not markup: the theme name is whatever the user called it.
                Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.muted; font.pixelSize: 12
                text: (discardDlg.doing === "new"
                       ? qsTr("Starting a new theme replaces “%1”.")
                       : qsTr("Opening another theme replaces “%1”.")).arg(discardDlg.currentName)
                      + " " + qsTr("This cannot be undone, so export the theme first if you want to keep a copy.")
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Item { Layout.fillWidth: true }
                AppButton { text: qsTr("Cancel"); onClicked: discardDlg.close() }
                AppButton {
                    highlighted: true
                    text: discardDlg.doing === "new" ? qsTr("Start new theme") : qsTr("Choose a theme…")
                    onClicked: {
                        var what = discardDlg.doing        // close() clears nothing here, but read it before closing
                        discardDlg.close()
                        if (what === "new") { backend.call("new", "", ""); win.say(qsTr("Started a new theme")) }
                        else if (what === "folder") openFolderDlg.open()
                        else openZipDlg.open()
                    }
                }
            }
        }
    }
}
