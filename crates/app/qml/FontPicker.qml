import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Adds a font to the theme: any font installed on this computer, or a font file. GRUB can only use its own bitmap format
// (.pf2), so the chosen font is converted at the chosen size; no GRUB tools are needed.
AppDialog {
    id: dlg
    property var backend
    property var fonts: []
    property string query: ""
    property int pick: -1
    property string note: ""
    signal added(string name)
    title: qsTr("Add a font")
    width: 600; height: Math.min(640, (parent ? parent.height : 700) - 40)

    readonly property var shown: { var q = query.toLowerCase(); return q === "" ? fonts : fonts.filter(function(f) { return (f.family + " " + f.style).toLowerCase().indexOf(q) >= 0 }) }
    function openNow() { note = ""; pick = -1; if (fonts.length === 0) { try { fonts = JSON.parse(backend.call("sysFonts", "", "")) } catch (e) { fonts = [] } } open() }
    function finish(r) { if (r.indexOf("ERR:") === 0) { note = r.substring(4); return } added(r); close() }
    function weightOf(s) { return /bold|black|heavy/i.test(s) ? Font.Bold : Font.Normal }

    NativePick { id: fileFont; backend: dlg.backend; kind: "file"; title: qsTr("Choose a font file"); filter: "Fonts|*.ttf *.otf"
        onAccepted: (p) => dlg.finish(dlg.backend.call("addFont", p, sizeBox.text)) }

    ColumnLayout {
        anchors.fill: parent; spacing: 8
        Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.muted; font.pixelSize: 12
            text: qsTr("Pick a font installed on this computer. GRUB draws text from small bitmap fonts, so the font is converted for one size. Add another size later if you need it.") }
        RowLayout { spacing: 8
            AppField { Layout.fillWidth: true; placeholderText: qsTr("Search %n installed font(s)…", "", dlg.fonts.length); onTextChanged: dlg.query = text; selectByMouse: true }
            Label { text: qsTr("Size (px)"); color: t.muted }
            AppStepper { id: sizeBox; implicitWidth: 96; text: "24"; minValue: 8; maxValue: 96; step: 1; bigStep: 4; validator: IntValidator { bottom: 8; top: 96 } }
        }
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; radius: 10; color: t.bg; border.width: 1; border.color: t.border; clip: true
            ListView {
                id: lv; anchors.fill: parent; anchors.margins: 4; model: dlg.shown; clip: true; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { }
                delegate: ItemDelegate {
                    required property var modelData
                    required property int index
                    width: lv.width - 10; height: 44; highlighted: dlg.pick === index
                    onClicked: dlg.pick = index
                    onDoubleClicked: { dlg.pick = index; addBtn.clicked() }
                    background: Rectangle { radius: 8; color: highlighted ? t.surface3 : (hovered ? t.surface2 : "transparent") }
                    contentItem: RowLayout {
                        spacing: 10
                        Label { text: modelData.family + (modelData.style !== "Regular" ? " " + modelData.style : ""); Layout.preferredWidth: 220; elide: Text.ElideRight; color: t.muted; font.pixelSize: 12 }
                        Label { text: "The quick brown fox 0123"; Layout.fillWidth: true; elide: Text.ElideRight; color: t.text; font.pixelSize: 18
                            font.family: modelData.family; font.weight: dlg.weightOf(modelData.style); font.italic: /italic|oblique/i.test(modelData.style) }
                    }
                }
                Label { anchors.centerIn: parent; visible: dlg.shown.length === 0; color: t.muted; text: dlg.fonts.length === 0 ? qsTr("No installed fonts were found.") : qsTr("No font matches your search.") }
            }
        }
        Label { visible: dlg.note !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.danger; text: dlg.note }
        RowLayout { spacing: 8
            AppButton { text: qsTr("From a file…"); tip: qsTr("Use a .ttf or .otf file that is not installed."); onClicked: fileFont.open() }
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Cancel"); onClicked: dlg.close() }
            AppButton { id: addBtn; highlighted: true; text: qsTr("Add to theme"); enabled: dlg.pick >= 0 && dlg.pick < dlg.shown.length
                tip: qsTr("Converts the selected font to a GRUB font at this size and adds it to the theme.")
                onClicked: dlg.finish(dlg.backend.call("addSysFont", JSON.stringify(dlg.shown[dlg.pick]), sizeBox.text)) }
        }
    }
}
