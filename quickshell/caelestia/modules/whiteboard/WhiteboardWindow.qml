import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia
import Caelestia.Config
import qs.components
import qs.services
import qs.utils


PanelWindow {
    id: win

    color: "transparent"
    visible: false

    screen: WhiteboardService.targetScreen || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    contentItem.Config.screen: screen ? screen.name : ""
    contentItem.Tokens.screen: screen ? screen.name : ""

    // Position next to the left bar using anchors & margins
    anchors.left: true
    anchors.top: true
    margins.left: 80
    margins.top: screen ? Math.max(16, Math.min(WhiteboardService.targetY - implicitHeight / 2, screen.height - implicitHeight - 16)) : 0

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay

    // Window dimensions
    implicitWidth: 600
    implicitHeight: 450

    onVisibleChanged: {
        if (!visible) {
            showSizeConfig = false;
            showColorPicker = false;
        }
    }

    Component.onCompleted: {
        WhiteboardService.window = win;
    }

    // =========================================================
    // --- STATE & CONFIGURATION
    // =========================================================
    property string currentTool: "pen" // "pen", "brush", "eraser"
    property var toolKeys: ["pen", "brush", "eraser"]
    property int currentToolIndex: Math.max(0, toolKeys.indexOf(currentTool))

    // UI Toggle States
    property bool showSizeConfig: false
    property bool showColorPicker: false

    // Infinite Color Picker State
    property real pickHue: 0.74
    property real pickSat: 0.33
    property real pickVal: 0.97
    property color currentColor: Qt.hsva(pickHue, pickSat, pickVal, 1.0)
    
    // Tool Size Config State (Independent memory per tool)
    property real penSizeRatio: 0.3
    property real brushSizeRatio: 0.4
    property real eraserSizeRatio: 0.6

    property real currentSizeRatio: {
        if (currentTool === "eraser") return eraserSizeRatio;
        if (currentTool === "brush") return brushSizeRatio;
        return penSizeRatio;
    }

    property real actualToolSize: {
        if (currentTool === "eraser") return 8 + (currentSizeRatio * 60);
        if (currentTool === "brush") return 4 + (currentSizeRatio * 40);
        return 2 + (currentSizeRatio * 30);
    }

    // Styling Helpers
    property color baseTextColor: Colours.palette.m3onSurface
    property color solidBgColor: Colours.palette.m3background
    property color themeBaseColor: Colours.palette.m3surface
    property color panelBgColor: Colours.tPalette.m3surface
    property color panelBorderColor: Colours.palette.m3outline

    // Zoom limits and World Size
    property real minZoom: 0.1
    property real maxZoom: 5.0
    property real worldSize: 2048 

    // =========================================================
    // --- HISTORY SYSTEM (UNDO / REDO)
    // =========================================================
    property var actionHistory: []
    property int historyStep: -1
    property int maxHistory: 50
    property var currentAction: null

    function commitAction(action) {
        var newHistory = win.actionHistory.slice(0, win.historyStep + 1);
        newHistory.push(action);
        
        if (newHistory.length > win.maxHistory) {
            newHistory.shift();
        }
        
        win.actionHistory = newHistory;
        win.historyStep = win.actionHistory.length - 1;
    }

    function undo() {
        if (win.historyStep >= 0) {
            win.historyStep--;
            triggerReplay();
        }
    }

    function redo() {
        if (win.historyStep < win.actionHistory.length - 1) {
            win.historyStep++;
            triggerReplay();
        }
    }

    function triggerReplay() {
        drawCanvas._replayPending = true;
        drawCanvas.requestPaint();
    }

    // Shortcuts for Undo/Redo
    Shortcut { enabled: win.visible; sequence: "Ctrl+Z"; onActivated: win.undo() }
    Shortcut { enabled: win.visible; sequence: "Ctrl+Shift+Z"; onActivated: win.redo() }

    // IPC Handler to toggle visibility from bash / bar
    IpcHandler {
        target: "whiteboard"
        property alias visible: win.visible
        function toggle(): void {
            if (!win.visible) {
                // Find focused screen
                const activeMon = Hypr.focusedMonitor;
                let activeScreen = null;
                if (activeMon) {
                    for (let i = 0; i < Quickshell.screens.length; i++) {
                        if (Quickshell.screens[i].name === activeMon.name) {
                            activeScreen = Quickshell.screens[i];
                            break;
                        }
                    }
                }
                if (!activeScreen && Quickshell.screens.length > 0) {
                    activeScreen = Quickshell.screens[0];
                }
                
                WhiteboardService.targetScreen = activeScreen;
                if (activeScreen) {
                    WhiteboardService.targetY = activeScreen.height / 2;
                }
            }
            win.visible = !win.visible;
        }
    }

    // Main window background and border styling
    Rectangle {
        anchors.fill: parent
        color: win.solidBgColor
        radius: Tokens.rounding.large
        border.width: 1
        border.color: win.panelBorderColor
        clip: true

        // Grid dots pattern
        Image {
            anchors.fill: parent
            fillMode: Image.Tile
            opacity: 0.15
            
            property real dotRadius: 1.2
            property real dotSpacing: 12
            property color dotC: win.baseTextColor
            
            source: `data:image/svg+xml;utf8,<svg width='${dotSpacing}' height='${dotSpacing}' xmlns='http://www.w3.org/2000/svg'><circle cx='${dotSpacing/2}' cy='${dotSpacing/2}' r='${dotRadius}' fill='rgb(${dotC.r*255},${dotC.g*255},${dotC.b*255})' /></svg>`
        }

        // =========================================================
        // --- CAMERA RIG (Handles viewport size, rotation, gestures)
        // =========================================================
        Item {
            id: cameraRig
            anchors.fill: parent
            clip: true

            function zoomBy(factor) {
                zoomContainer.scale = Math.max(win.minZoom, Math.min(zoomContainer.scale * factor, win.maxZoom));
            }

            PinchHandler {
                target: zoomContainer
                minimumScale: win.minZoom
                maximumScale: win.maxZoom
            }

            // =========================================================
            // --- CANVAS CONTAINER (Pans and Scales)
            // =========================================================
            Item {
                id: zoomContainer
                width: win.worldSize
                height: win.worldSize
                
                x: (cameraRig.width - width) / 2
                y: (cameraRig.height - height) / 2
                
                transformOrigin: Item.Center
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                DragHandler {
                    target: zoomContainer
                    enabled: win.currentTool === "mouse"
                    acceptedButtons: Qt.LeftButton
                }

                // --- HIGH-PERFORMANCE SYNCHRONOUS CANVAS ---
                Canvas {
                    id: drawCanvas
                    anchors.fill: parent
                    z: 1
                    
                    renderTarget: Canvas.FramebufferObject
                    
                    property real lastX: -1
                    property real lastY: -1
                    
                    property var _queue: []
                    property bool _clearPending: false
                    property bool _replayPending: false

                    function renderBrushLine(ctx, s, isLive) {
                        var bSize = s.penSize || 18;
                        var segments = isLive ? [{x1: s.x1, y1: s.y1, x2: s.x2, y2: s.y2}] : s.segments;
                        
                        var bristleCount = Math.max(6, Math.floor(bSize * 0.6));
                        
                        ctx.globalCompositeOperation = "source-over";
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        
                        var col = s.color;
                        
                        for (var b = 0; b < bristleCount; b++) {
                            var t = b / bristleCount;
                            var angle = t * Math.PI * 2;
                            var radius = (0.3 + (((b * 7 + 3) % 11) / 11) * 0.7) * (bSize / 2);
                            var offX = Math.cos(angle) * radius * 0.5;
                            var offY = Math.sin(angle) * radius * 0.5;
                            var alpha = 0.25 + (((b * 13 + 5) % 17) / 17) * 0.45;
                            var width = 0.8 + (((b * 3 + 1) % 5) / 5) * 1.6;
                            
                            ctx.globalAlpha = alpha;
                            ctx.lineWidth = width;
                            ctx.strokeStyle = col;
                            
                            ctx.beginPath();
                            ctx.moveTo(segments[0].x1 + offX, segments[0].y1 + offY);
                            for (var j = 0; j < segments.length; j++) {
                                ctx.lineTo(segments[j].x2 + offX, segments[j].y2 + offY);
                            }
                            ctx.stroke();
                        }
                        
                        ctx.globalAlpha = 1.0;
                    }

                    function applyToolStyle(ctx, tool, color, customSize) {
                        ctx.lineCap = "round";
                        ctx.lineJoin = "round";
                        
                        if (tool === "eraser") {
                            ctx.globalCompositeOperation = "destination-out";
                            ctx.lineWidth = customSize || win.actualToolSize;
                            ctx.strokeStyle = "rgba(0,0,0,1)"; 
                            ctx.globalAlpha = 1.0;
                            ctx.shadowBlur = 0;
                            ctx.shadowColor = "transparent";
                        } else { 
                            ctx.globalCompositeOperation = "source-over";
                            ctx.strokeStyle = color;
                            ctx.lineWidth = customSize || win.actualToolSize;
                            ctx.shadowBlur = 0;
                            ctx.shadowColor = "transparent";
                            ctx.globalAlpha = 1.0;
                        }
                    }

                    onPaint: {
                        var ctx = getContext("2d");
                        
                        if (_replayPending) {
                            ctx.clearRect(0, 0, width, height);
                            for (var h = 0; h <= win.historyStep; h++) {
                                var action = win.actionHistory[h];
                                if (!action) continue;

                                if (action.type === "clear") {
                                    ctx.clearRect(0, 0, width, height);
                                } else if (action.type === "fill_bg") {
                                    ctx.globalCompositeOperation = "destination-over";
                                    ctx.fillStyle = action.color;
                                    ctx.fillRect(0, 0, width, height);
                                    ctx.globalCompositeOperation = "source-over";
                                } else if (action.type === "stroke") {
                                    if (action.tool === "brush") {
                                        renderBrushLine(ctx, action, false);
                                    } else {
                                        ctx.beginPath();
                                        applyToolStyle(ctx, action.tool, action.color, action.penSize);
                                        
                                        if (action.segments && action.segments.length > 0) {
                                            ctx.moveTo(action.segments[0].x1, action.segments[0].y1);
                                            for (var k = 0; k < action.segments.length; k++) {
                                                ctx.lineTo(action.segments[k].x2, action.segments[k].y2);
                                            }
                                            ctx.stroke();
                                        }
                                    }
                                }
                            }
                            _replayPending = false;
                            _queue = []; 
                            return;
                        }

                        if (_clearPending) {
                            ctx.clearRect(0, 0, width, height);
                            _clearPending = false;
                        }
                        
                        for (var i = 0; i < _queue.length; i++) {
                            var q = _queue[i];
                            
                            if (q.type === "fill_bg") {
                                ctx.globalCompositeOperation = "destination-over";
                                ctx.fillStyle = q.color;
                                ctx.fillRect(0, 0, width, height);
                                ctx.globalCompositeOperation = "source-over";
                            } else if (q.tool === "brush") {
                                renderBrushLine(ctx, q, true);
                            } else {
                                ctx.beginPath();
                                applyToolStyle(ctx, q.tool, q.color, q.penSize);
                                ctx.moveTo(q.x1, q.y1);
                                ctx.lineTo(q.x2, q.y2);
                                ctx.stroke();
                            }
                        }
                        
                        _queue = []; 
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: win.currentTool === "mouse" ? Qt.NoButton : Qt.LeftButton
                        
                        onWheel: (wheel) => {
                            let deltaY = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : (wheel.pixelDelta ? wheel.pixelDelta.y : 0);
                            let deltaX = wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : (wheel.pixelDelta ? wheel.pixelDelta.x : 0);
                            let delta = deltaY !== 0 ? deltaY : deltaX;
                            
                            if (delta === 0) {
                                wheel.accepted = false;
                                return;
                            }
                            
                            wheel.accepted = true;
                            let zoomFactor = delta > 0 ? 1.15 : (1.0 / 1.15);
                            cameraRig.zoomBy(zoomFactor);
                        }

                        onPressed: (mouse) => {
                            win.showSizeConfig = false;
                            win.showColorPicker = false;

                            if (win.currentTool === "fill") {
                                let freezeCol = win.currentColor.toString();
                                win.commitAction({ type: "fill_bg", color: freezeCol });
                                drawCanvas._queue.push({ type: "fill_bg", color: freezeCol });
                                
                                drawCanvas.markDirty(Qt.rect(0, 0, drawCanvas.width, drawCanvas.height)); 
                                drawCanvas.requestPaint();
                                return;
                            }

                            drawCanvas.lastX = mouse.x;
                            drawCanvas.lastY = mouse.y;
                            
                            win.currentAction = { 
                                type: "stroke", 
                                tool: win.currentTool, 
                                color: win.currentColor.toString(), 
                                penSize: win.actualToolSize,
                                segments: [] 
                            };
                            var initialSegment = { x1: mouse.x, y1: mouse.y, x2: mouse.x + 0.1, y2: mouse.y };
                            win.currentAction.segments.push(initialSegment);

                            drawCanvas._queue.push({
                                type: "stroke",
                                tool: win.currentTool,
                                color: win.currentColor.toString(),
                                penSize: win.actualToolSize,
                                x1: initialSegment.x1, y1: initialSegment.y1, 
                                x2: initialSegment.x2, y2: initialSegment.y2
                            });
                            
                            var rad = 20;
                            drawCanvas.markDirty(Qt.rect(mouse.x - rad, mouse.y - rad, rad*2, rad*2));
                            drawCanvas.requestPaint();
                        }

                        onPositionChanged: (mouse) => {
                            if (pressed && win.currentTool !== "fill" && win.currentTool !== "mouse") {
                                var segment = {
                                    x1: drawCanvas.lastX, y1: drawCanvas.lastY,
                                    x2: mouse.x, y2: mouse.y
                                };
                                
                                if (win.currentAction) {
                                    win.currentAction.segments.push(segment);
                                }

                                drawCanvas._queue.push({
                                    type: "stroke",
                                    tool: win.currentTool,
                                    color: win.currentColor.toString(),
                                    penSize: win.actualToolSize,
                                    x1: segment.x1, y1: segment.y1, 
                                    x2: segment.x2, y2: segment.y2
                                });
                                
                                var rad = 20;
                                var minX = Math.min(drawCanvas.lastX, mouse.x) - rad;
                                var minY = Math.min(drawCanvas.lastY, mouse.y) - rad;
                                var w = Math.abs(mouse.x - drawCanvas.lastX) + rad*2;
                                var h = Math.abs(mouse.y - drawCanvas.lastY) + rad*2;
                                
                                drawCanvas.lastX = mouse.x;
                                drawCanvas.lastY = mouse.y;
                                
                                drawCanvas.markDirty(Qt.rect(minX, minY, w, h));
                                drawCanvas.requestPaint();
                            }
                        }

                        onReleased: (mouse) => {
                            if (win.currentAction) {
                                win.commitAction(win.currentAction);
                                win.currentAction = null;
                            }
                        }
                    }
                }
            }
        }

        // =========================================================
        // --- TOP TOOLBAR (Actions like Zoom, Undo, Redo, Copy, Clear)
        // =========================================================
        Row {
            id: topActionsLayout
            z: 10
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            // --- ZOOM PILL ---
            Rectangle {
                width: zoomRow.width + Tokens.padding.medium
                height: 38
                radius: Tokens.rounding.medium
                color: win.panelBgColor
                border.width: 1
                border.color: win.panelBorderColor

                Row {
                    id: zoomRow
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small

                    Item {
                        width: 28; height: 28
                        Rectangle {
                            anchors.fill: parent; radius: Tokens.rounding.small; z:-1
                            color: zoomMinusMouse.containsMouse ? Colours.palette.m3surfaceVariant : "transparent"
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "zoom_out"
                            color: win.baseTextColor
                        }
                        MouseArea {
                            id: zoomMinusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: cameraRig.zoomBy(1.0 / 1.25)
                        }
                    }

                    Item {
                        width: 44; height: 28
                        Rectangle {
                            anchors.fill: parent; radius: Tokens.rounding.small; z:-1
                            color: zoomResetMouse.containsMouse ? Colours.palette.m3surfaceVariant : "transparent"
                        }
                        Text {
                            anchors.centerIn: parent
                            text: Math.round(zoomContainer.scale * 100) + "%"
                            font.pixelSize: 11
                            color: win.baseTextColor
                            font.bold: true
                        }
                        MouseArea {
                            id: zoomResetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                zoomContainer.scale = 1.0;
                                zoomContainer.x = (cameraRig.width - zoomContainer.width) / 2;
                                zoomContainer.y = (cameraRig.height - zoomContainer.height) / 2;
                            }
                        }
                    }

                    Item {
                        width: 28; height: 28
                        Rectangle {
                            anchors.fill: parent; radius: Tokens.rounding.small; z:-1
                            color: zoomPlusMouse.containsMouse ? Colours.palette.m3surfaceVariant : "transparent"
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "zoom_in"
                            color: win.baseTextColor
                        }
                        MouseArea {
                            id: zoomPlusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: cameraRig.zoomBy(1.25)
                        }
                    }
                }
            }

            // --- UNDO BUTTON ---
            Rectangle {
                width: 38; height: 38
                radius: Tokens.rounding.medium
                color: win.panelBgColor
                border.width: 1
                border.color: win.panelBorderColor
                
                Rectangle {
                    anchors.centerIn: parent; width: 28; height: 28; radius: Tokens.rounding.small; z:-1
                    color: undoMouse.containsMouse ? Colours.palette.m3surfaceVariant : "transparent"
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "undo"
                    color: win.baseTextColor
                    opacity: win.historyStep >= 0 ? 1.0 : 0.4
                }

                MouseArea {
                    id: undoMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: win.historyStep >= 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.undo()
                }
            }

            // --- REDO BUTTON ---
            Rectangle {
                width: 38; height: 38
                radius: Tokens.rounding.medium
                color: win.panelBgColor
                border.width: 1
                border.color: win.panelBorderColor
                
                Rectangle {
                    anchors.centerIn: parent; width: 28; height: 28; radius: Tokens.rounding.small; z:-1
                    color: redoMouse.containsMouse ? Colours.palette.m3surfaceVariant : "transparent"
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "redo"
                    color: win.baseTextColor
                    opacity: win.historyStep < win.actionHistory.length - 1 ? 1.0 : 0.4
                }

                MouseArea {
                    id: redoMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: win.historyStep < win.actionHistory.length - 1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.redo()
                }
            }

            // --- COPY BUTTON ---
            Rectangle {
                width: 38; height: 38
                radius: Tokens.rounding.medium
                color: win.panelBgColor
                border.width: 1
                border.color: win.panelBorderColor
                
                Rectangle {
                    anchors.centerIn: parent; width: 28; height: 28; radius: Tokens.rounding.small; z:-1
                    color: copyMouse.containsMouse ? Colours.palette.m3surfaceVariant : "transparent"
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "content_copy"
                    color: win.baseTextColor
                }

                MouseArea {
                    id: copyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var tempPath = Paths.cache + "/whiteboard.png";
                        drawCanvas.grabToImage(function(result) {
                            if (result.saveToFile(tempPath)) {
                                Quickshell.execDetached(["sh", "-c", "wl-copy -t image/png < " + tempPath]);
                                Toaster.toast("Pizarra", "Copiado al portapapeles", "content_copy", Toast.Success);
                            } else {
                                Toaster.toast("Pizarra", "Error al guardar el dibujo", "error", Toast.Error);
                            }
                        });
                    }
                }
            }

            // --- CLEAR BUTTON ---
            Rectangle {
                width: 38; height: 38
                radius: Tokens.rounding.medium
                color: win.panelBgColor
                border.width: 1
                border.color: win.panelBorderColor
                
                Rectangle {
                    anchors.centerIn: parent; width: 28; height: 28; radius: Tokens.rounding.small; z:-1
                    color: clearMouse.containsMouse ? Colours.palette.m3errorContainer : "transparent"
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "delete"
                    color: clearMouse.containsMouse ? Colours.palette.m3onErrorContainer : Colours.palette.m3error
                }

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        win.commitAction({ type: "clear" });
                        drawCanvas._clearPending = true;
                        drawCanvas.requestPaint();
                    }
                }
            }
        }

        // =========================================================
        // --- BOTTOM TOOLBAR (Tool selectors, Color picker, Size config)
        // =========================================================
        Rectangle {
            id: toolbar
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: Tokens.padding.medium
            z: 10

            width: toolRow.width + Tokens.padding.medium
            height: 44
            radius: Tokens.rounding.large
            color: win.panelBgColor
            border.width: 1
            border.color: win.panelBorderColor

            Row {
                id: toolRow
                anchors.centerIn: parent
                spacing: Tokens.spacing.medium

                // --- TOOL: PAN/ZOOM ---
                ToolButton {
                    iconName: "pan_tool"
                    toolKey: "mouse"
                }

                // --- TOOL: PEN ---
                ToolButton {
                    iconName: "edit"
                    toolKey: "pen"
                }

                // --- TOOL: BRUSH ---
                ToolButton {
                    iconName: "brush"
                    toolKey: "brush"
                }

                // --- TOOL: ERASER ---
                ToolButton {
                    iconName: "ink_eraser"
                    toolKey: "eraser"
                }

                // --- ACTION: STROKE WIDTH SLIDER ---
                Item {
                    width: 32; height: 32
                    Rectangle {
                        anchors.fill: parent; radius: Tokens.rounding.small; z:-1
                        color: win.showSizeConfig ? Colours.palette.m3primaryContainer : (sizeBtnMouse.containsMouse ? Colours.palette.m3surfaceVariant : "transparent")
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "line_weight"
                        color: win.showSizeConfig ? Colours.palette.m3onPrimaryContainer : win.baseTextColor
                    }
                    MouseArea {
                        id: sizeBtnMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            win.showSizeConfig = !win.showSizeConfig;
                            win.showColorPicker = false;
                        }
                    }
                }

                // --- ACTION: COLOR PALETTE ---
                Item {
                    width: 32; height: 32
                    Rectangle {
                        anchors.fill: parent; radius: Tokens.rounding.small; z:-1
                        color: win.showColorPicker ? Colours.palette.m3primaryContainer : (colorBtnMouse.containsMouse ? Colours.palette.m3surfaceVariant : "transparent")
                    }
                    // Color preview circle inside palette icon
                    Rectangle {
                        width: 16; height: 16
                        radius: 8
                        color: win.currentColor
                        anchors.centerIn: parent
                        border.width: 1
                        border.color: win.panelBorderColor
                    }
                    MouseArea {
                        id: colorBtnMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            win.showColorPicker = !win.showColorPicker;
                            win.showSizeConfig = false;
                        }
                    }
                }
            }
        }

        // =========================================================
        // --- TOOL SIZE CONFIGURATION POPUP
        // =========================================================
        Rectangle {
            id: sizeConfigPopup
            z: 20
            width: 240
            height: 54
            radius: Tokens.rounding.medium
            color: Colours.palette.m3surface
            border.width: 1
            border.color: win.panelBorderColor
            
            anchors.bottom: toolbar.top
            anchors.bottomMargin: Tokens.padding.small
            anchors.horizontalCenter: parent.horizontalCenter
            
            visible: win.showSizeConfig
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: win.currentTool === "eraser" ? "ink_eraser" : (win.currentTool === "brush" ? "brush" : "edit")
                    color: win.baseTextColor
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 6
                    radius: 3
                    color: Colours.palette.m3surfaceVariant
                    
                    Rectangle {
                        width: parent.width * win.currentSizeRatio
                        height: parent.height
                        radius: parent.radius
                        color: Colours.palette.m3primary
                    }

                    Rectangle {
                        width: 16; height: 16
                        radius: 8
                        color: Colours.palette.m3primary
                        x: (parent.width * win.currentSizeRatio) - 8
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        
                        function updateSize(mouse) {
                            let val = Math.max(0.0, Math.min(1.0, mouse.x / width));
                            if (win.currentTool === "eraser") win.eraserSizeRatio = val;
                            else if (win.currentTool === "brush") win.brushSizeRatio = val;
                            else win.penSizeRatio = val;
                        }

                        onPositionChanged: (mouse) => { if (pressed) updateSize(mouse) }
                        onPressed: (mouse) => updateSize(mouse)
                    }
                }

                // Dynamic Preview Circle
                Item {
                    width: 24
                    height: 24
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.max(2, Math.min(24, win.actualToolSize * 0.5))
                        height: width
                        radius: width / 2
                        color: win.currentTool === "eraser" ? "transparent" : win.currentColor
                        border.width: 1
                        border.color: win.baseTextColor
                    }
                }
            }
        }

        // =========================================================
        // --- ADVANCED COLOR PICKER POPUP
        // =========================================================
        Rectangle {
            id: colorPickerPopup
            z: 20
            width: 280
            height: 250
            radius: Tokens.rounding.medium
            color: Colours.palette.m3surface
            border.width: 1
            border.color: win.panelBorderColor
            
            anchors.bottom: toolbar.top
            anchors.bottomMargin: Tokens.padding.small
            anchors.horizontalCenter: parent.horizontalCenter
            
            visible: win.showColorPicker
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150 } }

            Column {
                anchors.centerIn: parent
                spacing: Tokens.spacing.medium

                // SV Square and Hue Slider
                Row {
                    spacing: Tokens.spacing.medium
                    anchors.horizontalCenter: parent.horizontalCenter

                    // Saturation / Value Square
                    Rectangle {
                        width: 180; height: 150
                        radius: Tokens.rounding.small
                        color: Qt.hsva(win.pickHue, 1, 1, 1)
                        clip: true

                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "white" }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Vertical
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 1.0; color: "black" }
                            }
                        }

                        // Target Reticle
                        Rectangle {
                            width: 12; height: 12
                            radius: 6
                            border.width: 2; border.color: "white"
                            color: "transparent"
                            x: (win.pickSat * parent.width) - 6
                            y: ((1.0 - win.pickVal) * parent.height) - 6
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.CrossCursor
                            function updateSV(mouse) {
                                win.pickSat = Math.max(0, Math.min(1, mouse.x / width));
                                win.pickVal = 1.0 - Math.max(0, Math.min(1, mouse.y / height));
                            }
                            onPressed: (mouse) => updateSV(mouse)
                            onPositionChanged: (mouse) => { if (pressed) updateSV(mouse) }
                        }
                    }

                    // Hue Slider
                    Rectangle {
                        width: 20; height: 150
                        radius: Tokens.rounding.small
                        clip: true
                        gradient: Gradient {
                            orientation: Gradient.Vertical
                            GradientStop { position: 0.0; color: "#ff0000" }
                            GradientStop { position: 0.166; color: "#ffff00" }
                            GradientStop { position: 0.333; color: "#00ff00" }
                            GradientStop { position: 0.5; color: "#00ffff" }
                            GradientStop { position: 0.666; color: "#0000ff" }
                            GradientStop { position: 0.833; color: "#ff00ff" }
                            GradientStop { position: 1.0; color: "#ff0000" }
                        }

                        Rectangle {
                            width: parent.width; height: 6
                            radius: 3
                            border.width: 1; border.color: "black"
                            color: "white"
                            y: (win.pickHue * parent.height) - 3
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function updateH(mouse) {
                                win.pickHue = Math.max(0, Math.min(1, mouse.y / height));
                            }
                            onPressed: (mouse) => updateH(mouse)
                            onPositionChanged: (mouse) => { if (pressed) updateH(mouse) }
                        }
                    }
                }

                // Preset Swatches
                Row {
                    spacing: Tokens.spacing.small
                    anchors.horizontalCenter: parent.horizontalCenter

                    property var swatches: ["#ffffff", "#ff0000", "#00ff00", "#0000ff", "#ffff00", "#ff00ff", "#00ffff", "#000000"]

                    Repeater {
                        model: parent.swatches
                        delegate: Rectangle {
                            width: 20; height: 20
                            radius: 10
                            color: modelData
                            border.width: 1
                            border.color: win.panelBorderColor

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    win.currentColor = modelData;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Component for toolbar buttons
    component ToolButton: Item {
        required property string iconName
        required property string toolKey

        width: 32; height: 32
        readonly property bool isActive: win.currentTool === toolKey

        Rectangle {
            anchors.fill: parent
            radius: Tokens.rounding.small
            color: parent.isActive ? Colours.palette.m3primary : (mouseArea.containsMouse ? Colours.palette.m3surfaceVariant : "transparent")
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: parent.iconName
            color: parent.isActive ? Colours.palette.m3onPrimary : win.baseTextColor
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                win.currentTool = parent.toolKey;
                win.showSizeConfig = false;
                win.showColorPicker = false;
            }
        }
    }
}
