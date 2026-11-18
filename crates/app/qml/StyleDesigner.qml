import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Makes a "style": the nine-piece picture GRUB stretches around a box (selection bar, menu panel, progress track ...).
// Design one from a few controls, or cut one out of a picture. The result is added to the theme and assigned at once.
AppDialog {
    id: dlg
    property var backend
    property string uid: ""
    property string key: ""
    property string what: ""
    property string note: ""
    signal created(string pattern)
    title: qsTr("Style designer") + (what !== "" ? " · " + what : "")
    width: 560

    function openFor(itemUid, styleKey, label) { uid = itemUid; key = styleKey; what = label.replace("…", ""); note = ""; tabs.currentIndex = 0; open() }
    function spec() {
        return JSON.stringify({ key: dlg.key, fill: fillHex.text, fill2: grad.checked ? fill2Hex.text : "", opacity: parseInt(op.text) || 100,
                                radius: parseInt(rad.text) || 0, border_width: parseInt(bw.text) || 0, border: borderHex.text, border_opacity: parseInt(bop.text) || 100 })
    }
    function done(r) {
        if (r.indexOf("ERR:") === 0) { note = r.substring(4); return }
        created(r); close()
    }
    NativePick { id: colorPick; backend: dlg.backend; kind: "color"; title: qsTr("Choose a colour"); property var target: null
        onAccepted: (c) => { if (target) target.text = c } }
    NativePick { id: picPick; backend: dlg.backend; kind: "file"; title: qsTr("Choose a picture"); filter: "Pictures|*.png *.jpg *.jpeg"; property string path: ""
        onAccepted: (p) => { path = p; picName.text = p.split("/").pop() } }

    ColumnLayout {
        width: dlg.availableWidth; spacing: 10
        AppTabBar { id: tabs; Layout.alignment: Qt.AlignLeft
            AppTabButton { text: qsTr("Design"); width: implicitWidth }
            AppTabButton { text: qsTr("From a picture"); width: implicitWidth }
        }
        StackLayout {
            currentIndex: tabs.currentIndex; Layout.fillWidth: true
            // ---- design
            ColumnLayout {
                spacing: 10
                // live look (an approximation: GRUB stretches the real pieces)
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 84; color: t.bg; border.width: 1; border.color: t.border
                    Rectangle {
                        anchors.centerIn: parent; width: 280; height: 44
                        radius: Math.min(parseInt(rad.text) || 0, 22)
                        opacity: (parseInt(op.text) || 100) / 100
                        border.width: Math.min(parseInt(bw.text) || 0, 8); border.color: borderHex.text
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: fillHex.text }
                            GradientStop { position: 1.0; color: grad.checked ? fill2Hex.text : fillHex.text }
                        }
                        Label { anchors.centerIn: parent; text: qsTr("Preview"); color: "white"; font.bold: true }
                    }
                }
                GridLayout {
                    columns: 3; columnSpacing: 8; rowSpacing: 8; Layout.fillWidth: true
                    Label { text: qsTr("Fill"); color: t.muted }
                    AppField { id: fillHex; Layout.fillWidth: true; text: "#ff6b6b"; selectByMouse: true }
                    AppButton { text: qsTr("Pick…"); onClicked: { colorPick.target = fillHex; colorPick.current = fillHex.text; colorPick.open() } }
                    AppCheckBox { id: grad; Layout.columnSpan: 3; text: qsTr("Gradient"); tip: qsTr("Blend the fill into a second colour from top to bottom.") }
                    Label { text: qsTr("Second colour"); color: t.muted; visible: grad.checked }
                    AppField { id: fill2Hex; Layout.fillWidth: true; text: "#c0392b"; selectByMouse: true; visible: grad.checked }
                    AppButton { text: qsTr("Pick…"); visible: grad.checked; onClicked: { colorPick.target = fill2Hex; colorPick.current = fill2Hex.text; colorPick.open() } }
                    Label { text: qsTr("Opacity (%)"); color: t.muted }
                    AppStepper { id: op; Layout.fillWidth: true; text: "100"; minValue: 0; maxValue: 100; step: 5; bigStep: 25; validator: IntValidator { bottom: 0; top: 100 } }
                    Item { }
                    Label { text: qsTr("Corner radius (px)"); color: t.muted }
                    AppStepper { id: rad; Layout.fillWidth: true; text: "8"; minValue: 0; maxValue: 96; step: 1; bigStep: 4; validator: IntValidator { bottom: 0; top: 96 } }
                    Item { }
                    Label { text: qsTr("Border width (px)"); color: t.muted }
                    AppStepper { id: bw; Layout.fillWidth: true; text: "0"; minValue: 0; maxValue: 32; step: 1; bigStep: 4; validator: IntValidator { bottom: 0; top: 32 } }
                    Item { }
                    Label { text: qsTr("Border colour"); color: t.muted }
                    AppField { id: borderHex; Layout.fillWidth: true; text: "#ffffff"; selectByMouse: true }
                    AppButton { text: qsTr("Pick…"); onClicked: { colorPick.target = borderHex; colorPick.current = borderHex.text; colorPick.open() } }
                    Label { text: qsTr("Border opacity (%)"); color: t.muted }
                    AppStepper { id: bop; Layout.fillWidth: true; text: "100"; minValue: 0; maxValue: 100; step: 5; bigStep: 25; validator: IntValidator { bottom: 0; top: 100 } }
                    Item { }
                }
            }
            // ---- from a picture
            ColumnLayout {
                spacing: 10
                Label { Layout.fillWidth: true; wrapMode: Text.Wrap; color: t.muted; font.pixelSize: 12
                    text: qsTr("Choose any picture. It is cut into nine pieces: four fixed corners of the sizes below, and edges and a centre that GRUB stretches. Use this for artwork made in another program.") }
                RowLayout { spacing: 8
                    AppButton { text: qsTr("Choose picture…"); onClicked: picPick.open() }
                    Label { id: picName; text: qsTr("nothing chosen"); color: t.muted; elide: Text.ElideMiddle; Layout.fillWidth: true } }
                GridLayout { columns: 4; columnSpacing: 8; rowSpacing: 8
                    Label { text: qsTr("Left"); color: t.muted }   AppStepper { id: cl; implicitWidth: 100; text: "12"; minValue: 0; maxValue: 400; validator: IntValidator { bottom: 0; top: 400 } }
                    Label { text: qsTr("Top"); color: t.muted }    AppStepper { id: ct; implicitWidth: 100; text: "12"; minValue: 0; maxValue: 400; validator: IntValidator { bottom: 0; top: 400 } }
                    Label { text: qsTr("Right"); color: t.muted }  AppStepper { id: cr; implicitWidth: 100; text: "12"; minValue: 0; maxValue: 400; validator: IntValidator { bottom: 0; top: 400 } }
                    Label { text: qsTr("Bottom"); color: t.muted } AppStepper { id: cb; implicitWidth: 100; text: "12"; minValue: 0; maxValue: 400; validator: IntValidator { bottom: 0; top: 400 } }
                }
            }
        }
        Label { visible: dlg.note !== ""; text: dlg.note; color: t.danger; wrapMode: Text.Wrap; Layout.fillWidth: true }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Item { Layout.fillWidth: true }
            AppButton { text: qsTr("Cancel"); onClicked: dlg.close() }
            AppButton { highlighted: true; text: tabs.currentIndex === 0 ? qsTr("Create style") : qsTr("Cut into a style")
                enabled: tabs.currentIndex === 0 || picPick.path !== ""
                tip: qsTr("Adds the nine picture pieces to the theme and uses them for this item.")
                onClicked: tabs.currentIndex === 0
                    ? dlg.done(dlg.backend.call("designStyle", dlg.uid, dlg.spec()))
                    : dlg.done(dlg.backend.call("importStyle", dlg.uid, JSON.stringify({ key: dlg.key, path: picPick.path, l: parseInt(cl.text) || 0, t: parseInt(ct.text) || 0, r: parseInt(cr.text) || 0, b: parseInt(cb.text) || 0 }))) }
        }
    }
}
