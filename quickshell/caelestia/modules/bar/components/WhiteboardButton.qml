import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import Quickshell
import Quickshell.Io

Item {
    id: root

    implicitWidth: icon.implicitHeight + Tokens.padding.small * 2
    implicitHeight: icon.implicitHeight

    StateLayer {
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: implicitHeight
        implicitHeight: icon.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        onClicked: {
            toggleProc.running = false;
            toggleProc.running = true;
        }
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent

        text: "draw"
        color: Colours.palette.m3primary
        fontStyle: Tokens.font.icon.builders.small.weight(Font.Bold).build()
    }

    Process {
        id: toggleProc
        command: ["quickshell", "ipc", "whiteboard", "toggle"]
    }
}
