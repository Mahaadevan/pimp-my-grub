import QtQuick
import QtQuick.Controls
import QtQuick.Window
import dev.pimpmygrub

// Full-screen simulation of the GRUB menu. It shows the theme as GRUB would, with the boot entries and timeout of THIS
// computer when they can be read, a running countdown, and keyboard control like the real thing. Nothing is booted.
Window {
    id: w
    property var backend
    property var entries: []                 // [{title, class}]
    property int sel: 0
    property int total: 5
    property int secs: 5
    property bool counting: true
    property string banner: ""
    property string source: ""
    property bool help: true
    property var restore: ({ timeout: 5, total: 5 })
    readonly property int count: entries.length > 0 ? entries.length : 5
    visibility: Window.Hidden
    color: "black"
    title: qsTr("Pimp my GRUB: live preview")

    function call(c, a) { return backend.call(c, a === undefined ? "" : String(a), "") }
    function start() {
        var h = ({})
        try { restore = { timeout: JSON.parse(call("status")).timeout, total: restore.total } } catch (e) { }
        try { h = JSON.parse(call("hostSync")) } catch (e) { }
        entries = (h.found && h.entries && h.entries.length) ? h.entries : []
        source = h.found ? qsTr("Boot entries read from this computer (%1)").arg(h.file) : qsTr("Sample entries: this computer's grub.cfg could not be read")
        total = (h.found && h.timeout > 0) ? h.timeout : 5
        secs = total
        sel = (h.found && h.default < entries.length) ? h.default : 0
        counting = true; banner = ""; help = true
        call("entries", JSON.stringify(entries)); call("timeoutTotal", total); call("timeout", secs); call("menuSel", sel); call("timeoutVisible", "1")
        visibility = Window.FullScreen
        scene.forceActiveFocus(); push()
        helpTimer.restart()
    }
    function stop() {
        visibility = Window.Hidden
        call("entries", "[]"); call("timeoutTotal", restore.total); call("timeout", restore.timeout); call("menuSel", 0); call("timeoutVisible", "1")
    }
    function push() { call("menuSel", sel); call("timeout", secs); call("timeoutVisible", counting ? "1" : "0"); scene.input(6, 0, 0, 0, 0, 0) }
    function stopCounting() { if (counting) { counting = false; push() } }
    function bootSelected() {
        counting = false
        var t = entries.length > 0 ? entries[sel].title : ["Ubuntu", "Advanced options for Ubuntu", "Memory test (memtest86+)", "Windows Boot Manager", "UEFI Firmware Settings"][sel]
        banner = qsTr("Booting “%1” …").arg(t) + "\n" + qsTr("(Preview only: nothing is started.)")
        push(); bannerTimer.restart()
    }
    onClosing: (c) => { c.accepted = false; stop() }

    SceneItem {
        id: scene
        anchors.fill: parent; live: true; focus: true
        Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Escape) { if (w.banner !== "") { w.banner = ""; w.push() } else w.stop(); e.accepted = true; return }
            if (w.banner !== "") { e.accepted = true; return }
            w.help = false
            if (e.key === Qt.Key_Up) { w.stopCounting(); if (w.sel > 0) w.sel--; w.push() }
            else if (e.key === Qt.Key_Down) { w.stopCounting(); if (w.sel < w.count - 1) w.sel++; w.push() }
            else if (e.key === Qt.Key_Home) { w.stopCounting(); w.sel = 0; w.push() }
            else if (e.key === Qt.Key_End) { w.stopCounting(); w.sel = w.count - 1; w.push() }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { w.bootSelected() }
            else if (e.key === Qt.Key_E) { w.stopCounting(); w.banner = qsTr("Edit the boot commands\n(not available in the preview)"); bannerTimer.restart() }
            else if (e.key === Qt.Key_C) { w.stopCounting(); w.banner = qsTr("grub> _\n(The GRUB command line is not available in the preview)"); bannerTimer.restart() }
            else if (e.key === Qt.Key_F1 || e.key === Qt.Key_Question) { w.help = true; helpTimer.restart() }
            else w.stopCounting()
            e.accepted = true
        }
        MouseArea { anchors.fill: parent; onClicked: scene.forceActiveFocus() }
    }

    // like GRUB, the countdown ticks once a second until a key is pressed
    Timer { interval: 1000; running: w.visible && w.counting && w.banner === ""; repeat: true
        onTriggered: { if (w.secs > 0) w.secs--; w.push(); if (w.secs <= 0) w.bootSelected() } }
    Timer { id: bannerTimer; interval: 3500; onTriggered: { if (w.banner.indexOf("Booting") >= 0 || w.banner !== "") { w.banner = ""; w.push() } } }
    Timer { id: helpTimer; interval: 7000; onTriggered: w.help = false }

    Rectangle {
        visible: w.banner !== ""; anchors.centerIn: parent; width: Math.min(parent.width - 80, 640); height: msg.implicitHeight + 56
        radius: 14; color: "#e60a0c10"; border.width: 1; border.color: "#44ffffff"
        Text { id: msg; anchors.centerIn: parent; width: parent.width - 48; text: w.banner; color: "white"; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap }
    }
    Rectangle {
        visible: w.help; opacity: w.help ? 1 : 0; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 18
        width: Math.min(parent.width - 40, hint.implicitWidth + 36); height: hint.implicitHeight + 20; radius: 12; color: "#d90a0c10"; border.width: 1; border.color: "#33ffffff"
        Behavior on opacity { NumberAnimation { duration: 250 } }
        Text { id: hint; anchors.centerIn: parent; color: "#d6d9df"; font.pixelSize: 13; horizontalAlignment: Text.AlignHCenter
            text: qsTr("LIVE PREVIEW · ↑ ↓ choose · Enter boots (simulated) · e / c as in GRUB · F1 help · Esc leaves") + "\n" + w.source }
    }
}
