import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The GRUB settings that live in /etc/default/grub, as checkboxes, numbers and choices. The values are read from this
// computer; nothing is written until the person reviews the exact change and confirms it (the helper keeps a backup).
// On the right, the file itself is shown as it will look: every line the change writes is highlighted, and clicking a
// line points at the setting it belongs to.
Item {
    id: root
    readonly property var t: Tokens {}
    property var backend
    property bool compact: false                    // classic layout: tighter rows, no file view
    property var info: ({ options: [], entries: [], file: "", readable: true })
    property var edits: ({})                        // id -> new value (only what differs from the file)
    readonly property int pending: Object.keys(edits).length
    property string note: ""                        // why an administrator read failed, if it did
    property var prev: ({ lines: [], error: "", changed: 0 })
    property string hl: ""                          // setting picked from the file view
    signal review(var edits)
    signal status(string msg)                      // one-line notes for the window footer

    function reload() {
        info = JSON.parse(backend.call("hostInfo", "", "")); edits = ({}); note = ""; refreshPreview()
        status(qsTr("Read %1 (%n setting(s))", "", info.options.length).arg(info.file))
    }
    // Most systems keep /etc/default/grub and grub.cfg readable by root only. This asks the helper (one polkit password
    // prompt) to copy them somewhere this user can read; it changes nothing on the system.
    function readElevated() {
        note = ""
        var r = backend.call("hostInfoElevated", "", "")
        if (r.indexOf("ERR:") === 0) { note = r.substring(4); status(note); return }
        info = JSON.parse(r); edits = ({}); refreshPreview()
        status(qsTr("Read %1 with Administrator rights (%n setting(s))", "", info.options.length).arg(info.file))
    }
    Component.onCompleted: reload()

    // The file as the helper will leave it, with the lines this change touches.
    function refreshPreview() {
        try { prev = JSON.parse(backend.call("cfgPreview", JSON.stringify(edits), "")) }
        catch (e) { prev = { lines: [], error: "", changed: 0 } }
    }
    function pick(id) { if (id !== "") { hl = id; hlTimer.restart() } }
    Connections { target: root; function onEditsChanged() { root.refreshPreview() } function onInfoChanged() { root.refreshPreview() } }
    Timer { id: hlTimer; interval: 2600; onTriggered: root.hl = "" }

    function base(id) { for (var i = 0; i < info.options.length; i++) if (info.options[i].id === id) return info.options[i].value; return "" }
    function val(id) { return edits.hasOwnProperty(id) ? edits[id] : base(id) }
    function setVal(id, v) {
        var e = Object.assign({}, edits)
        if (String(v) === String(base(id))) delete e[id]; else e[id] = String(v)
        edits = e
    }
    function discard() { edits = ({}); status(qsTr("Discarded unsaved changes")) }
    // settings that only make sense in combination
    function enabledFor(id) { return id !== "default_entry" || val("remember_last") !== "true" }
    // extra, situational warnings (on top of each option's standing one)
    function liveWarn(o) {
        if (o.id === "timeout" && val("timeout") === "0") return qsTr("With 0 seconds the menu never appears unless you hold a key, and recovery mode is hard to reach.")
        if (o.id === "timeout_style" && val("timeout_style") === "hidden" && Number(val("timeout")) <= 2) return qsTr("A hidden menu with a very short wait is easy to miss. You may not be able to open the menu or recovery mode.")
        if (o.id === "os_prober" && base("os_prober") === "true" && val("os_prober") === "false") return qsTr("Windows and other systems will be removed from the menu the next time it is generated.")
        return ""
    }

    ColumnLayout {
        anchors.fill: parent; spacing: 0
        // header strip
        Rectangle {
            Layout.fillWidth: true; implicitHeight: hint.implicitHeight + 20; color: t.surface
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: t.border }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 14; spacing: 10
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 3
                    Label {
                        id: hint; Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.muted; font.pixelSize: 12
                        text: root.info.readable
                              ? qsTr("These values are read from <b>%1</b> on this computer. Nothing changes until you press <b>Review changes</b>, check the exact difference and confirm. A backup is made first and every change can be undone.").arg(root.info.file)
                              : qsTr("<b>%1</b> could not be read: this system lets only root read it, so the values below are GRUB's defaults. Press <b>Read as Administrator</b> to see the real ones.").arg(root.info.file)
                    }
                    Label { visible: root.note !== ""; Layout.fillWidth: true; text: root.note; color: t.warn; font.pixelSize: 12; wrapMode: Text.Wrap }
                }
                // Shown when the files are out of reach: grub.cfg is root-only even where /etc/default/grub is not, and
                // without it there are no boot entries (so "default entry" would only offer made-up numbers).
                AppButton { visible: !root.info.readable || root.info.entries.length === 0; highlighted: true; text: qsTr("Read as Administrator…")
                    tip: qsTr("Reads /etc/default/grub and grub.cfg with administrator rights (polkit asks for your password once). Nothing is changed by doing this.")
                    onClicked: root.readElevated() }
                AppButton { text: qsTr("Reload"); tip: qsTr("Read the file again and forget unsaved edits"); onClicked: root.reload() }
            }
        }

        // The settings and the file view are a split: drag the handle between them to make the text editor wider or narrower.
        SplitView {
            id: split
            Layout.fillWidth: true; Layout.fillHeight: true
            orientation: Qt.Horizontal
            // Purely visual (no HoverHandler: that steals the hover the SplitView needs to drag the handle).
            handle: Rectangle {
                id: cHandle
                implicitWidth: 7; implicitHeight: 6; color: "transparent"
                containmentMask: Item { x: (cHandle.width - width) / 2; width: 12; height: cHandle.height }
                Rectangle {
                    anchors.centerIn: parent; width: 2; height: 28; radius: 1
                    color: SplitHandle.pressed ? t.accent : (SplitHandle.hovered ? t.muted2 : t.border2)
                }
            }

            ScrollView { ScrollBar.vertical: AppScrollBar { } ScrollBar.horizontal: AppScrollBar { }
                id: sv; SplitView.fillWidth: true; SplitView.minimumWidth: 340; SplitView.preferredWidth: 620
                clip: true; contentWidth: availableWidth
                ColumnLayout {
                    width: Math.min(sv.availableWidth, 860); x: Math.max(0, (sv.availableWidth - width) / 2)
                    spacing: root.compact ? 6 : 10
                    Item { Layout.preferredHeight: 6 }
                    Repeater {
                        model: ["Boot menu", "Kernel", "Appearance", "Advanced"]
                        delegate: ColumnLayout {
                            id: grp
                            required property string modelData
                            readonly property var rows: root.info.options.filter(function(o) { return o.group === modelData })
                            visible: rows.length > 0; Layout.fillWidth: true; Layout.leftMargin: 14; Layout.rightMargin: 14; spacing: 0
                            Label { text: modelData.toUpperCase(); color: t.muted; font.pixelSize: 11; font.bold: true; font.letterSpacing: 0.8; bottomPadding: 6; topPadding: 6 }
                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: col.implicitHeight; color: t.surface; border.width: 1; border.color: t.border
                                ColumnLayout {
                                    id: col; width: parent.width; spacing: 0
                                    Repeater {
                                        model: grp.rows
                                        delegate: Item {
                                            id: row
                                            required property var modelData
                                            required property int index
                                            readonly property var o: modelData
                                            readonly property bool changed: root.edits.hasOwnProperty(o.id)
                                            Layout.fillWidth: true; implicitHeight: Math.max(52, line.implicitHeight + 18)
                                            // the setting this line of the file belongs to, picked from the file view
                                            Rectangle { anchors.fill: parent; visible: root.hl !== "" && root.hl === row.o.id; color: t.surface3 }
                                            Rectangle { visible: row.index > 0; anchors.top: parent.top; width: parent.width - 28; x: 14; height: 1; color: t.border }
                                            Rectangle { visible: row.changed; width: 3; height: parent.height - 16; y: 8; color: t.accent }
                                            RowLayout {
                                                id: line; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: 16; anchors.rightMargin: 14; spacing: 10
                                                ColumnLayout {
                                                    Layout.fillWidth: true; spacing: 2
                                                    RowLayout {
                                                        spacing: 6
                                                        Label { text: row.o.label; font.pixelSize: 13; color: root.enabledFor(row.o.id) ? t.text : t.muted2; elide: Text.ElideRight; Layout.fillWidth: true }
                                                        WarnBadge { text: root.liveWarn(row.o) !== "" ? root.liveWarn(row.o) : row.o.warn; strong: root.liveWarn(row.o) !== "" }
                                                    }
                                                    Label { Layout.fillWidth: true; text: row.o.tip; color: t.muted2; font.pixelSize: 11; wrapMode: Text.Wrap; visible: !root.compact; maximumLineCount: 3; elide: Text.ElideRight }
                                                }
                                                Loader {
                                                    Layout.alignment: Qt.AlignVCenter
                                                    sourceComponent: row.o.kind === "switch" ? swc : row.o.kind === "number" ? numc : row.o.kind === "select" ? selc : txtc
                                                    property var opt: row.o
                                                }
                                            }
                                            HoverHandler { id: rowHover }
                                            ToolTip.visible: rowHover.hovered && root.compact; ToolTip.delay: 600; ToolTip.timeout: 20000; ToolTip.text: row.o.tip
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Item { Layout.preferredHeight: 12 }
                }
            }

            // The file itself, as the helper will leave it (read-only: the settings are edited on the left, and this
            // shows exactly what they write). Drag the split handle to resize it.
            Rectangle {
                visible: !root.compact
                SplitView.minimumWidth: 260; SplitView.preferredWidth: Math.max(320, Math.min(470, root.width * 0.34)); color: t.bg
                ColumnLayout {
                    anchors.fill: parent; spacing: 0
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: 38; color: t.surface
                        RowLayout {
                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 12; spacing: 8
                            Label { text: qsTr("/etc/default/grub, as it will look"); font.pixelSize: 12; font.bold: true; color: t.text; Layout.fillWidth: true; elide: Text.ElideRight }
                            Label { text: root.prev.changed > 0 ? qsTr("%n changed line(s)", "", root.prev.changed) : qsTr("no changes"); color: root.prev.changed > 0 ? t.accent : t.muted; font.pixelSize: 11 }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: t.border }
                    Flickable {
                        id: fileView; Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                        contentWidth: width; contentHeight: fileCol.implicitHeight + 12
                        ScrollBar.vertical: AppScrollBar { }
                        Column {
                            id: fileCol; width: parent.width; y: 6; spacing: 0
                            Repeater {
                                model: root.prev.lines
                                delegate: Rectangle {
                                    id: fl
                                    required property var modelData
                                    width: fileCol.width; height: Math.max(18, ft.implicitHeight + 6)
                                    color: modelData.changed ? t.surface3 : "transparent"
                                    Rectangle { visible: modelData.changed; width: 3; height: parent.height; color: t.accent }
                                    Rectangle { visible: !modelData.changed && modelData.option !== ""; width: 3; height: parent.height; color: t.border2 }
                                    Row {
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: 10; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10
                                        Label { text: fl.modelData.n; width: 20; horizontalAlignment: Text.AlignRight; color: t.muted2; font.pixelSize: 11; font.family: "JetBrains Mono" }
                                        Text {
                                            id: ft
                                            width: fl.width - 48; textFormat: Text.PlainText; text: fl.modelData.text
                                            color: fl.modelData.kind === "tag" ? t.muted2 : (fl.modelData.changed ? t.text : t.muted)
                                            font.family: "JetBrains Mono"; font.pixelSize: 11
                                            wrapMode: Text.NoWrap; elide: Text.ElideRight
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent; enabled: fl.modelData.option !== ""; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.pick(fl.modelData.option)
                                    }
                                }
                            }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: t.border }
                    Label {
                        Layout.fillWidth: true; Layout.margins: 12; wrapMode: Text.Wrap; color: t.muted2; font.pixelSize: 11
                        text: root.prev.error !== ""
                              ? root.prev.error
                              : qsTr("Read-only: your own lines are never edited. The app writes one marked block at the end of the file, and the highlighted lines are what this change puts there. Click a line to find its setting.")
                    }
                }
            }
        }

        // action bar
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 54; color: t.surface
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: t.border }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 14; spacing: 10
                Rectangle { width: 8; height: 8; color: root.pending > 0 ? t.accent : t.border2 }
                Label { text: root.pending > 0 ? qsTr("%n unsaved change(s)", "", root.pending) : qsTr("No changes yet"); color: root.pending > 0 ? t.text : t.muted; font.pixelSize: 12 }
                Item { Layout.fillWidth: true }
                AppButton { text: qsTr("Discard"); enabled: root.pending > 0; tip: qsTr("Throw away the edits on this page"); onClicked: root.discard() }
                AppButton { text: qsTr("Review changes…"); highlighted: true; enabled: root.pending > 0
                    tip: qsTr("Shows exactly what will change in /etc/default/grub and grub.cfg. You confirm before anything is written.")
                    onClicked: root.review(root.edits) }
            }
        }
    }

    Component { id: swc
        AppCheckBox { checked: root.val(opt.id) === "true"; enabled: root.enabledFor(opt.id); tip: opt.tip; onToggled: root.setVal(opt.id, checked ? "true" : "false") } }
    Component { id: numc
        AppStepper { implicitWidth: 110; text: root.val(opt.id); enabled: root.enabledFor(opt.id)
            minValue: opt.id === "timeout" ? -1 : 0; maxValue: 3600; step: 1; bigStep: 5
            validator: IntValidator { bottom: -1; top: 3600 }
            onStepped: (v) => root.setVal(opt.id, v); onEditingFinished: if (text !== "") root.setVal(opt.id, text) } }
    Component { id: selc
        AppComboBox { implicitWidth: 240; enabled: root.enabledFor(opt.id)
            model: opt.options.map(function(x) { return x.l })
            Component.onCompleted: sync()
            function sync() { var v = root.val(opt.id); for (var i = 0; i < opt.options.length; i++) if (opt.options[i].v === v) { currentIndex = i; return } currentIndex = 0 }
            Connections { target: root; function onEditsChanged() { sync() } function onInfoChanged() { sync() } }
            onActivated: root.setVal(opt.id, opt.options[currentIndex].v) } }
    Component { id: txtc
        AppField { implicitWidth: 300; text: root.val(opt.id); selectByMouse: true
            onEditingFinished: root.setVal(opt.id, text) } }
}
