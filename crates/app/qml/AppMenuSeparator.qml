import QtQuick
import QtQuick.Controls

MenuSeparator {
    readonly property var t: Tokens {}
    topPadding: 4; bottomPadding: 4; leftPadding: 10; rightPadding: 10
    contentItem: Rectangle { implicitHeight: 1; color: t.border }
}
