import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

ScrollView {
    id: root
    readonly property var t: Tokens {}
    property var backend
    property var info: ({ mode: "theme", title: "", geometry: [], fields: [] })
    property int rev: backend ? backend.rev : 0
    onRevChanged: reload()
    Component.onCompleted: reload()
    function reload() { info = JSON.parse(backend.call("inspector", "", "")) }
    property string target: ""      // field being edited by a shared dialog
    property string note: ""
    contentWidth: availableWidth

    function set(key, v) { backend.call("setField", key, v) }

    ColorDialog { id: colorDlg; onAccepted: { if (root.target === "__rect") backend.call("rectColor", selectedColor.toString(), ""); else root.set(root.target, selectedColor.toString().substring(0, 7)) } }
    FileDialog { id: imgDlg; nameFilters: ["Images (*.png *.jpg *.jpeg)"]
        onAccepted: { var r = backend.call("addAsset", selectedFile.toString(), ""); if (r.indexOf("ERR:") === 0) root.note = r.substring(4); else root.set(root.target, r) } }
    FileDialog { id: fontDlg; nameFilters: ["Fonts (*.ttf *.otf)"]
        onAccepted: sizeDlg.open() }
    Dialog { id: sizeDlg; title: qsTr("Font size"); standardButtons: Dialog.Ok | Dialog.Cancel; modal: true; anchors.centerIn: Overlay.overlay
        SpinBox { id: sizeBox; from: 8; to: 160; value: 24; editable: true }
        onAccepted: { var r = backend.call("addFont", fontDlg.selectedFile.toString(), sizeBox.value.toString()); if (r.indexOf("ERR:") === 0) root.note = r.substring(4); else { root.note = qsTr("Font added: %1").arg(r); if (root.target) root.set(root.target, r) } } }

    ColumnLayout {
        width: root.availableWidth; spacing: 6
        Label { text: root.info.title.toUpperCase(); font.bold: true; font.pixelSize: 11; font.letterSpacing: 0.8; color: t.muted; Layout.leftMargin: 14; Layout.topMargin: 14; Layout.bottomMargin: 6 }

        // position and size
        GridLayout {
            visible: root.info.geometry.length > 0; columns: 2; Layout.margins: 8; columnSpacing: 6; rowSpacing: 4; Layout.fillWidth: true
            Repeater {
                model: root.info.geometry
                delegate: RowLayout { Layout.fillWidth: true; spacing: 4
                    Label { text: modelData.label; Layout.preferredWidth: 42; color: t.muted }
                    AppField { Layout.fillWidth: true; text: modelData.value; selectByMouse: true; onEditingFinished: root.set(modelData.key, text) }
                }
            }
        }
        RowLayout { visible: root.info.geometry.length > 0; Layout.margins: 8; spacing: 6
            AppButton { text: qsTr("Center X"); onClicked: backend.call("center", "x", "") }
            AppButton { text: qsTr("Center Y"); onClicked: backend.call("center", "y", "") }
        }
        Label { visible: root.info.geometry.length > 0; Layout.margins: 8; Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.muted2; font.pixelSize: 11
            text: qsTr("Values accept pixels or GRUB expressions like 50%-120. Dragging keeps % units.") }

        // style fields
        Repeater {
            model: root.info.fields
            delegate: RowLayout {
                id: row
                Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 8; spacing: 6
                Label { text: modelData.label; Layout.preferredWidth: 96; elide: Text.ElideRight; color: t.muted }
                Loader {
                    Layout.fillWidth: true
                    sourceComponent: {
                        switch (modelData.kind) {
                        case "color": case "rectcolor": return colorField
                        case "bool": return boolField
                        case "select": return comboField
                        case "file": case "style": case "font": return comboField
                        default: return textField
                        }
                    }
                    property var f: modelData
                }
                AppIconButton { visible: modelData.kind === "file"; text: "⬆"; onClicked: { root.target = modelData.key; imgDlg.open() } ToolTip.text: qsTr("Upload image"); ToolTip.visible: hovered }
                AppIconButton { visible: modelData.kind === "font"; text: "＋"; onClicked: { root.target = modelData.key; fontDlg.open() } ToolTip.text: qsTr("Add a .ttf/.otf font (converted to PF2)"); ToolTip.visible: hovered }
                AppIconButton { visible: modelData.kind === "style"; text: "＋"; onClicked: { root.target = modelData.key; styleDlg.open() } ToolTip.text: qsTr("Create a solid-colour style"); ToolTip.visible: hovered }
            }
        }

        // theme-wide extras
        Label { visible: root.info.mode === "theme"; text: qsTr("FONTS"); font.bold: true; font.pixelSize: 11; font.letterSpacing: 0.8; color: t.muted; Layout.leftMargin: 14; Layout.topMargin: 14; Layout.bottomMargin: 6 }
        AppButton { visible: root.info.mode === "theme"; text: qsTr("Add font (.ttf / .otf)…"); Layout.leftMargin: 8; onClicked: { root.target = ""; fontDlg.open() } }
        Repeater { model: root.info.mode === "theme" ? root.info.fonts : []; delegate: Label { text: modelData; Layout.leftMargin: 14; color: t.muted; font.pixelSize: 11 } }
        Label { visible: root.info.mode === "theme"; text: qsTr("ASSETS (%1)").arg(root.info.assets ? root.info.assets.length : 0); font.bold: true; font.pixelSize: 11; font.letterSpacing: 0.8; color: t.muted; Layout.leftMargin: 14; Layout.topMargin: 14; Layout.bottomMargin: 6 }
        Repeater {
            model: root.info.mode === "theme" ? root.info.assets : []
            delegate: RowLayout { Layout.leftMargin: 10; Layout.rightMargin: 8; Layout.fillWidth: true
                Label { text: modelData; Layout.fillWidth: true; elide: Text.ElideMiddle; font.pixelSize: 11 }
                AppIconButton { text: "✕"; onClicked: backend.call("removeAsset", modelData, "") } }
        }
        Label { visible: root.info.mode === "theme" && root.info.missing && root.info.missing.length > 0; Layout.margins: 14; Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.warn
            text: qsTr("Missing files referenced by theme.txt: %1").arg(root.info.missing ? root.info.missing.join(", ") : "") }
        Label { visible: root.note !== ""; text: root.note; Layout.margins: 14; Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.warn }
    }

    Dialog { id: styleDlg; title: qsTr("Solid-colour style"); standardButtons: Dialog.Ok | Dialog.Cancel; modal: true; anchors.centerIn: Overlay.overlay
        AppField { id: styleColor; text: "#2f7fd6"; placeholderText: "#rrggbb" }
        onAccepted: backend.call("solidStyle", root.target, styleColor.text) }

    Component { id: textField
        AppField { text: f.value; selectByMouse: true; onEditingFinished: root.set(f.key, text) } }
    Component { id: boolField
        CheckBox { checked: f.value === "true"; onToggled: root.set(f.key, checked ? "true" : "false") } }
    Component { id: colorField
        RowLayout { spacing: 6
            Rectangle { width: 32; height: 32; radius: 8; border.color: t.border2; color: /^#[0-9a-fA-F]{3,8}$/.test(f.value) ? f.value : "#ffffff"
                MouseArea { anchors.fill: parent; onClicked: { root.target = f.key; colorDlg.selectedColor = parent.color; colorDlg.open() } } }
            AppField { Layout.fillWidth: true; visible: f.kind === "color"; text: f.value; selectByMouse: true; onEditingFinished: root.set(f.key, text) }
        } }
    Component { id: comboField
        ComboBox {
            editable: f.kind === "font"
            model: f.kind === "file" || f.kind === "style" ? [""].concat(f.options) : (f.options.indexOf(f.value) < 0 && f.value !== "" ? [f.value].concat(f.options) : f.options)
            currentIndex: Math.max(0, find(f.value))
            onActivated: root.set(f.key, currentText)
            onAccepted: if (editable) root.set(f.key, editText)
        } }
}
