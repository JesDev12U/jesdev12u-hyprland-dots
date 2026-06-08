import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import Quickshell
import Quickshell.Io

Item {
    id: root

    required property ShellScreen screen

    implicitWidth: icon.implicitHeight + Tokens.padding.small * 2
    implicitHeight: icon.implicitHeight

    StateLayer {
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: icon.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        onClicked: {
            let absoluteY = root.mapToItem(null, 0, root.height / 2).y;
            WhiteboardService.toggle(root.screen, absoluteY);
        }
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent

        text: "draw"
        color: Colours.palette.m3primary
        fontStyle: Tokens.font.icon.builders.small.weight(Font.Bold).build()
    }
}
