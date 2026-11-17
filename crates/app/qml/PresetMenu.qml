import QtQuick
import QtQuick.Controls

// A menu listing the ready-made versions of one kind of item (menu, label, progress bar ...).
Menu {
    id: m
    property var backend
    property string kind: ""
    property string plainText: ""            // first entry: add the item with its standard settings
    property var presets: []
    signal plain()
    signal chosen(string id)
    readonly property var all: (plainText !== "" ? [{ id: "__plain", label: plainText, tip: qsTr("Add it with the standard settings.") }] : []).concat(presets)
    function load() { try { presets = JSON.parse(backend.call("presets", "", ""))[kind] || [] } catch (e) { presets = [] } }
    Component.onCompleted: load()
    onAboutToShow: load()
    Instantiator {
        model: m.all
        delegate: AppMenuItem {
            required property var modelData
            text: modelData.label
            ToolTip.visible: hovered; ToolTip.delay: 250; ToolTip.timeout: 12000; ToolTip.text: modelData.tip
            onTriggered: modelData.id === "__plain" ? m.plain() : m.chosen(modelData.id)
        }
        onObjectAdded: (i, o) => m.insertItem(i, o)
        onObjectRemoved: (i, o) => m.removeItem(o)
    }
}
