import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import dev.stylemygrub

// The boot entries GRUB lists on this computer (read from grub.cfg). Read-only on purpose: GRUB regenerates that file from
// /etc/default/grub and /etc/grub.d, so a hand edit is lost at the next kernel update, and a mistake there can stop the
// computer from booting. The default entry is changed on the General page instead, with a review and a backup.
Item {
    id: root
    readonly property var t: Tokens {}
    property var backend
    property var grubSettings: null                 // the GRUB settings panel, for the "default" marker
    property var entries: []
    property string cfgFile: ""
    signal message(string m)

    function useHost(h) { entries = h.entries || []; cfgFile = h.cfg || "" }
    function reload() { try { useHost(JSON.parse(backend.call("hostInfo", "", ""))) } catch (e) { entries = [] } }
    // grub.cfg is root-only on most systems, so the list stays empty until the person reads it with administrator rights.
    // That only copies the file for reading: this panel never writes to grub.cfg.
    function loadElevated() {
        var r = backend.call("hostInfoElevated", "", "")
        if (r.indexOf("ERR:") === 0) { root.message(r.substring(4)); return }
        try { useHost(JSON.parse(r)) } catch (e) { entries = [] }
    }
    function isDefault(id) {
        return grubSettings !== null && grubSettings.val("remember_last") !== "true" && grubSettings.val("default_entry") === id
    }
    Component.onCompleted: reload()

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 10
        Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.muted; font.pixelSize: 12
            text: root.entries.length > 0
                  ? qsTr("The entries below are what GRUB lists on this computer (from %1). Their order and names come from your distribution's scripts in /etc/grub.d, so they are shown here and nowhere edited.").arg(root.cfgFile)
                  : qsTr("The boot entries could not be read: grub.cfg is missing, or only the administrator may read it. The settings still work.") }
        // grub.cfg is generated, not written by hand: this list is read-only, and the warning stays visible.
        Rectangle {
            Layout.fillWidth: true; color: t.surface2; border.width: 1; border.color: t.warn
            implicitHeight: warnRow.implicitHeight + 16
            RowLayout { id: warnRow; anchors.fill: parent; anchors.margins: 8; spacing: 8
                WarnBadge { Layout.alignment: Qt.AlignTop; strong: true
                    text: qsTr("A broken grub.cfg can stop the computer from booting. This list never writes to it; change the default entry on the General page instead.") }
                Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.text; font.pixelSize: 12
                    text: qsTr("<b>Read-only: modifying grub.cfg is unsafe.</b> GRUB regenerates that file from <code>/etc/default/grub</code> and the scripts in <code>/etc/grub.d</code>, so a hand edit is lost at the next kernel update — and a mistake in it can leave the computer unable to boot. Nothing on this tab writes to <code>grub.cfg</code>.") }
            }
        }
        RowLayout {
            visible: root.entries.length === 0
            AppButton { text: qsTr("Read with Administrator rights…"); onClicked: root.loadElevated()
                tip: qsTr("Reads grub.cfg with Administrator rights (polkit asks for your password once). Only a copy is read; the file is not changed. Starting the app with sudo works too.") }
            Item { Layout.fillWidth: true }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; color: t.surface; border.width: 1; border.color: t.border; clip: true
            ListView {
                id: lv; anchors.fill: parent; anchors.margins: 4; model: root.entries; clip: true; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: AppScrollBar { }
                delegate: ItemDelegate {
                    required property var modelData
                    width: lv.width - 8; height: 42; hoverEnabled: true
                    readonly property bool isDefault: root.isDefault(modelData.id)
                    background: Rectangle { color: parent.hovered ? t.surface2 : "transparent" }
                    contentItem: RowLayout {
                        spacing: 10
                        Item { Layout.preferredWidth: 14 + modelData.depth * 22 }
                        Label { text: modelData.submenu ? "▸" : "◆"; color: isDefault ? t.accent : t.muted2 }
                        Label { text: modelData.title; Layout.fillWidth: true; elide: Text.ElideRight; color: t.text }
                        Label { visible: isDefault; text: qsTr("default"); color: t.accent; font.pixelSize: 11 }
                        Label { text: modelData.id; color: t.muted2; font.family: t.mono; font.pixelSize: 11 }
                    }
                }
            }
        }
    }
}
