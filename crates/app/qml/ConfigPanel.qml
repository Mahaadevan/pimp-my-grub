import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The GRUB settings that live in /etc/default/grub, as switches, numbers and choices. The values are read from this
// computer; nothing is written until the person reviews the exact change and confirms it (the helper keeps a backup).
Item {
    id: root
    readonly property var t: Tokens {}
    property var backend
    property bool compact: false                    // classic layout: tighter rows
    property var info: ({ options: [], entries: [], file: "", readable: true })
    property var edits: ({})                        // id -> new value (only what differs from the file)
    readonly property int pending: Object.keys(edits).length
    signal review(var edits)

    function reload() { info = JSON.parse(backend.call("hostInfo", "", "")); edits = ({}) }
    Component.onCompleted: reload()

    function base(id) { for (var i = 0; i < info.options.length; i++) if (info.options[i].id === id) return info.options[i].value; return "" }
    function val(id) { return edits.hasOwnProperty(id) ? edits[id] : base(id) }
    function setVal(id, v) {
        var e = Object.assign({}, edits)
        if (String(v) === String(base(id))) delete e[id]; else e[id] = String(v)
        edits = e
    }
    function discard() { edits = ({}) }
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
                Label {
                    id: hint; Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.muted; font.pixelSize: 12
                    text: root.info.readable
                          ? qsTr("These values are read from <b>%1</b> on this computer. Nothing changes until you press <b>Review changes</b>, check the exact difference and confirm. A backup is made first and every change can be undone.").arg(root.info.file)
                          : qsTr("<b>%1</b> could not be read. The values below are GRUB's defaults.").arg(root.info.file)
                }
                AppButton { text: qsTr("Reload"); tip: qsTr("Read the file again and forget unsaved edits"); onClicked: root.reload() }
            }
        }
        ScrollView {
            id: sv; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentWidth: availableWidth
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
                            Layout.fillWidth: true; implicitHeight: col.implicitHeight; radius: 12; color: t.surface; border.width: 1; border.color: t.border
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
                                        Rectangle { visible: row.index > 0; anchors.top: parent.top; width: parent.width - 28; x: 14; height: 1; color: t.border }
                                        Rectangle { visible: row.changed; width: 3; height: parent.height - 16; y: 8; radius: 2; color: t.accent }
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
        // action bar
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 54; color: t.surface
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: t.border }
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 14; spacing: 10
                Rectangle { width: 8; height: 8; radius: 4; color: root.pending > 0 ? t.accent : t.border2 }
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
        AppSwitch { checked: root.val(opt.id) === "true"; enabled: root.enabledFor(opt.id); tip: opt.tip; onToggled: root.setVal(opt.id, checked ? "true" : "false") } }
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
