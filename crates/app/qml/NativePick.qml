import QtQuick
import QtQuick.Dialogs

// Opens the system's own chooser (zenity / kdialog: the same dialog other programs on the desktop show) for a file,
// a folder or a colour, and falls back to Qt's built-in dialog only when no system chooser can be started.
QtObject {
    id: np
    property var backend
    property string kind: "file"        // "file" | "dir" | "color"
    property string title: ""
    property string filter: ""          // e.g. "Images|*.png *.jpg"
    property string current: ""         // colour: the colour to start from
    readonly property string token: "p" + Math.floor(Math.random() * 1e9)
    signal accepted(string value)       // a file/folder path (or file:// URL from the fallback), or "#rrggbb"

    function open() {
        var r = backend.call("pick", kind + "\u0001" + title + "\u0001" + filter + "\u0001" + current, token)
        if (r !== "native") fallback()
    }
    function fallback() {
        if (kind === "dir") _dir.open()
        else if (kind === "color") { _col.selectedColor = current !== "" ? current : "#ff9248"; _col.open() }
        else _file.open()
    }
    property var _link: Connections {
        target: np.backend
        function onPickedChanged() {
            var p = np.backend.picked.split("\u0001")
            if (p.length < 3 || p[1] !== np.token) return
            if (p[2] === "!fallback") np.fallback()
            else if (p[2] !== "") np.accepted(p[2])
        }
    }
    property var _file: FileDialog {
        title: np.title
        nameFilters: np.filter === "" ? [] : [np.filter.split("|")[0] + " (" + np.filter.split("|")[1] + ")"]
        onAccepted: np.accepted(selectedFile.toString())
    }
    property var _dir: FolderDialog { title: np.title; onAccepted: np.accepted(selectedFolder.toString()) }
    property var _col: ColorDialog { title: np.title; onAccepted: np.accepted(selectedColor.toString().substring(0, 7)) }
}
