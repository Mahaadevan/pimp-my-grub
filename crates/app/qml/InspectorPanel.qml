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
    // The Repeaters are keyed by these lists, which only change when the set of fields changes, so editing a value
    // updates the existing controls in place instead of rebuilding them (keeps focus and a held arrow button alive).
    property var fieldKeys: []
    property var geoKeys: []
    function reload() {
        var n = JSON.parse(backend.call("inspector", "", ""))
        var fk = n.fields.map(function(f) { return f.key + ":" + f.kind })
        var gk = n.geometry.map(function(g) { return g.key })
        info = n
        if (fk.join("|") !== fieldKeys.join("|")) fieldKeys = fk
        if (gk.join("|") !== geoKeys.join("|")) geoKeys = gk
    }
    property string target: ""      // field being edited by a shared dialog
    property string note: ""
    contentWidth: availableWidth

    function set(key, v) { backend.call("setField", key, v) }

    ColorDialog { id: colorDlg; onAccepted: { if (root.target === "__rect") backend.call("rectColor", selectedColor.toString(), ""); else root.set(root.target, selectedColor.toString().substring(0, 7)) } }
    FileDialog { id: imgDlg; nameFilters: ["Images (*.png *.jpg *.jpeg)"]
        onAccepted: { var r = backend.call("addAsset", selectedFile.toString(), ""); if (r.indexOf("ERR:") === 0) root.note = r.substring(4); else root.set(root.target, r) } }
    FileDialog { id: fontDlg; nameFilters: ["Fonts (*.ttf *.otf)"]
        onAccepted: sizeDlg.open() }
    AppDialog { id: sizeDlg; title: qsTr("Font size"); standardButtons: Dialog.Ok | Dialog.Cancel
        AppStepper { id: sizeBox; implicitWidth: 120; text: "24"; minValue: 8; maxValue: 160; step: 1; bigStep: 4; inputMethodHints: Qt.ImhDigitsOnly; validator: IntValidator { bottom: 8; top: 160 } }
        onAccepted: { var r = backend.call("addFont", fontDlg.selectedFile.toString(), Math.max(8, Math.min(160, parseInt(sizeBox.text) || 24)).toString()); if (r.indexOf("ERR:") === 0) root.note = r.substring(4); else { root.note = qsTr("Font added: %1").arg(r); if (root.target) root.set(root.target, r) } } }

    ColumnLayout {
        width: root.availableWidth; spacing: 6
        Label { text: root.info.title.toUpperCase(); font.bold: true; font.pixelSize: 11; font.letterSpacing: 0.8; color: t.muted; Layout.leftMargin: 14; Layout.topMargin: 14; Layout.bottomMargin: 6 }

        // position and size
        GridLayout {
            visible: root.info.geometry.length > 0; columns: 2; Layout.margins: 8; columnSpacing: 6; rowSpacing: 4; Layout.fillWidth: true
            Repeater {
                model: root.geoKeys
                delegate: RowLayout { Layout.fillWidth: true; spacing: 4
                    property var g: root.info.geometry[index] || ({ key: "", label: "", value: "" })
                    Label { text: g.label; Layout.preferredWidth: 42; color: t.muted }
                    AppStepper { Layout.fillWidth: true; text: g.value; minValue: 0; maxValue: 20000
                        onEditingFinished: root.set(g.key, text); onStepped: (v) => root.set(g.key, v) }
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
            model: root.fieldKeys
            delegate: RowLayout {
                id: row
                property var fd: root.info.fields[index] || ({ key: "", label: "", kind: "str", value: "", options: [] })
                Layout.fillWidth: true; Layout.leftMargin: 8; Layout.rightMargin: 8; spacing: 6
                Label { text: row.fd.label; Layout.preferredWidth: 96; elide: Text.ElideRight; color: t.muted }
                Loader {
                    Layout.fillWidth: true
                    sourceComponent: {
                        switch (row.fd.kind) {
                        case "color": case "rectcolor": return colorField
                        case "bool": return boolField
                        case "select": return comboField
                        case "file": case "style": case "font": return comboField
                        case "expr": return numberField
                        default: return textField
                        }
                    }
                    property var f: row.fd
                }
                AppIconButton { visible: row.fd.kind === "file"; text: "⬆"; onClicked: { root.target = row.fd.key; imgDlg.open() } ToolTip.text: qsTr("Upload image"); ToolTip.visible: hovered }
                AppIconButton { visible: row.fd.kind === "font"; text: "＋"; onClicked: { root.target = row.fd.key; fontDlg.open() } ToolTip.text: qsTr("Add a .ttf/.otf font (converted to PF2)"); ToolTip.visible: hovered }
                AppIconButton { visible: row.fd.kind === "style"; text: "＋"; onClicked: { root.target = row.fd.key; styleDlg.open() } ToolTip.text: qsTr("Create a solid-colour style"); ToolTip.visible: hovered }
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

    AppDialog { id: styleDlg; title: qsTr("Solid-colour style"); standardButtons: Dialog.Ok | Dialog.Cancel
        AppField { id: styleColor; text: "#2f7fd6"; placeholderText: "#rrggbb" }
        onAccepted: backend.call("solidStyle", root.target, styleColor.text) }

    Component { id: textField
        AppField { text: f.value; selectByMouse: true; onEditingFinished: root.set(f.key, text) } }
    Component { id: numberField
        AppStepper { text: f.value; minValue: f.key === "start_angle" ? -360 : 0; maxValue: f.key === "start_angle" ? 360 : 20000
            onEditingFinished: root.set(f.key, text); onStepped: (v) => root.set(f.key, v) } }
    Component { id: boolField
        AppCheckBox { checked: f.value === "true"; onToggled: root.set(f.key, checked ? "true" : "false") } }
    Component { id: colorField
        RowLayout { spacing: 6
            Rectangle { width: 32; height: 32; radius: 8; border.color: t.border2; color: /^#[0-9a-fA-F]{3,8}$/.test(f.value) ? f.value : "#ffffff"
                MouseArea { anchors.fill: parent; onClicked: { root.target = f.key; colorDlg.selectedColor = parent.color; colorDlg.open() } } }
            AppField { Layout.fillWidth: true; visible: f.kind === "color"; text: f.value; selectByMouse: true; onEditingFinished: root.set(f.key, text) }
        } }
    Component { id: comboField
        AppComboBox {
            model: f.kind === "file" || f.kind === "style" ? [""].concat(f.options) : (f.options.indexOf(f.value) < 0 && f.value !== "" ? [f.value].concat(f.options) : f.options)
            currentIndex: Math.max(0, find(f.value))
            onActivated: root.set(f.key, currentText)
        } }
}
