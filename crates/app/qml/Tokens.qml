import QtQuick
import "Theme.js" as Theme

// Design tokens, modelled on the GrubStudio look: near-black surfaces, hairline borders, one orange accent.
// Use as:  readonly property var t: Tokens {}
QtObject {
    id: tk
    readonly property color bg:          "#09090b"
    readonly property color surface:     "#111113"
    readonly property color surface2:    "#18181b"
    readonly property color surface3:    "#222226"
    readonly property color border:      "#27272a"
    readonly property color border2:     "#3f3f46"
    readonly property color text:        "#fafafa"
    readonly property color muted:       "#a1a1aa"
    readonly property color muted2:      "#71717a"
    // The accent is user-selectable (Appearance dialog); everything derived from it follows.
    property color accent:      "#ff9248"
    property color accentHover: Qt.lighter(accent, 1.15)
    property color accentDown:  Qt.darker(accent, 1.15)
    property color accentSoft:  Qt.rgba(accent.r, accent.g, accent.b, 0.14)
    property color accentFg:    (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6 ? "#1a0e04" : "#ffffff"
    function apply(c) { accent = c }
    Component.onCompleted: Theme.register(tk)
    Component.onDestruction: Theme.unregister(tk)
    readonly property color ok:          "#5ccf8b"
    readonly property color warn:        "#e0a030"
    readonly property color danger:      "#ff6b6b"
    readonly property string mono:       "JetBrains Mono, Fira Code, DejaVu Sans Mono, monospace"
}
