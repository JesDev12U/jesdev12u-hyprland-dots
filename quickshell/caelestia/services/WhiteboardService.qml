pragma Singleton

import QtQuick
import Quickshell
import qs.services

Singleton {
    id: root

    // Reference to the active WhiteboardWindow
    property var window: null

    // Screen where the whiteboard should be displayed
    property ShellScreen targetScreen: null

    // Y coordinate of the button's center relative to the screen
    property real targetY: 0

    function toggle(screen, yCoords) {
        targetScreen = screen;
        targetY = yCoords;
        if (window) {
            window.visible = !window.visible;
        }
    }
}
