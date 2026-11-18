import QtQuick
import QtQuick.Controls

// The right-click menu of the editor (canvas and layers list): edit, arrange, align, group, lock, create styles, add things.
AppMenu {
    id: m
    property var backend
    property var sel: null                   // the selected layer row {uid, type, locked, hidden, ...} or null
    property bool canPaste: false
    readonly property string uid: sel ? String(sel.uid) : ""
    readonly property bool isGroup: sel ? (sel.type === "canvas" || sel.type === "vbox" || sel.type === "hbox") : false
    signal edited()
    signal styleRequested(string key, string title)
    signal presetRequested(string kind, string id)
    signal plainRequested(string kind)

    function openAt(parentItem, x, y) { refresh(); popup(parentItem, x, y) }
    function refresh() {
        var rows = []
        try { rows = JSON.parse(backend.call("layers", "", "")) } catch (e) { }
        sel = null
        for (var i = 0; i < rows.length; i++) if (rows[i].selected) sel = rows[i]
        canPaste = backend.call("hasClipboard", "", "") === "1"
    }
    function run(cmd, a, b) { backend.call(cmd, a, b); edited() }

    AppMenuItem { text: qsTr("Cut"); enabled: !!m.sel; onTriggered: m.run("cut", m.uid, "") }
    AppMenuItem { text: qsTr("Copy"); enabled: !!m.sel; onTriggered: backend.call("copy", m.uid, "") }
    AppMenuItem { text: qsTr("Paste"); enabled: m.canPaste; onTriggered: m.run("paste", "", "") }
    AppMenuItem { text: qsTr("Duplicate"); enabled: !!m.sel; onTriggered: m.run("duplicate", "", "") }
    AppMenuItem { text: qsTr("Delete"); enabled: !!m.sel; onTriggered: m.run("remove", "", "") }
    AppMenuSeparator { }
    AppMenu {
        title: qsTr("Arrange"); enabled: !!m.sel
        AppMenuItem { text: qsTr("Bring to front"); onTriggered: m.run("front", m.uid, "") }
        AppMenuItem { text: qsTr("Bring forward"); onTriggered: m.run("reorder", "1", "") }
        AppMenuItem { text: qsTr("Send backward"); onTriggered: m.run("reorder", "-1", "") }
        AppMenuItem { text: qsTr("Send to back"); onTriggered: m.run("back", m.uid, "") }
    }
    AppMenu {
        title: qsTr("Align to its container"); enabled: !!m.sel
        AppMenuItem { text: qsTr("Left"); onTriggered: m.run("align", m.uid, "left") }
        AppMenuItem { text: qsTr("Center horizontally"); onTriggered: m.run("align", m.uid, "hcenter") }
        AppMenuItem { text: qsTr("Right"); onTriggered: m.run("align", m.uid, "right") }
        AppMenuSeparator { }
        AppMenuItem { text: qsTr("Top"); onTriggered: m.run("align", m.uid, "top") }
        AppMenuItem { text: qsTr("Middle"); onTriggered: m.run("align", m.uid, "vcenter") }
        AppMenuItem { text: qsTr("Bottom"); onTriggered: m.run("align", m.uid, "bottom") }
    }
    AppMenuItem { text: qsTr("Group"); enabled: !!m.sel && !m.isGroup; onTriggered: m.run("group", m.uid, "") }
    AppMenuItem { text: qsTr("Ungroup"); enabled: m.isGroup; onTriggered: m.run("ungroup", m.uid, "") }
    AppMenuItem { text: m.sel && m.sel.locked ? qsTr("Unlock") : qsTr("Lock position"); enabled: !!m.sel; onTriggered: m.run("toggle", m.uid, "locked") }
    AppMenuItem { text: m.sel && m.sel.hidden ? qsTr("Show") : qsTr("Hide"); enabled: !!m.sel; onTriggered: m.run("toggle", m.uid, "hidden") }
    AppMenuSeparator { }
    AppMenu {
        title: qsTr("Create a style (box look)"); enabled: !!m.sel && (m.sel.type === "boot_menu" || m.sel.type === "progress_bar")
        AppMenuItem { visible: !!m.sel && m.sel.type === "boot_menu"; height: visible ? implicitHeight : 0; text: qsTr("Selected entry bar…"); onTriggered: m.styleRequested("selected_item_pixmap_style", text) }
        AppMenuItem { visible: !!m.sel && m.sel.type === "boot_menu"; height: visible ? implicitHeight : 0; text: qsTr("Every entry row…"); onTriggered: m.styleRequested("item_pixmap_style", text) }
        AppMenuItem { visible: !!m.sel && m.sel.type === "boot_menu"; height: visible ? implicitHeight : 0; text: qsTr("Menu panel…"); onTriggered: m.styleRequested("menu_pixmap_style", text) }
        AppMenuItem { visible: !!m.sel && m.sel.type === "boot_menu"; height: visible ? implicitHeight : 0; text: qsTr("Scrollbar track…"); onTriggered: m.styleRequested("scrollbar_frame", text) }
        AppMenuItem { visible: !!m.sel && m.sel.type === "boot_menu"; height: visible ? implicitHeight : 0; text: qsTr("Scrollbar thumb…"); onTriggered: m.styleRequested("scrollbar_thumb", text) }
        AppMenuItem { visible: !!m.sel && m.sel.type === "progress_bar"; height: visible ? implicitHeight : 0; text: qsTr("Bar track…"); onTriggered: m.styleRequested("bar_style", text) }
        AppMenuItem { visible: !!m.sel && m.sel.type === "progress_bar"; height: visible ? implicitHeight : 0; text: qsTr("Bar fill…"); onTriggered: m.styleRequested("highlight_style", text) }
    }
    AppMenuSeparator { }
    AppMenu {
        title: qsTr("Add")
        PresetMenu { title: qsTr("Menu"); backend: m.backend; kind: "boot_menu"; plainText: qsTr("Standard menu"); onPlain: m.plainRequested("boot_menu"); onChosen: (id) => m.presetRequested("boot_menu", id) }
        PresetMenu { title: qsTr("Label"); backend: m.backend; kind: "label"; plainText: qsTr("Standard label"); onPlain: m.plainRequested("label"); onChosen: (id) => m.presetRequested("label", id) }
        PresetMenu { title: qsTr("Rectangle"); backend: m.backend; kind: "rectangle"; plainText: qsTr("Plain colour rectangle"); onPlain: m.plainRequested("rect"); onChosen: (id) => m.presetRequested("rectangle", id) }
        PresetMenu { title: qsTr("Progress bar"); backend: m.backend; kind: "progress_bar"; plainText: ""; onChosen: (id) => m.presetRequested("progress_bar", id) }
        PresetMenu { title: qsTr("Circular progress"); backend: m.backend; kind: "circular_progress"; plainText: ""; onChosen: (id) => m.presetRequested("circular_progress", id) }
        PresetMenu { title: qsTr("Group"); backend: m.backend; kind: "canvas"; plainText: ""; onChosen: (id) => m.presetRequested("canvas", id) }
        AppMenuSeparator { }
        AppMenuItem { text: qsTr("Image"); onTriggered: m.plainRequested("image") }
    }
}
