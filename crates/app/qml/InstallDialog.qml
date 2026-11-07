import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    readonly property var t: Tokens {}
    id: dlg
    property var backend
    property var s: ({ phase: "probe", plan: null, sys: null, result: null, live: [], error: "" })
    property bool agree: false
    property string gfx: "auto"
    modal: true; closePolicy: Dialog.NoAutoClose
    padding: 18
    background: Rectangle { radius: 14; color: t.surface; border.width: 1; border.color: t.border2 }
    Overlay.modal: Rectangle { color: "#b0000000" }
    header: Label { text: dlg.title; font.bold: true; font.pixelSize: 16; leftPadding: 18; topPadding: 16; bottomPadding: 4 }
    anchors.centerIn: Overlay.overlay
    width: Math.min(740, parent.width - 40); height: Math.min(sv.contentHeight + 120, parent.height - 40)
    title: s.mode === "manage" ? qsTr("GRUB theme manager") : qsTr("Install theme to GRUB")

    function openFor(mode) { agree = false; backend.call("installOpen", mode, ""); open() }
    function plan() { agree = false; backend.call("installPlan", nameField.text, gfx) }
    Connections {
        target: dlg.backend
        function onInstallJsonChanged() {
            var prev = dlg.s.phase
            dlg.s = JSON.parse(dlg.backend.installJson)
            if (dlg.s.phase === "review" && prev !== "review") { nameField.text = JSON.parse(dlg.backend.call("status", "", "")).name; dlg.plan() }
        }
    }
    readonly property bool nameOk: /^[A-Za-z0-9][A-Za-z0-9._-]{0,47}$/.test(nameField.text)

    footer: ColumnLayout {
        visible: s.phase === "review" && s.plan && !s.plan.fatal
        spacing: 4
        AppCheckBox { Layout.leftMargin: 12; Layout.rightMargin: 12; text: qsTr("I understand these files will be changed and that a backup is created first."); checked: dlg.agree; onToggled: dlg.agree = checked }
        RowLayout { Layout.margins: 12; Layout.topMargin: 0
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Cancel"); onClicked: dlg.close() }
            AppButton { text: qsTr("Apply changes (asks for your password)"); highlighted: true; enabled: dlg.agree && dlg.nameOk && s.plan && !s.plan.fatal
                onClicked: dlg.backend.call("installApply", nameField.text, dlg.gfx) }
        }
    }

    contentItem: ScrollView {
        id: sv; clip: true; contentWidth: availableWidth
        ColumnLayout {
            width: sv.availableWidth; spacing: 10

            Label { visible: s.phase === "probe"; text: qsTr("Checking your system…") }

            // ---- review
            ColumnLayout { visible: s.phase === "review"; Layout.fillWidth: true; spacing: 10
                Frame { Layout.fillWidth: true; background: Rectangle { color: "#10241a"; border.color: "#1f5a3a"; radius: 10 }
                    Label { width: parent.width; wrapMode: Text.Wrap; color: "#d6f5e3"; font.pixelSize: 12
                        text: qsTr("<b>Safe by design.</b> Your current <code>/etc/default/grub</code> and <code>grub.cfg</code> are backed up in <code>/var/lib/pimp-my-grub</code> first. The new boot menu is generated and validated before it replaces the old one, and any error restores everything automatically. If a theme ever fails to load, GRUB shows its plain text menu; your OS entries are never removed.") } }
                GridLayout { columns: 2; Layout.fillWidth: true
                    Label { text: qsTr("Theme name") }
                    AppField { id: nameField; Layout.fillWidth: true; onEditingFinished: if (dlg.nameOk) dlg.plan() }
                    Label { text: qsTr("Resolution") }
                    AppComboBox { Layout.fillWidth: true; model: ["auto", "1920x1080,auto", "2560x1440,auto", "1366x768,auto", "1280x720,auto", "1024x768,auto"]; currentIndex: 1
                        onActivated: { dlg.gfx = currentText; dlg.plan() } Component.onCompleted: dlg.gfx = currentText }
                }
                Label { visible: !dlg.nameOk; color: t.danger; text: qsTr("Use letters, digits, dot, dash or underscore (max 48).") }
                Label { visible: !s.plan && s.error === ""; text: qsTr("Preparing a preview of the changes…"); opacity: 0.7 }
                Label { visible: s.error !== ""; text: s.error; color: t.danger; wrapMode: Text.Wrap; Layout.fillWidth: true }
                ColumnLayout { visible: s.plan && !s.plan.fatal; Layout.fillWidth: true; spacing: 8
                    Label { text: qsTr("These system files will be changed"); font.bold: true }
                    Repeater { model: s.plan ? s.plan.changes : []
                        delegate: Frame { Layout.fillWidth: true; background: Rectangle { radius: 10; color: t.surface2; border.color: t.border }
                            RowLayout { width: parent.width; spacing: 10
                                Label { text: modelData.action.toUpperCase(); font.bold: true; font.pixelSize: 10; font.letterSpacing: 0.6; color: t.accent; Layout.preferredWidth: 64 }
                                ColumnLayout { Layout.fillWidth: true; spacing: 2
                                    Label { text: modelData.path; font.family: "monospace"; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
                                    Label { text: modelData.note; opacity: 0.65; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.Wrap } } } } }
                    Repeater { model: s.plan ? s.plan.warns : []; delegate: Label { text: "⚠ " + modelData; color: t.warn; wrapMode: Text.Wrap; Layout.fillWidth: true } }
                    Label { text: qsTr("Exact edit to /etc/default/grub"); font.bold: true }
                    ScrollView { Layout.fillWidth: true; Layout.preferredHeight: 150; clip: true
                        TextArea { readOnly: true; font.family: t.mono; font.pixelSize: 12; color: t.text; text: s.plan ? s.plan.diff : ""; wrapMode: TextArea.NoWrap
                            background: Rectangle { color: t.bg; radius: 8; border.width: 1; border.color: t.border } } }
                    Frame { Layout.fillWidth: true
                        Label { width: parent.width; wrapMode: Text.Wrap; font.pixelSize: 12
                            text: qsTr("<b>If something looks wrong later</b><br>• Open <i>Manage</i> → <i>Undo last change</i>.<br>• Original files stay in <code>/var/lib/pimp-my-grub/original/</code>. Copy <code>default-grub</code> back to <code>/etc/default/grub</code>, then run <code>sudo update-grub</code> (Debian/Ubuntu) or <code>sudo grub2-mkconfig -o /boot/grub2/grub.cfg</code> (Fedora/openSUSE).<br>• From a live USB: mount your system, restore <code>/etc/default/grub</code> and regenerate the config.") } }
                }
                RowLayout { visible: !(s.plan && !s.plan.fatal); Layout.fillWidth: true; Item { Layout.fillWidth: true } AppButton { text: qsTr("Close"); onClicked: dlg.close() } }
            }

            // ---- applying
            ColumnLayout { visible: s.phase === "applying"; Layout.fillWidth: true
                Label { text: qsTr("Working… approve the password prompt if it appears. Do not power off."); opacity: 0.8; wrapMode: Text.Wrap; Layout.fillWidth: true }
                ProgressBar { indeterminate: true; Layout.fillWidth: true
                    background: Rectangle { implicitHeight: 6; radius: 3; color: t.border }
                    contentItem: Item { implicitHeight: 6; clip: true
                        Rectangle { id: bar; width: parent.width * 0.3; height: 6; radius: 3; color: t.accent
                            SequentialAnimation on x { loops: Animation.Infinite; running: true
                                NumberAnimation { from: 0; to: bar.parent.width * 0.7; duration: 800; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: bar.parent.width * 0.7; to: 0; duration: 800; easing.type: Easing.InOutQuad } } } } }
                Repeater { model: s.live; delegate: Label { text: (index === s.live.length - 1 ? "… " : "✓ ") + modelData } } }

            // ---- done
            ColumnLayout { visible: s.phase === "done"; Layout.fillWidth: true; spacing: 8
                Label { text: qsTr("Done. The change is active and will be visible at your next reboot."); color: t.ok; font.bold: true; wrapMode: Text.Wrap; Layout.fillWidth: true }
                Repeater { model: s.result ? s.result.warns : []; delegate: Label { text: "⚠ " + modelData; color: t.warn; wrapMode: Text.Wrap; Layout.fillWidth: true } }
                RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true }
                    AppButton { text: qsTr("Undo this change"); onClicked: dlg.backend.call("installRollback", "", "") }
                    AppButton { text: qsTr("Close"); highlighted: true; onClicked: dlg.close() } } }

            // ---- failed
            ColumnLayout { visible: s.phase === "failed"; Layout.fillWidth: true; spacing: 8
                Label { text: qsTr("Nothing was broken."); font.bold: true; color: t.danger }
                Label { text: s.error; wrapMode: Text.Wrap; Layout.fillWidth: true }
                Label { visible: s.result && s.result.restored; text: qsTr("Your previous GRUB configuration was restored automatically."); color: t.ok }
                RowLayout { Layout.fillWidth: true; Item { Layout.fillWidth: true } AppButton { text: qsTr("Close"); highlighted: true; onClicked: dlg.close() } } }

            // ---- manage
            ColumnLayout { visible: s.phase === "manage"; Layout.fillWidth: true; spacing: 8
                Frame { Layout.fillWidth: true; visible: !!s.sys
                    Label { width: parent.width; wrapMode: Text.Wrap
                        text: s.sys ? qsTr("GRUB folder: %1 · %2 · %3<br>Current theme: %4<br>Pimp my grub theme: <b>%5</b>").arg(s.sys.info.grub_dir || "").arg((s.sys.info.firmware || "").toUpperCase()).arg(s.sys.info.grub_version || "").arg(s.sys.info.current_theme || qsTr("none")).arg(s.sys.info.managed_name || qsTr("none installed")) : "" } }
                Repeater { model: s.sys ? s.sys.warns : []; delegate: Label { text: "⚠ " + modelData; color: t.warn; wrapMode: Text.Wrap; Layout.fillWidth: true } }
                Label { Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.7; font.pixelSize: 12
                    text: qsTr("Undo restores the previous state (and previous theme if there was one). Remove deletes everything Pimp my grub added and restores your original theme settings. Both regenerate the boot menu safely.") }
                RowLayout { Layout.fillWidth: true
                    AppButton { text: qsTr("Undo last change"); enabled: s.sys && s.sys.info.can_rollback === "yes"; onClicked: dlg.backend.call("installRollback", "", "") }
                    AppButton { text: qsTr("Remove all Pimp my grub changes"); enabled: s.sys && !!s.sys.info.managed_name; onClicked: dlg.backend.call("installUninstall", "", "") }
                    Item { Layout.fillWidth: true }
                    AppButton { text: qsTr("Close"); onClicked: dlg.close() } } }
        }
    }
}
