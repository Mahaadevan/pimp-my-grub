import QtQuick

// Design tokens, modelled on the GrubStudio look: near-black surfaces, hairline borders, one orange accent.
// Use as:  readonly property var t: Tokens {}
QtObject {
    readonly property color bg:          "#09090b"
    readonly property color surface:     "#111113"
    readonly property color surface2:    "#18181b"
    readonly property color surface3:    "#222226"
    readonly property color border:      "#27272a"
    readonly property color border2:     "#3f3f46"
    readonly property color text:        "#fafafa"
    readonly property color muted:       "#a1a1aa"
    readonly property color muted2:      "#71717a"
    readonly property color accent:      "#ff9248"
    readonly property color accentHover: "#ffa566"
    readonly property color accentDown:  "#e87d33"
    readonly property color accentSoft:  Qt.rgba(1, 0.573, 0.282, 0.14)
    readonly property color accentFg:    "#1a0e04"
    readonly property color ok:          "#5ccf8b"
    readonly property color warn:        "#e0a030"
    readonly property color danger:      "#ff6b6b"
    readonly property string mono:       "JetBrains Mono, Fira Code, DejaVu Sans Mono, monospace"
}
