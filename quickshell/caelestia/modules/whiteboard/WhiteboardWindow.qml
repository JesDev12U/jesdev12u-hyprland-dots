import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
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
    anchors.right: win.isFullScreen
    anchors.bottom: win.isFullScreen

    margins.left: win.isFullScreen ? 0 : 80
    margins.top: win.isFullScreen ? 0 : (screen ? Math.max(16, Math.min(WhiteboardService.targetY - implicitHeight / 2, screen.height - implicitHeight - 16)) : 0)
    margins.right: 0
    margins.bottom: 0

    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay

    // Window dimensions
    implicitWidth: 600
    implicitHeight: 450

    onVisibleChanged: {
        if (visible) {
            rootRectangle.forceActiveFocus();
            win.triggerReplay();
        } else {
            showSizeConfig = false;
            showColorPicker = false;
        }
    }

    onIsFullScreenChanged: {
        win.triggerReplay();
    }

    Component.onCompleted: {
        WhiteboardService.window = win;
        win.jsState.history = win.actionHistory;
        win.jsState.step = win.historyStep;
    }

    // =========================================================
    // --- STATE & CONFIGURATION
    // =========================================================
    property bool isFullScreen: false
    property string currentTool: "pen" // "mouse", "pen", "brush", "eraser", "line", "rectangle", "circle", "text", "arrow"
    property var toolKeys: ["mouse", "pen", "brush", "eraser", "line", "arrow", "rectangle", "circle", "text"]
    property int currentToolIndex: Math.max(0, toolKeys.indexOf(currentTool))

    // Text editing and moving properties
    property bool isHoveringText: false
    property int hoveredTextIndex: -1
    property int editingTextIndex: -1
    property real lastHoverX: -1
    property real lastHoverY: -1

    // Hand tool moving properties
    property int hoveredElementIndex: -1
    property int grabbedElementIndex: -1
    property real grabStartMouseX: 0
    property real grabStartMouseY: 0
    property real grabbedElementDx: 0
    property real grabbedElementDy: 0

    onCurrentToolChanged: {
        win.selectedElementIndices = [];
        win.grabbedElementIndex = -1;
        win.resizeGrabbed = false;
        win.rotateGrabbed = false;
        win.triggerReplay();
        previewCanvas.requestPaint();
    }

    // Selection and Resize properties
    property int selectedElementIndex: -1
    property var selectedElementIndices: []
    property real selectionMinX: 0
    property real selectionMaxX: 0
    property real selectionMinY: 0
    property real selectionMaxY: 0
    property real selectionRotation: 0
    property bool resizeGrabbed: false
    property string resizeHandle: "" // "TL", "TR", "BL", "BR"
    property real grabbedMinX: 0
    property real grabbedMaxX: 0
    property real grabbedMinY: 0
    property real grabbedMaxY: 0
    property var actionBeforeResize: null
    property var actionsBeforeResize: []

    // Rotation properties
    property bool rotateGrabbed: false
    property real grabbedInitialAngle: 0
    property real grabbedElementInitialRotation: 0
    property real grabbedElementRotationDelta: 0

    onSelectedElementIndicesChanged: {
        if (selectedElementIndices.length > 0) {
            win.selectedElementIndex = selectedElementIndices[selectedElementIndices.length - 1];
        } else {
            win.selectedElementIndex = -1;
        }
    }

    // Current text toolbar properties
    property string activeTextFontFamily: "sans-serif" // "sans-serif", "serif", "monospace", "cursive"
    property bool activeTextIsBold: true
    property bool activeTextIsItalic: false

    // Clipboard for copy-pasting elements
    property var copiedElements: []
    property bool isCursorOverUIOnPress: false

    function copySelectedElement() {
        if (win.selectedElementIndices.length > 0) {
            let list = [];
            for (let idx of win.selectedElementIndices) {
                let action = win.actionHistory[idx];
                if (action) {
                    list.push(cloneAction(action));
                }
            }
            win.copiedElements = list;
            Toaster.toast("Pizarra", "Dibujo copiado", "content_copy", Toast.Success);
        }
    }

    function pasteCopiedElement() {
        if (win.copiedElements && win.copiedElements.length > 0) {
            let offset = 24;
            let newIndices = [];
            let newCopiedList = [];
            
            for (let i = 0; i < win.copiedElements.length; i++) {
                let pasted = cloneAction(win.copiedElements[i]);
                win.shiftAction(pasted, offset, offset);
                win.commitAction(pasted);
                newIndices.push(win.historyStep);
                newCopiedList.push(pasted);
            }
            
            win.copiedElements = newCopiedList;
            win.selectedElementIndices = newIndices;
            win.updateSelectionBounds();
            
            win.triggerReplay();
            previewCanvas.requestPaint();
            Toaster.toast("Pizarra", "Dibujo pegado", "content_paste", Toast.Success);
        }
    }

    function deleteSelectedElements() {
        if (win.selectedElementIndices.length === 0) return;
        
        let sortedIndices = win.selectedElementIndices.slice().sort((a, b) => b - a);
        let newHistory = win.actionHistory.slice(0, win.historyStep + 1);
        for (let idx of sortedIndices) {
            if (idx >= 0 && idx < newHistory.length) {
                newHistory.splice(idx, 1);
            }
        }
        
        win.selectedElementIndices = [];
        win.actionHistory = newHistory;
        win.historyStep = win.actionHistory.length - 1;
        win.jsState.history = win.actionHistory;
        win.jsState.step = win.historyStep;
        win.updateSelectionBounds();
        
        win.triggerReplay();
        previewCanvas.requestPaint();
        Toaster.toast("Pizarra", "Elementos eliminados", "delete", Toast.Success);
    }

    function rotateAction(action, delta, cx, cy) {
        if (!action) return;
        
        // 1. Calculate current center of the element's bounding box
        let ecx = (action.minX + action.maxX) / 2;
        let ecy = (action.minY + action.maxY) / 2;
        
        // 2. Rotate the element's center around the rotation center (cx, cy)
        let p = rotatePoint(ecx, ecy, cx, cy, delta);
        
        // 3. Calculate translation offset
        let dx = p.x - ecx;
        let dy = p.y - ecy;
        
        // 4. Translate the element coordinates
        if (action.type === "shape") {
            action.x1 += dx;
            action.y1 += dy;
            action.x2 += dx;
            action.y2 += dy;
        } else if (action.type === "text") {
            action.x += dx;
            action.y += dy;
        } else if (action.type === "stroke") {
            for (var s = 0; s < action.segments.length; s++) {
                let seg = action.segments[s];
                seg.x1 += dx;
                seg.y1 += dy;
                seg.x2 += dx;
                seg.y2 += dy;
            }
        }
        
        // 5. Update rotation
        action.rotation = (action.rotation || 0) + delta;
        
        // 6. Translate the bounding box
        action.minX += dx;
        action.maxX += dx;
        action.minY += dy;
        action.maxY += dy;

        // Shift eraser paths recursively
        if (action.eraserPaths) {
            for (var ep = 0; ep < action.eraserPaths.length; ep++) {
                shiftAction(action.eraserPaths[ep], dx, dy);
            }
        }
    }

    function rotatePoint(px, py, cx, cy, angle) {
        let cos = Math.cos(angle);
        let sin = Math.sin(angle);
        return {
            x: cx + (px - cx) * cos - (py - cy) * sin,
            y: cy + (px - cx) * sin + (py - cy) * cos
        };
    }

    function updateSelectionBounds() {
        if (win.selectedElementIndices.length === 0) {
            win.selectionMinX = 0;
            win.selectionMaxX = 0;
            win.selectionMinY = 0;
            win.selectionMaxY = 0;
            return;
        }
        let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
        for (let idx of win.selectedElementIndices) {
            let action = win.actionHistory[idx];
            if (action) {
                if (action.minX === undefined) {
                    if (action.type === "stroke") calculateStrokeBounds(action);
                    else if (action.type === "shape") {
                        action.minX = Math.min(action.x1, action.x2);
                        action.maxX = Math.max(action.x1, action.x2);
                        action.minY = Math.min(action.y1, action.y2);
                        action.maxY = Math.max(action.y1, action.y2);
                    } else if (action.type === "text") {
                        let estWidth = win.getTextEstWidth(action.text, action.fontSize, action.fontFamily);
                        let estHeight = action.fontSize;
                        action.minX = action.x - 12;
                        action.maxX = action.x - 12 + estWidth;
                        action.minY = action.y - estHeight / 2;
                        action.maxY = action.y + estHeight / 2;
                    }
                }
                if (action.minX < minX) minX = action.minX;
                if (action.maxX > maxX) maxX = action.maxX;
                if (action.minY < minY) minY = action.minY;
                if (action.maxY > maxY) maxY = action.maxY;
            }
        }
        win.selectionMinX = minX;
        win.selectionMaxX = maxX;
        win.selectionMinY = minY;
        win.selectionMaxY = maxY;
    }

    function getTextEstWidth(text, fontSize, fontFamily) {
        let factor = 0.55;
        if (fontFamily === "monospace") factor = 0.60;
        else if (fontFamily === "cursive") factor = 0.45;
        return text.length * fontSize * factor;
    }

    function drawArrow(ctx, x1, y1, x2, y2, penSize, color) {
        let angle = Math.atan2(y2 - y1, x2 - x1);
        let arrowLength = Math.max(12, penSize * 2.5);
        let arrowAngle = Math.PI / 6;
        let x3 = x2 - arrowLength * Math.cos(angle - arrowAngle);
        let y3 = y2 - arrowLength * Math.sin(angle - arrowAngle);
        let x4 = x2 - arrowLength * Math.cos(angle + arrowAngle);
        let y4 = y2 - arrowLength * Math.sin(angle + arrowAngle);

        ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.fillStyle = color;
        ctx.lineWidth = penSize;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";

        ctx.moveTo(x1, y1);
        ctx.lineTo(x2, y2);
        ctx.stroke();

        ctx.beginPath();
        ctx.moveTo(x2, y2);
        ctx.lineTo(x3, y3);
        ctx.lineTo(x4, y4);
        ctx.closePath();
        ctx.fill();
        ctx.stroke();
    }

    function cloneAction(action) {
        if (!action) return null;
        let clone = {
            type: action.type,
            color: action.color,
            penSize: action.penSize,
            tool: action.tool,
            fontSize: action.fontSize,
            fontFamily: action.fontFamily,
            isBold: action.isBold,
            isItalic: action.isItalic,
            text: action.text,
            shapeType: action.shapeType,
            x: action.x,
            y: action.y,
            x1: action.x1,
            y1: action.y1,
            x2: action.x2,
            y2: action.y2,
            minX: action.minX,
            maxX: action.maxX,
            minY: action.minY,
            maxY: action.maxY,
            rotation: action.rotation,
            historyIndex: action.historyIndex
        };
        if (action.segments) {
            clone.segments = [];
            for (var i = 0; i < action.segments.length; i++) {
                clone.segments.push({
                    x1: action.segments[i].x1,
                    y1: action.segments[i].y1,
                    x2: action.segments[i].x2,
                    y2: action.segments[i].y2
                });
            }
        }
        if (action.eraserPaths) {
            clone.eraserPaths = [];
            for (var ep = 0; ep < action.eraserPaths.length; ep++) {
                clone.eraserPaths.push(cloneAction(action.eraserPaths[ep]));
            }
        }
        return clone;
    }

    function scaleAction(action, scaleX, scaleY, refX, refY) {
        let scaleFactor = (scaleX + scaleY) / 2;
        
        if (action.type === "shape") {
            action.x1 = refX + (action.x1 - refX) * scaleX;
            action.y1 = refY + (action.y1 - refY) * scaleY;
            action.x2 = refX + (action.x2 - refX) * scaleX;
            action.y2 = refY + (action.y2 - refY) * scaleY;
        } else if (action.type === "text") {
            action.x = refX + (action.x - refX) * scaleX;
            action.y = refY + (action.y - refY) * scaleY;
            action.fontSize = Math.max(6, Math.round(action.fontSize * scaleFactor));
        } else if (action.type === "stroke") {
            if (action.penSize) {
                action.penSize = Math.max(1, action.penSize * scaleFactor);
            }
            for (var s = 0; s < action.segments.length; s++) {
                let seg = action.segments[s];
                seg.x1 = refX + (seg.x1 - refX) * scaleX;
                seg.y1 = refY + (seg.y1 - refY) * scaleY;
                seg.x2 = refX + (seg.x2 - refX) * scaleX;
                seg.y2 = refY + (seg.y2 - refY) * scaleY;
            }
        }
        
        if (action.eraserPaths) {
            for (var ep = 0; ep < action.eraserPaths.length; ep++) {
                scaleAction(action.eraserPaths[ep], scaleX, scaleY, refX, refY);
            }
        }
        
        // Recalculate bounds
        if (action.type === "stroke") {
            calculateStrokeBounds(action);
        } else if (action.type === "shape") {
            action.minX = Math.min(action.x1, action.x2);
            action.maxX = Math.max(action.x1, action.x2);
            action.minY = Math.min(action.y1, action.y2);
            action.maxY = Math.max(action.y1, action.y2);
        } else if (action.type === "text") {
            let estWidth = win.getTextEstWidth(action.text, action.fontSize, action.fontFamily);
            let estHeight = action.fontSize;
            action.minX = action.x - 12;
            action.maxX = action.x - 12 + estWidth;
            action.minY = action.y - estHeight / 2;
            action.maxY = action.y + estHeight / 2;
        }
    }

    function shiftAction(action, dx, dy) {
        if (!action) return;
        if (action.type === "text" || action.type === "shape") {
            action.x1 += dx;
            action.y1 += dy;
            action.x2 += dx;
            action.y2 += dy;
            if (action.type === "text") {
                action.x += dx;
                action.y += dy;
            }
        } else if (action.type === "stroke") {
            if (action.segments) {
                for (var s = 0; s < action.segments.length; s++) {
                    action.segments[s].x1 += dx;
                    action.segments[s].y1 += dy;
                    action.segments[s].x2 += dx;
                    action.segments[s].y2 += dy;
                }
            }
        }
        
        if (action.minX !== undefined) {
            action.minX += dx;
            action.maxX += dx;
            action.minY += dy;
            action.maxY += dy;
        }

        if (action.eraserPaths) {
            for (var ep = 0; ep < action.eraserPaths.length; ep++) {
                shiftAction(action.eraserPaths[ep], dx, dy);
            }
        }
    }

    function getHoveredHandle(mx, my) {
        if (win.selectedElementIndices.length === 0) return "";
        let minX, maxX, minY, maxY, rot;
        if (win.selectedElementIndices.length === 1) {
            let action = win.actionHistory[win.selectedElementIndices[0]];
            if (!action) return "";
            minX = action.minX;
            maxX = action.maxX;
            minY = action.minY;
            maxY = action.maxY;
            rot = action.rotation || 0;
        } else {
            minX = win.selectionMinX;
            maxX = win.selectionMaxX;
            minY = win.selectionMinY;
            maxY = win.selectionMaxY;
            rot = 0;
        }
        
        let cx = (minX + maxX) / 2;
        let cy = (minY + maxY) / 2;
        
        // Transform mouse to local unrotated space
        let lmx = mx;
        let lmy = my;
        if (rot !== 0) {
            let cos = Math.cos(-rot);
            let sin = Math.sin(-rot);
            lmx = cx + (mx - cx) * cos - (my - cy) * sin;
            lmy = cy + (mx - cx) * sin + (my - cy) * cos;
        }
        
        let borderOffset = 4 / zoomContainer.scale;
        let bx1 = minX - borderOffset;
        let bx2 = maxX + borderOffset;
        let by1 = minY - borderOffset;
        let by2 = maxY + borderOffset;
        let mouseTol = 15 / zoomContainer.scale;
        
        // Check rotation handle first
        let rxHandleX = (bx1 + bx2) / 2;
        let rxHandleY = by1 - 24 / zoomContainer.scale;
        if (Math.sqrt(Math.pow(lmx - rxHandleX, 2) + Math.pow(lmy - rxHandleY, 2)) < mouseTol) {
            return "ROT";
        }
        
        if (Math.sqrt(Math.pow(lmx - bx1, 2) + Math.pow(lmy - by1, 2)) < mouseTol) return "TL";
        if (Math.sqrt(Math.pow(lmx - bx2, 2) + Math.pow(lmy - by1, 2)) < mouseTol) return "TR";
        if (Math.sqrt(Math.pow(lmx - bx1, 2) + Math.pow(lmy - by2, 2)) < mouseTol) return "BL";
        if (Math.sqrt(Math.pow(lmx - bx2, 2) + Math.pow(lmy - by2, 2)) < mouseTol) return "BR";
        return "";
    }

    function updateHoverState(mx, my) {
        if (win.currentTool === "text") {
            for (var h = win.historyStep; h >= 0; h--) {
                var action = win.actionHistory[h];
                if (action && action.type === "text") {
                    let estWidth = win.getTextEstWidth(action.text, action.fontSize, action.fontFamily);
                    let estHeight = action.fontSize;
                    let xStart = action.x - 12;
                    let yStart = action.y - estHeight / 2;
                    
                    if (mx >= xStart - 6 && mx <= xStart + estWidth + 6 &&
                        my >= yStart - 6 && my <= yStart + estHeight + 6) {
                        win.hoveredTextIndex = h;
                        win.isHoveringText = true;
                        return;
                    }
                }
            }
            win.hoveredTextIndex = -1;
            win.isHoveringText = false;
        } else if (win.currentTool === "mouse") {
            win.hoveredElementIndex = getElementAt(mx, my);
        }
    }

    function isPointErasedByEraser(px, py, actionOrIndex, optHistory, optStep) {
        let history = optHistory !== undefined ? optHistory : win.actionHistory;
        let step = optStep !== undefined ? optStep : win.historyStep;
        let actionIdx = typeof actionOrIndex === "number" ? actionOrIndex : history.indexOf(actionOrIndex);
        if (actionIdx === -1) return false;
        
        for (var he = actionIdx + 1; he <= step; he++) {
            let ep = history[he];
            if (ep && ep.type === "stroke" && ep.tool === "eraser") {
                if (ep.minX !== undefined) {
                    let size = ep.penSize || 18;
                    let rad = size / 2;
                    if (px < ep.minX - rad || px > ep.maxX + rad ||
                        py < ep.minY - rad || py > ep.maxY + rad) {
                        continue;
                    }
                }
                let eraserRadius = (ep.penSize || 18) / 2;
                if (ep.segments) {
                    for (var es = 0; es < ep.segments.length; es++) {
                        let eseg = ep.segments[es];
                        // Quick segment bounding box check
                        let sMinX = eseg.x1 < eseg.x2 ? eseg.x1 : eseg.x2;
                        let sMaxX = eseg.x1 > eseg.x2 ? eseg.x1 : eseg.x2;
                        if (px < sMinX - eraserRadius || px > sMaxX + eraserRadius) continue;
                        
                        let sMinY = eseg.y1 < eseg.y2 ? eseg.y1 : eseg.y2;
                        let sMaxY = eseg.y1 > eseg.y2 ? eseg.y1 : eseg.y2;
                        if (py < sMinY - eraserRadius || py > sMaxY + eraserRadius) continue;

                        if (distToSegmentSq(px, py, eseg.x1, eseg.y1, eseg.x2, eseg.y2) <= eraserRadius * eraserRadius) {
                            return true;
                        }
                    }
                }
            }
        }
        return false;
    }

    function isPointErasedByEraserList(px, py, overlappingErasers, optHistory) {
        let history = optHistory !== undefined ? optHistory : win.actionHistory;
        for (var i = 0; i < overlappingErasers.length; i++) {
            let epIdx = overlappingErasers[i];
            let ep = history[epIdx];
            if (ep) {
                let size = ep.penSize || 18;
                let rad = size / 2;
                if (px < ep.minX - rad || px > ep.maxX + rad ||
                    py < ep.minY - rad || py > ep.maxY + rad) {
                    continue;
                }
                let eraserRadius = size / 2;
                if (ep.segments) {
                    for (var es = 0; es < ep.segments.length; es++) {
                        let eseg = ep.segments[es];
                        // Quick segment bounding box check
                        let sMinX = eseg.x1 < eseg.x2 ? eseg.x1 : eseg.x2;
                        let sMaxX = eseg.x1 > eseg.x2 ? eseg.x1 : eseg.x2;
                        if (px < sMinX - eraserRadius || px > sMaxX + eraserRadius) continue;
                        
                        let sMinY = eseg.y1 < eseg.y2 ? eseg.y1 : eseg.y2;
                        let sMaxY = eseg.y1 > eseg.y2 ? eseg.y1 : eseg.y2;
                        if (py < sMinY - eraserRadius || py > sMaxY + eraserRadius) continue;

                        if (distToSegmentSq(px, py, eseg.x1, eseg.y1, eseg.x2, eseg.y2) <= eraserRadius * eraserRadius) {
                            return true;
                        }
                    }
                }
            }
        }
        return false;
    }

    function isElementFullyErased(h, optHistory, optStep) {
        let history = optHistory !== undefined ? optHistory : win.actionHistory;
        let step = optStep !== undefined ? optStep : win.historyStep;
        var action = history[h];
        if (!action) return true;
        if (action.tool === "eraser") return true;
        
        if (action.isFullyErasedCache !== undefined) {
            return action.isFullyErasedCache;
        }

        if (action.minX === undefined) {
            if (action.type === "stroke") {
                calculateStrokeBounds(action);
            } else if (action.type === "shape") {
                action.minX = Math.min(action.x1, action.x2);
                action.maxX = Math.max(action.x1, action.x2);
                action.minY = Math.min(action.y1, action.y2);
                action.maxY = Math.max(action.y1, action.y2);
            } else if (action.type === "text") {
                let estWidth = win.getTextEstWidth(action.text, action.fontSize, action.fontFamily);
                let estHeight = action.fontSize;
                action.minX = action.x - 12;
                action.maxX = action.x - 12 + estWidth;
                action.minY = action.y - estHeight / 2;
                action.maxY = action.y + estHeight / 2;
            }
        }

        let overlappingErasers = [];
        let margin = 10;
        for (var he = h + 1; he <= step; he++) {
            var act = history[he];
            if (act && act.type === "stroke" && act.tool === "eraser") {
                if (act.minX === undefined) {
                    calculateStrokeBounds(act);
                }
                let overlap = !(act.minX > action.maxX + margin || 
                                act.maxX < action.minX - margin || 
                                act.minY > action.maxY + margin || 
                                act.maxY < action.minY - margin);
                if (overlap) {
                    overlappingErasers.push(he);
                }
            }
        }

        if (overlappingErasers.length === 0) {
            action.isFullyErasedCache = false;
            return false;
        }

        if (action.type === "stroke") {
            if (!action.segments || action.segments.length === 0) {
                action.isFullyErasedCache = true;
                return true;
            }
            for (var s = 0; s < action.segments.length; s++) {
                let seg = action.segments[s];
                if (!isPointErasedByEraserList(seg.x1, seg.y1, overlappingErasers, history) || 
                    !isPointErasedByEraserList(seg.x2, seg.y2, overlappingErasers, history) || 
                    !isPointErasedByEraserList((seg.x1 + seg.x2)/2, (seg.y1 + seg.y2)/2, overlappingErasers, history)) {
                    action.isFullyErasedCache = false;
                    return false;
                }
            }
            action.isFullyErasedCache = true;
            return true;
        }
        
        if (action.type === "shape") {
            if (action.shapeType === "line" || action.shapeType === "arrow") {
                let res = isPointErasedByEraserList(action.x1, action.y1, overlappingErasers, history) && 
                       isPointErasedByEraserList(action.x2, action.y2, overlappingErasers, history) && 
                       isPointErasedByEraserList((action.x1 + action.x2)/2, (action.y1 + action.y2)/2, overlappingErasers, history);
                action.isFullyErasedCache = res;
                return res;
            } else if (action.shapeType === "rectangle") {
                let cx = (action.x1 + action.x2)/2;
                let cy = (action.y1 + action.y2)/2;
                let corners = [
                    {x: action.x1, y: action.y1},
                    {x: action.x2, y: action.y1},
                    {x: action.x2, y: action.y2},
                    {x: action.x1, y: action.y2},
                    {x: cx, y: action.y1},
                    {x: action.x2, y: cy},
                    {x: cx, y: action.y2},
                    {x: action.x1, y: cy}
                ];
                for (var i = 0; i < corners.length; i++) {
                    if (!isPointErasedByEraserList(corners[i].x, corners[i].y, overlappingErasers, history)) {
                        action.isFullyErasedCache = false;
                        return false;
                    }
                }
                action.isFullyErasedCache = true;
                return true;
            } else if (action.shapeType === "circle") {
                let cx = (action.x1 + action.x2) / 2;
                let cy = (action.y1 + action.y2) / 2;
                let rx = Math.abs(action.x2 - action.x1) / 2;
                let ry = Math.abs(action.y2 - action.y1) / 2;
                let pts = [
                    {x: cx, y: cy},
                    {x: cx - rx, y: cy},
                    {x: cx + rx, y: cy},
                    {x: cx, y: cy - ry},
                    {x: cx, y: cy + ry}
                ];
                for (var i = 0; i < pts.length; i++) {
                    if (!isPointErasedByEraserList(pts[i].x, pts[i].y, overlappingErasers, history)) {
                        action.isFullyErasedCache = false;
                        return false;
                    }
                }
                action.isFullyErasedCache = true;
                return true;
            }
        }
        
        if (action.type === "text") {
            let estWidth = win.getTextEstWidth(action.text, action.fontSize, action.fontFamily);
            let estHeight = action.fontSize;
            let x1 = action.x - 12;
            let x2 = x1 + estWidth;
            let y1 = action.y - estHeight / 2;
            let y2 = action.y + estHeight / 2;
            let pts = [
                {x: x1, y: y1}, {x: x2, y: y1}, {x: x2, y: y2}, {x: x1, y: y2},
                {x: (x1+x2)/2, y: (y1+y2)/2}
            ];
            for (var i = 0; i < pts.length; i++) {
                if (!isPointErasedByEraserList(pts[i].x, pts[i].y, overlappingErasers, history)) {
                    action.isFullyErasedCache = false;
                    return false;
                }
            }
            action.isFullyErasedCache = true;
            return true;
        }
        
        action.isFullyErasedCache = false;
        return false;
    }

    function getElementAt(mx, my) {
        for (var h = win.historyStep; h >= 0; h--) {
            var action = win.actionHistory[h];
            if (!action) continue;
            if (action.tool === "eraser") continue;
            if (isElementFullyErased(h)) continue;
            // Compute bounds on demand if they aren't pre-calculated
            if (action.minX === undefined) {
                if (action.type === "stroke") {
                    calculateStrokeBounds(action);
                } else if (action.type === "shape") {
                    action.minX = Math.min(action.x1, action.x2);
                    action.maxX = Math.max(action.x1, action.x2);
                    action.minY = Math.min(action.y1, action.y2);
                    action.maxY = Math.max(action.y1, action.y2);
                } else if (action.type === "text") {
                    let estWidth = win.getTextEstWidth(action.text, action.fontSize, action.fontFamily);
                    let estHeight = action.fontSize;
                    action.minX = action.x - 12;
                    action.maxX = action.x - 12 + estWidth;
                    action.minY = action.y - estHeight / 2;
                    action.maxY = action.y + estHeight / 2;
                }
            }

            // Bounding box check (with 15px tolerance)
            if (action.minX !== undefined) {
                if (mx < action.minX - 15 || mx > action.maxX + 15 ||
                    my < action.minY - 15 || my > action.maxY + 15) {
                    continue; // Skip detailed scan!
                }
            }

            if (isPointErasedByEraser(mx, my, h)) continue;

            if (action.type === "text") {
                return h;
            }
            
            if (action.type === "shape") {
                if (action.shapeType === "line" || action.shapeType === "arrow") {
                    if (distToSegmentSq(mx, my, action.x1, action.y1, action.x2, action.y2) < 225) {
                        return h;
                    }
                } else {
                    return h;
                }
            }
            
            if (action.type === "stroke") {
                let step = Math.max(1, Math.floor(action.segments.length / 50));
                for (var s = 0; s < action.segments.length; s += step) {
                    let seg = action.segments[s];
                    if (distToSegmentSq(mx, my, seg.x1, seg.y1, seg.x2, seg.y2) < 225) {
                        return h;
                    }
                }
            }
        }
        return -1;
    }

    function distToSegmentSq(px, py, x1, y1, x2, y2) {
        let l2 = (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1);
        if (l2 === 0) return (px - x1) * (px - x1) + (py - y1) * (py - y1);
        let t = ((px - x1) * (x2 - x1) + (py - y1) * (y2 - y1)) / l2;
        t = Math.max(0, Math.min(1, t));
        let projX = x1 + t * (x2 - x1);
        let projY = y1 + t * (y2 - y1);
        return (px - projX) * (px - projX) + (py - projY) * (py - projY);
    }

    function simplifyPath(segments, tolerance) {
        if (!segments || segments.length <= 1) return segments;
        
        let result = [];
        let startPt = { x: segments[0].x1, y: segments[0].y1 };
        
        for (let i = 0; i < segments.length; i++) {
            let seg = segments[i];
            let dx = seg.x2 - startPt.x;
            let dy = seg.y2 - startPt.y;
            let dist = Math.sqrt(dx * dx + dy * dy);
            
            if (dist >= tolerance || i === segments.length - 1) {
                result.push({
                    x1: startPt.x,
                    y1: startPt.y,
                    x2: seg.x2,
                    y2: seg.y2
                });
                startPt = { x: seg.x2, y: seg.y2 };
            }
        }
        return result;
    }

    function invalidateFullyErasedCache() {
        if (!win.actionHistory) return;
        for (var i = 0; i < win.actionHistory.length; i++) {
            var action = win.actionHistory[i];
            if (action) {
                action.isFullyErasedCache = undefined;
            }
        }
    }

    // UI Toggle States
    property bool showSizeConfig: false
    property bool showColorPicker: false

    // Infinite Color Picker State
    property real pickHue: 0.74
    property real pickSat: 0.33
    property real pickVal: 0.97
    property color currentColor: Qt.hsva(pickHue, pickSat, pickVal, 1.0)
    
    function selectColor(col) {
        let c = Qt.color(col);
        if (c.hsvHue >= 0) {
            win.pickHue = c.hsvHue;
        }
        win.pickSat = c.hsvSaturation;
        win.pickVal = c.hsvValue;
    }

    onSelectedElementIndexChanged: {
        if (selectedElementIndex !== -1) {
            let action = actionHistory[selectedElementIndex];
            if (action && action.color !== undefined) {
                let c = Qt.color(action.color);
                if (c.hsvHue >= 0) {
                    pickHue = c.hsvHue;
                }
                pickSat = c.hsvSaturation;
                pickVal = c.hsvValue;
            }
        }
    }

    onCurrentColorChanged: {
        if (win.selectedElementIndices.length > 0) {
            let colStr = win.currentColor.toString();
            let changed = false;
            for (let idx of win.selectedElementIndices) {
                let action = win.actionHistory[idx];
                if (action && action.color !== undefined && action.color !== colStr) {
                    action.color = colStr;
                    changed = true;
                }
            }
            if (changed) {
                win.triggerReplay();
                previewCanvas.requestPaint();
            }
        }
    }
    
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
    property real minZoom: 0.05
    property real maxZoom: 10.0
    property real worldSize: 3072 

    // =========================================================
    // --- HISTORY SYSTEM (UNDO / REDO)
    // =========================================================
    property var actionHistory: []
    property int historyStep: -1
    property bool isCommittingAction: false
    property var jsState: ({ "history": [], "step": -1 })
    onActionHistoryChanged: {
        if (!win.isCommittingAction && !win.isCommittingEraser) {
            win.invalidateFullyErasedCache();
        }
    }
    onHistoryStepChanged: {
        if (!win.isCommittingAction) {
            win.invalidateFullyErasedCache();
        }
    }
    property int maxHistory: 50000
    property var currentAction: null
    property bool isCommittingEraser: false

    function calculateStrokeBounds(action) {
        let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
        for (var s = 0; s < action.segments.length; s++) {
            let seg = action.segments[s];
            if (seg.x1 < minX) minX = seg.x1;
            if (seg.x2 < minX) minX = seg.x2;
            if (seg.x1 > maxX) maxX = seg.x1;
            if (seg.x2 > maxX) maxX = seg.x2;
            if (seg.y1 < minY) minY = seg.y1;
            if (seg.y2 < minY) minY = seg.y2;
            if (seg.y1 > maxY) maxY = seg.y1;
            if (seg.y2 > maxY) maxY = seg.y2;
        }
        action.minX = minX;
        action.maxX = maxX;
        action.minY = minY;
        action.maxY = maxY;
    }

    function splitStrokeAction(action, maxSegmentsPerChunk) {
        if (!action.segments || action.segments.length <= maxSegmentsPerChunk) {
            calculateStrokeBounds(action);
            return [action];
        }
        
        let chunks = [];
        let undoGroupId = Date.now() + "_" + Math.random();
        
        for (var i = 0; i < action.segments.length; i += maxSegmentsPerChunk) {
            let chunkSegments = action.segments.slice(i, i + maxSegmentsPerChunk);
            let chunkAction = {
                type: action.type,
                tool: action.tool,
                color: action.color,
                penSize: action.penSize,
                segments: chunkSegments,
                undoGroup: undoGroupId
            };
            calculateStrokeBounds(chunkAction);
            chunks.push(chunkAction);
        }
        return chunks;
    }

    function commitAction(action) {
        let actionsToCommit = [action];
        
        if (action.type === "stroke") {
            if (action.tool === "eraser") {
                action.segments = win.simplifyPath(action.segments, 6.0);
                actionsToCommit = splitStrokeAction(action, 50);
            } else {
                action.segments = win.simplifyPath(action.segments, 2.0);
                calculateStrokeBounds(action);
            }
        } else if (action.type === "shape") {
            action.minX = Math.min(action.x1, action.x2);
            action.maxX = Math.max(action.x1, action.x2);
            action.minY = Math.min(action.y1, action.y2);
            action.maxY = Math.max(action.y1, action.y2);
        } else if (action.type === "text") {
            let estWidth = win.getTextEstWidth(action.text, action.fontSize, action.fontFamily);
            let estHeight = action.fontSize;
            action.minX = action.x - 12;
            action.maxX = action.x - 12 + estWidth;
            action.minY = action.y - estHeight / 2;
            action.maxY = action.y + estHeight / 2;
        }

        if (action.tool === "eraser") {
            win.isCommittingEraser = true;
        }

        var newHistory = win.actionHistory.slice(0, win.historyStep + 1);
        for (let k = 0; k < actionsToCommit.length; k++) {
            newHistory.push(actionsToCommit[k]);
        }
        
        if (newHistory.length > win.maxHistory) {
            newHistory.shift();
        }
        
        win.isCommittingAction = true;
        win.actionHistory = newHistory;
        win.historyStep = win.actionHistory.length - 1;
        win.isCommittingAction = false;
        
        win.jsState.history = win.actionHistory;
        win.jsState.step = win.historyStep;

        if (action.tool === "eraser") {
            let margin = 10;
            let eraserIdx = win.historyStep;
            for (let k = 0; k < actionsToCommit.length; k++) {
                let chunkEraser = actionsToCommit[k];
                let limitIdx = eraserIdx - (actionsToCommit.length - 1 - k);
                for (var i = 0; i < limitIdx; i++) {
                    var prevAction = win.actionHistory[i];
                    if (prevAction && prevAction.tool !== "eraser" && prevAction.type !== "clear" && prevAction.type !== "fill_bg") {
                        let overlap = !(chunkEraser.minX > prevAction.maxX + margin || 
                                        chunkEraser.maxX < prevAction.minX - margin || 
                                        chunkEraser.minY > prevAction.maxY + margin || 
                                        chunkEraser.maxY < prevAction.minY - margin);
                        if (overlap) {
                            prevAction.isFullyErasedCache = undefined;
                        }
                    }
                }
            }
            win.isCommittingEraser = false;
        }
    }

    function drawLocalErasers(ctx, action) {}

    function isPointOverUI(sceneX, sceneY) {
        if (typeof colorPickerPopup !== "undefined" && colorPickerPopup.visible && isPointOverItem(colorPickerPopup, sceneX, sceneY)) return true;
        if (typeof sizeConfigPopup !== "undefined" && sizeConfigPopup.visible && isPointOverItem(sizeConfigPopup, sceneX, sceneY)) return true;
        if (typeof textStyleModal !== "undefined" && textStyleModal.visible && isPointOverItem(textStyleModal, sceneX, sceneY)) return true;
        if (typeof toolbar !== "undefined" && toolbar.visible && isPointOverItem(toolbar, sceneX, sceneY)) return true;
        if (typeof topActionsLayout !== "undefined" && topActionsLayout.visible && isPointOverItem(topActionsLayout, sceneX, sceneY)) return true;
        return false;
    }

    function isPointOverItem(item, sceneX, sceneY) {
        if (!item || !item.visible || item.opacity === 0) return false;
        let localPt = item.mapFromItem(null, sceneX, sceneY);
        return (localPt.x >= 0 && localPt.x <= item.width && localPt.y >= 0 && localPt.y <= item.height);
    }

    function undo() {
        if (win.historyStep >= 0) {
            win.selectedElementIndices = [];
            win.grabbedElementIndex = -1;
            win.resizeGrabbed = false;
            win.rotateGrabbed = false;
            
            let currentGroup = win.actionHistory[win.historyStep].undoGroup;
            if (currentGroup !== undefined) {
                while (win.historyStep >= 0 && win.actionHistory[win.historyStep].undoGroup === currentGroup) {
                    win.historyStep--;
                }
            } else {
                win.historyStep--;
            }
            
            win.jsState.step = win.historyStep;
            win.updateSelectionBounds();
            triggerReplay();
            previewCanvas.requestPaint();
        }
    }

    function redo() {
        if (win.historyStep < win.actionHistory.length - 1) {
            win.selectedElementIndices = [];
            win.grabbedElementIndex = -1;
            win.resizeGrabbed = false;
            win.rotateGrabbed = false;
            
            let nextStep = win.historyStep + 1;
            let nextGroup = win.actionHistory[nextStep].undoGroup;
            if (nextGroup !== undefined) {
                while (win.historyStep < win.actionHistory.length - 1 && win.actionHistory[win.historyStep + 1].undoGroup === nextGroup) {
                    win.historyStep++;
                }
            } else {
                win.historyStep++;
            }
            
            win.jsState.step = win.historyStep;
            win.updateSelectionBounds();
            triggerReplay();
            previewCanvas.requestPaint();
        }
    }

    function triggerReplay() {
        drawCanvas._replayPending = true;
        drawCanvas.requestPaint();
    }

    // Shortcuts for Undo/Redo / Fullscreen
    Shortcut { enabled: win.visible; sequence: "Ctrl+Z"; onActivated: win.undo() }
    Shortcut { enabled: win.visible; sequence: "Ctrl+Shift+Z"; onActivated: win.redo() }
    Shortcut { enabled: win.visible; sequence: "F11"; onActivated: win.isFullScreen = !win.isFullScreen }
    Shortcut {
        enabled: win.visible && win.currentTool === "mouse" && !activeTextEditor.visible
        sequence: "Ctrl+C"
        onActivated: win.copySelectedElement()
    }
    Shortcut {
        enabled: win.visible && win.currentTool === "mouse" && !activeTextEditor.visible
        sequence: "Ctrl+V"
        onActivated: win.pasteCopiedElement()
    }
    Shortcut {
        enabled: win.visible && win.currentTool === "mouse" && !activeTextEditor.visible
        sequence: "Delete"
        onActivated: win.deleteSelectedElements()
    }
    Shortcut {
        enabled: win.visible && win.currentTool === "mouse" && !activeTextEditor.visible
        sequence: "BackSpace"
        onActivated: win.deleteSelectedElements()
    }

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
        id: rootRectangle
        anchors.fill: parent
        color: win.solidBgColor
        radius: win.isFullScreen ? 0 : Tokens.rounding.large
        border.width: win.isFullScreen ? 0 : 1
        clip: true
        
        PointHandler {
            id: globalReleaseMonitor
            target: null
            onActiveChanged: {
                if (!active) {
                    win.isCursorOverUIOnPress = false;
                }
            }
        }

        // =========================================================
        // --- CAMERA RIG (Handles viewport size, rotation, gestures)
        // =========================================================
        Item {
            id: cameraRig
            anchors.fill: parent
            clip: true

            // Viewport Void Background (visible when zoomed out or panned to the edges)
            Rectangle {
                anchors.fill: parent
                color: Qt.darker(win.solidBgColor, 1.1)
                z: -3
            }

            function zoomBy(factor) {
                zoomContainer.scale = Math.max(win.minZoom, Math.min(zoomContainer.scale * factor, win.maxZoom));
            }

            PinchHandler {
                id: canvasPinchHandler
                target: zoomContainer
                minimumScale: win.minZoom
                maximumScale: win.maxZoom
                onActiveChanged: {
                    if (!active) {
                        win.triggerReplay();
                    }
                }
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

                // The Whiteboard Paper Background & Border
                Rectangle {
                    anchors.fill: parent
                    color: win.solidBgColor
                    border.color: win.panelBorderColor
                    border.width: 1.5
                    radius: 8
                    z: -2
                }

                // Grid dots inside the Whiteboard area (pans and scales with the canvas)
                Image {
                    anchors.fill: parent
                    fillMode: Image.Tile
                    opacity: 0.15
                    z: -1
                    
                    property real dotRadius: 1.2
                    property real dotSpacing: 12
                    property color dotC: win.baseTextColor
                    
                    source: `data:image/svg+xml;utf8,<svg width='${dotSpacing}' height='${dotSpacing}' xmlns='http://www.w3.org/2000/svg'><circle cx='${dotSpacing/2}' cy='${dotSpacing/2}' r='${dotRadius}' fill='rgb(${dotC.r*255},${dotC.g*255},${dotC.b*255})' /></svg>`
                    sourceSize.width: dotSpacing
                    sourceSize.height: dotSpacing
                }

                DragHandler {
                    id: canvasPanHandler
                    target: zoomContainer
                    enabled: win.currentTool === "mouse" && win.grabbedElementIndex === -1 && !win.resizeGrabbed && !win.rotateGrabbed && !win.isCursorOverUIOnPress
                    acceptedButtons: Qt.LeftButton
                    onActiveChanged: {
                        if (active) {
                            let pressPt = centroid.scenePressPosition;
                            if (win.isPointOverUI(pressPt.x, pressPt.y)) {
                                win.isCursorOverUIOnPress = true;
                            }
                        } else {
                            win.triggerReplay();
                        }
                    }
                }

                // =========================================================
                // --- SHAPE PREVIEW LAYER ---
                // =========================================================
                Item {
                    id: shapePreview
                    anchors.fill: parent
                    z: 2
                    visible: true
                    enabled: false
                    
                    property string shapeType: ""
                    property real startX: 0
                    property real startY: 0
                    property real curX: 0
                    property real curY: 0

                    Canvas {
                        id: previewCanvas
                        anchors.fill: parent
                        renderTarget: Canvas.Image
                        
                        function drawAction(ctx, action) {
                            if (!action) return;
                            if (action.type === "text") {
                                ctx.globalCompositeOperation = "source-over";
                                ctx.fillStyle = action.color;
                                let weight = (action.isBold === undefined || action.isBold) ? "bold" : "normal";
                                let style = action.isItalic ? "italic" : "normal";
                                let family = "Inter, system-ui, sans-serif";
                                if (action.fontFamily === "serif") family = "Georgia, serif";
                                else if (action.fontFamily === "monospace") family = "JetBrains Mono, monospace";
                                else if (action.fontFamily === "cursive") family = "Caveat, cursive";
                                ctx.font = style + " " + weight + " " + action.fontSize + "px " + family;
                                ctx.textBaseline = "middle";
                                ctx.fillText(action.text, action.x, action.y);
                            } else if (action.type === "shape") {
                                ctx.beginPath();
                                ctx.lineCap = "round";
                                ctx.lineJoin = "round";
                                ctx.globalCompositeOperation = "source-over";
                                ctx.strokeStyle = action.color;
                                ctx.lineWidth = action.penSize;
                                ctx.globalAlpha = 1.0;
                                
                                if (action.shapeType === "rectangle") {
                                    let rx = Math.min(action.x1, action.x2);
                                    let ry = Math.min(action.y1, action.y2);
                                    let rw = Math.abs(action.x2 - action.x1);
                                    let rh = Math.abs(action.y2 - action.y1);
                                    ctx.rect(rx, ry, rw, rh);
                                    ctx.stroke();
                                } else if (action.shapeType === "circle") {
                                    let rx = Math.min(action.x1, action.x2);
                                    let ry = Math.min(action.y1, action.y2);
                                    let rw = Math.abs(action.x2 - action.x1);
                                    let rh = Math.abs(action.y2 - action.y1);
                                    ctx.ellipse(rx, ry, rw, rh);
                                    ctx.stroke();
                                } else if (action.shapeType === "line") {
                                    ctx.moveTo(action.x1, action.y1);
                                    ctx.lineTo(action.x2, action.y2);
                                    ctx.stroke();
                                } else if (action.shapeType === "arrow") {
                                    win.drawArrow(ctx, action.x1, action.y1, action.x2, action.y2, action.penSize, action.color);
                                }
                            } else if (action.type === "stroke") {
                                if (action.tool === "brush") {
                                    drawCanvas.renderBrushLine(ctx, action, false);
                                } else {
                                    ctx.beginPath();
                                    ctx.lineCap = "round";
                                    ctx.lineJoin = "round";
                                    ctx.globalCompositeOperation = "source-over";
                                    ctx.strokeStyle = action.color;
                                    ctx.lineWidth = action.penSize;
                                    ctx.globalAlpha = 1.0;
                                    
                                    if (action.segments && action.segments.length > 0) {
                                        ctx.moveTo(action.segments[0].x1, action.segments[0].y1);
                                        for (var k = 0; k < action.segments.length; k++) {
                                            ctx.lineTo(action.segments[k].x2, action.segments[k].y2);
                                        }
                                        ctx.stroke();
                                    }
                                }
                            }
                            win.drawLocalErasers(ctx, action);
                        }
                        
                        function drawSelectionBox(ctx, x1, x2, y1, y2, rotation, drawHandles) {
                            if (drawHandles === undefined) drawHandles = true;
                            let borderOffset = 4 / zoomContainer.scale;
                            let handleSize = 8 / zoomContainer.scale;
                            
                            let bx1 = x1 - borderOffset;
                            let bx2 = x2 + borderOffset;
                            let by1 = y1 - borderOffset;
                            let by2 = y2 + borderOffset;
                            
                            ctx.save();
                            if (rotation && rotation !== 0) {
                                let cx = (x1 + x2) / 2;
                                let cy = (y1 + y2) / 2;
                                ctx.translate(cx, cy);
                                ctx.rotate(rotation);
                                ctx.translate(-cx, -cy);
                            }
                            
                            // Draw bounding box
                            ctx.beginPath();
                            ctx.strokeStyle = "#3b82f6"; // selection blue
                            ctx.lineWidth = 1.5 / zoomContainer.scale;
                            ctx.setLineDash([4 / zoomContainer.scale, 4 / zoomContainer.scale]);
                            ctx.rect(bx1, by1, bx2 - bx1, by2 - by1);
                            ctx.stroke();
                            ctx.setLineDash([]); // Reset dash
                            
                            // Draw handles
                            if (drawHandles) {
                                ctx.fillStyle = "white";
                                ctx.strokeStyle = "#3b82f6";
                                ctx.lineWidth = 2 / zoomContainer.scale;
                                
                                function drawHandle(hx, hy) {
                                    ctx.beginPath();
                                    ctx.arc(hx, hy, handleSize / 2, 0, 2 * Math.PI);
                                    ctx.fill();
                                    ctx.stroke();
                                }
                                
                                drawHandle(bx1, by1); // TL
                                drawHandle(bx2, by1); // TR
                                drawHandle(bx1, by2); // BL
                                drawHandle(bx2, by2); // BR
                                
                                // Draw rotation handle line and circle
                                let rxHandleX = (bx1 + bx2) / 2;
                                let rxHandleY = by1 - 24 / zoomContainer.scale;
                                
                                ctx.beginPath();
                                ctx.strokeStyle = "#3b82f6";
                                ctx.lineWidth = 1.5 / zoomContainer.scale;
                                ctx.moveTo(rxHandleX, by1);
                                ctx.lineTo(rxHandleX, rxHandleY);
                                ctx.stroke();
                                
                                ctx.fillStyle = "white";
                                ctx.strokeStyle = "#10b981"; // nice emerald green for rotation!
                                ctx.lineWidth = 2 / zoomContainer.scale;
                                ctx.beginPath();
                                ctx.arc(rxHandleX, rxHandleY, handleSize / 2, 0, 2 * Math.PI);
                                ctx.fill();
                                ctx.stroke();
                            }
                            
                            ctx.restore();
                        }

                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            if (shapePreview.shapeType === "" && win.grabbedElementIndex === -1 && win.selectedElementIndex === -1 && !win.resizeGrabbed && !win.rotateGrabbed) return;
                            
                            // 1. Draw shape preview
                            if (shapePreview.shapeType !== "") {
                                ctx.strokeStyle = win.currentColor;
                                ctx.lineWidth = win.actualToolSize;
                                ctx.lineCap = "round";
                                ctx.lineJoin = "round";
                                ctx.beginPath();
                                
                                let x1 = shapePreview.startX;
                                let y1 = shapePreview.startY;
                                let x2 = shapePreview.curX;
                                let y2 = shapePreview.curY;
                                
                                if (shapePreview.shapeType === "rectangle") {
                                    let rx = Math.min(x1, x2);
                                    let ry = Math.min(y1, y2);
                                    let rw = Math.abs(x2 - x1);
                                    let rh = Math.abs(y2 - y1);
                                    ctx.rect(rx, ry, rw, rh);
                                    ctx.stroke();
                                } else if (shapePreview.shapeType === "circle") {
                                    let rx = Math.min(x1, x2);
                                    let ry = Math.min(y1, y2);
                                    let rw = Math.abs(x2 - x1);
                                    let rh = Math.abs(y2 - y1);
                                    ctx.ellipse(rx, ry, rw, rh);
                                    ctx.stroke();
                                } else if (shapePreview.shapeType === "line") {
                                    ctx.moveTo(x1, y1);
                                    ctx.lineTo(x2, y2);
                                    ctx.stroke();
                                } else if (shapePreview.shapeType === "arrow") {
                                    win.drawArrow(ctx, x1, y1, x2, y2, win.actualToolSize, win.currentColor);
                                }
                            }
                            
                            // 2. Draw grabbed elements with offset (when moving)
                            if (win.grabbedElementIndex !== -1 && !win.resizeGrabbed && !win.rotateGrabbed) {
                                ctx.save();
                                for (let i = 0; i < win.selectedElementIndices.length; i++) {
                                    let idx = win.selectedElementIndices[i];
                                    let action = win.actionHistory[idx];
                                    if (action) {
                                        ctx.save();
                                        let cx = (action.minX + action.maxX) / 2;
                                        let cy = (action.minY + action.maxY) / 2;
                                        
                                        ctx.translate(win.grabbedElementDx, win.grabbedElementDy);
                                        if (action.rotation && action.rotation !== 0) {
                                            ctx.translate(cx, cy);
                                            ctx.rotate(action.rotation);
                                            ctx.translate(-cx, -cy);
                                        }
                                        drawAction(ctx, action);
                                        ctx.restore();
                                    }
                                }
                                drawSelectionBox(ctx, win.selectionMinX + win.grabbedElementDx, win.selectionMaxX + win.grabbedElementDx, win.selectionMinY + win.grabbedElementDy, win.selectionMaxY + win.grabbedElementDy, 0, false);
                                ctx.restore();
                            }
                            
                            // 3. Draw resizing elements
                            if (win.resizeGrabbed && win.actionsBeforeResize.length > 0) {
                                let dx = win.grabbedElementDx;
                                let dy = win.grabbedElementDy;
                                
                                let rot = 0;
                                let ldx = dx;
                                let ldy = dy;
                                
                                let minX = win.grabbedMinX;
                                let maxX = win.grabbedMaxX;
                                let minY = win.grabbedMinY;
                                let maxY = win.grabbedMaxY;
                                
                                if (win.resizeHandle === "BR") {
                                    maxX = Math.max(minX + 5, win.grabbedMaxX + ldx);
                                    maxY = Math.max(minY + 5, win.grabbedMaxY + ldy);
                                } else if (win.resizeHandle === "TL") {
                                    minX = Math.min(maxX - 5, win.grabbedMinX + ldx);
                                    minY = Math.min(maxY - 5, win.grabbedMinY + ldy);
                                } else if (win.resizeHandle === "TR") {
                                    maxX = Math.max(minX + 5, win.grabbedMaxX + ldx);
                                    minY = Math.min(maxY - 5, win.grabbedMinY + ldy);
                                } else if (win.resizeHandle === "BL") {
                                    minX = Math.min(maxX - 5, win.grabbedMinX + ldx);
                                    maxY = Math.max(minY + 5, win.grabbedMaxY + ldy);
                                }
                                
                                let W0 = win.grabbedMaxX - win.grabbedMinX;
                                let H0 = win.grabbedMaxY - win.grabbedMinY;
                                if (W0 === 0) W0 = 1;
                                if (H0 === 0) H0 = 1;
                                
                                let scaleX = (maxX - minX) / W0;
                                let scaleY = (maxY - minY) / H0;
                                
                                let refX = win.grabbedMinX;
                                let refY = win.grabbedMinY;
                                if (win.resizeHandle === "TL") { refX = win.grabbedMaxX; refY = win.grabbedMaxY; }
                                else if (win.resizeHandle === "TR") { refX = win.grabbedMinX; refY = win.grabbedMaxY; }
                                else if (win.resizeHandle === "BL") { refX = win.grabbedMaxX; refY = win.grabbedMinY; }
                                
                                ctx.save();
                                for (let i = 0; i < win.actionsBeforeResize.length; i++) {
                                    let tempAction = cloneAction(win.actionsBeforeResize[i]);
                                    scaleAction(tempAction, scaleX, scaleY, refX, refY);
                                    
                                    ctx.save();
                                    if (tempAction.rotation && tempAction.rotation !== 0) {
                                        let cx = (tempAction.minX + tempAction.maxX) / 2;
                                        let cy = (tempAction.minY + tempAction.maxY) / 2;
                                        ctx.translate(cx, cy);
                                        ctx.rotate(tempAction.rotation);
                                        ctx.translate(-cx, -cy);
                                    }
                                    drawAction(ctx, tempAction);
                                    ctx.restore();
                                }
                                drawSelectionBox(ctx, minX, maxX, minY, maxY, 0, true);
                                ctx.restore();
                            }
                            
                            // 3.5 Draw rotating elements
                            if (win.rotateGrabbed && win.selectedElementIndices.length > 0) {
                                let cx = (win.selectionMinX + win.selectionMaxX) / 2;
                                let cy = (win.selectionMinY + win.selectionMaxY) / 2;
                                let delta = win.grabbedElementRotationDelta;
                                
                                ctx.save();
                                for (let i = 0; i < win.selectedElementIndices.length; i++) {
                                    let idx = win.selectedElementIndices[i];
                                    let action = win.actionHistory[idx];
                                    if (action) {
                                        ctx.save();
                                        let tempAction = cloneAction(action);
                                        rotateAction(tempAction, delta, cx, cy);
                                        
                                        if (tempAction.rotation && tempAction.rotation !== 0) {
                                            let acx = (tempAction.minX + tempAction.maxX) / 2;
                                            let acy = (tempAction.minY + tempAction.maxY) / 2;
                                            ctx.translate(acx, acy);
                                            ctx.rotate(tempAction.rotation);
                                            ctx.translate(-acx, -acy);
                                        }
                                        drawAction(ctx, tempAction);
                                        ctx.restore();
                                    }
                                }
                                drawSelectionBox(ctx, win.selectionMinX, win.selectionMaxX, win.selectionMinY, win.selectionMaxY, delta, true);
                                ctx.restore();
                            }
                            
                            // 4. Draw selection box around selected elements (static hover/selected state)
                            if (win.selectedElementIndices.length > 0 && win.grabbedElementIndex === -1 && !win.resizeGrabbed && !win.rotateGrabbed) {
                                if (win.selectedElementIndices.length === 1) {
                                    let action = win.actionHistory[win.selectedElementIndices[0]];
                                    if (action) {
                                        drawSelectionBox(ctx, action.minX, action.maxX, action.minY, action.maxY, action.rotation, true);
                                    }
                                } else {
                                    for (let i = 0; i < win.selectedElementIndices.length; i++) {
                                        let idx = win.selectedElementIndices[i];
                                        let action = win.actionHistory[idx];
                                        if (action) {
                                            drawSelectionBox(ctx, action.minX, action.maxX, action.minY, action.maxY, action.rotation, false);
                                        }
                                    }
                                    drawSelectionBox(ctx, win.selectionMinX, win.selectionMaxX, win.selectionMinY, win.selectionMaxY, 0, true);
                                }
                            }
                        }
                    }
                }

                // =========================================================
                // --- TEXT EDITOR INTERFACE ---
                // =========================================================
                TextField {
                    id: activeTextEditor
                    z: 3
                    visible: false
                    
                    color: win.currentColor
                    font.pixelSize: Math.max(12, 16 + win.currentSizeRatio * 48)
                    font.bold: win.activeTextIsBold
                    font.italic: win.activeTextIsItalic
                    font.family: {
                        if (win.activeTextFontFamily === "sans-serif") return "Inter, sans-serif";
                        if (win.activeTextFontFamily === "serif") return "Georgia, serif";
                        if (win.activeTextFontFamily === "monospace") return "JetBrains Mono, monospace";
                        if (win.activeTextFontFamily === "cursive") return "Caveat, cursive";
                        return "sans-serif";
                    }
                    
                    verticalAlignment: TextInput.AlignVCenter
                    leftPadding: 12
                    rightPadding: 12
                    
                    width: Math.max(150, textMetrics.width + 32)
                    height: font.pixelSize * 1.4 + 16
                    
                    background: Rectangle {
                        color: Qt.rgba(0, 0, 0, 0.2)
                        border.color: win.currentColor
                        border.width: 2
                        radius: Tokens.rounding.small
                    }
                    
                    TextMetrics {
                        id: textMetrics
                        font: activeTextEditor.font
                        text: activeTextEditor.text
                    }

                    onVisibleChanged: {
                        if (visible) {
                            forceActiveFocus();
                        }
                    }

                    Keys.onEscapePressed: {
                        cancelEdit();
                    }

                    onActiveFocusChanged: {
                        if (!activeFocus && visible) {
                            commitText();
                        }
                    }

                    onAccepted: {
                        commitText();
                    }

                    function cancelEdit() {
                        win.editingTextIndex = -1;
                        text = "";
                        visible = false;
                        win.triggerReplay();
                    }

                    function commitText() {
                        if (text.trim().length > 0) {
                            if (win.editingTextIndex !== -1) {
                                let action = win.actionHistory[win.editingTextIndex];
                                action.text = text;
                                action.color = win.currentColor.toString();
                                action.fontSize = font.pixelSize;
                                action.fontFamily = win.activeTextFontFamily;
                                action.isBold = win.activeTextIsBold;
                                action.isItalic = win.activeTextIsItalic;
                                win.editingTextIndex = -1;
                            } else {
                                let action = {
                                    type: "text",
                                    x: x + 12,
                                    y: y + height / 2,
                                    text: text,
                                    color: win.currentColor.toString(),
                                    fontSize: font.pixelSize,
                                    fontFamily: win.activeTextFontFamily,
                                    isBold: win.activeTextIsBold,
                                    isItalic: win.activeTextIsItalic
                                };
                                win.commitAction(action);
                            }
                            win.triggerReplay();
                        } else {
                            if (win.editingTextIndex !== -1) {
                                let newHistory = win.actionHistory.slice();
                                newHistory.splice(win.editingTextIndex, 1);
                                win.actionHistory = newHistory;
                                win.historyStep--;
                                win.jsState.history = win.actionHistory;
                                win.jsState.step = win.historyStep;
                                win.editingTextIndex = -1;
                                win.triggerReplay();
                            }
                        }
                        text = "";
                        visible = false;
                    }
                }

                // =========================================================
                // --- TEXT STYLING TOOLBAR MODAL ---
                // =========================================================
                Rectangle {
                    id: textStyleModal
                    z: 20
                    parent: cameraRig
                    
                    MouseArea {
                        anchors.fill: parent
                        onPressed: (mouse) => { mouse.accepted = true; }
                    }
                    
                    width: 204
                    height: 44
                    radius: Tokens.rounding.medium
                    color: win.panelBgColor
                    border.width: 1
                    border.color: win.panelBorderColor
                    
                    x: {
                        let editorScreenX = zoomContainer.x + activeTextEditor.x * zoomContainer.scale;
                        let editorScreenWidth = activeTextEditor.width * zoomContainer.scale;
                        let targetX = editorScreenX + (editorScreenWidth - width) / 2;
                        return Math.max(8, Math.min(targetX, cameraRig.width - width - 8));
                    }
                    y: {
                        let editorScreenY = zoomContainer.y + activeTextEditor.y * zoomContainer.scale;
                        let targetY = editorScreenY - height - 8;
                        if (targetY < 8) {
                            let editorScreenHeight = activeTextEditor.height * zoomContainer.scale;
                            return editorScreenY + editorScreenHeight + 8;
                        }
                        return targetY;
                    }
                    
                    visible: opacity > 0.0
                    opacity: activeTextEditor.visible ? 1.0 : 0.0
                    scale: activeTextEditor.visible ? 1.0 : 0.95
                    
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
                    
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 2
                        
                        Row {
                            spacing: 1
                            Layout.fillWidth: true
                            
                            // Sans
                            Rectangle {
                                id: btnSans
                                width: 28; height: 28; radius: Tokens.rounding.small
                                color: win.activeTextFontFamily === "sans-serif" ? Colours.palette.m3primaryContainer : (mouseAreaSans.containsMouse ? Colours.palette.m3surfaceVariant : "transparent")
                                Text {
                                    anchors.centerIn: parent
                                    text: "Ag"
                                    font.family: "Inter, sans-serif"
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: win.activeTextFontFamily === "sans-serif" ? Colours.palette.m3onPrimaryContainer : win.baseTextColor
                                }
                                MouseArea {
                                    id: mouseAreaSans
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onClicked: win.activeTextFontFamily = "sans-serif"
                                }
                            }
                            
                            // Serif
                            Rectangle {
                                id: btnSerif
                                width: 28; height: 28; radius: Tokens.rounding.small
                                color: win.activeTextFontFamily === "serif" ? Colours.palette.m3primaryContainer : (mouseAreaSerif.containsMouse ? Colours.palette.m3surfaceVariant : "transparent")
                                Text {
                                    anchors.centerIn: parent
                                    text: "Ag"
                                    font.family: "Georgia, serif"
                                    font.bold: true
                                    font.pixelSize: 11
                                    color: win.activeTextFontFamily === "serif" ? Colours.palette.m3onPrimaryContainer : win.baseTextColor
                                }
                                MouseArea {
                                    id: mouseAreaSerif
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onClicked: win.activeTextFontFamily = "serif"
                                }
                            }
                            
                            // Mono
                            Rectangle {
                                id: btnMono
                                width: 28; height: 28; radius: Tokens.rounding.small
                                color: win.activeTextFontFamily === "monospace" ? Colours.palette.m3primaryContainer : (mouseAreaMono.containsMouse ? Colours.palette.m3surfaceVariant : "transparent")
                                Text {
                                    anchors.centerIn: parent
                                    text: "Ag"
                                    font.family: "monospace"
                                    font.bold: true
                                    font.pixelSize: 10
                                    color: win.activeTextFontFamily === "monospace" ? Colours.palette.m3onPrimaryContainer : win.baseTextColor
                                }
                                MouseArea {
                                    id: mouseAreaMono
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onClicked: win.activeTextFontFamily = "monospace"
                                }
                            }
                            
                            // Cursive
                            Rectangle {
                                id: btnCursive
                                width: 28; height: 28; radius: Tokens.rounding.small
                                color: win.activeTextFontFamily === "cursive" ? Colours.palette.m3primaryContainer : (mouseAreaCursive.containsMouse ? Colours.palette.m3surfaceVariant : "transparent")
                                Text {
                                    anchors.centerIn: parent
                                    text: "Ag"
                                    font.family: "cursive"
                                    font.bold: true
                                    font.pixelSize: 12
                                    color: win.activeTextFontFamily === "cursive" ? Colours.palette.m3onPrimaryContainer : win.baseTextColor
                                }
                                MouseArea {
                                    id: mouseAreaCursive
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onClicked: win.activeTextFontFamily = "cursive"
                                }
                            }
                        }
                        
                        Rectangle {
                            width: 1
                            height: 20
                            color: win.panelBorderColor
                        }
                        
                        Item {
                            width: 28; height: 28
                            Rectangle {
                                id: btnBoldBg
                                anchors.fill: parent; radius: Tokens.rounding.small; z: -1
                                color: win.activeTextIsBold ? Colours.palette.m3primaryContainer : (mouseAreaBold.containsMouse ? Colours.palette.m3surfaceVariant : "transparent")
                            }
                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "format_bold"
                                color: win.activeTextIsBold ? Colours.palette.m3onPrimaryContainer : win.baseTextColor
                            }
                            MouseArea {
                                id: mouseAreaBold
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: win.activeTextIsBold = !win.activeTextIsBold
                            }
                        }
                        
                        Item {
                            width: 28; height: 28
                            Rectangle {
                                id: btnItalicBg
                                anchors.fill: parent; radius: Tokens.rounding.small; z: -1
                                color: win.activeTextIsItalic ? Colours.palette.m3primaryContainer : (mouseAreaItalic.containsMouse ? Colours.palette.m3surfaceVariant : "transparent")
                            }
                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "format_italic"
                                color: win.activeTextIsItalic ? Colours.palette.m3onPrimaryContainer : win.baseTextColor
                            }
                            MouseArea {
                                id: mouseAreaItalic
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: win.activeTextIsItalic = !win.activeTextIsItalic
                            }
                        }
                    }
                }

                // --- HIGH-PERFORMANCE SYNCHRONOUS CANVAS ---
                Canvas {
                    id: drawCanvas
                    anchors.fill: parent
                    z: 1
                    
                    renderTarget: Canvas.Image
                    
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
                            let hStep = win.jsState.step;
                            let hHistory = win.jsState.history;
                            for (var h = 0; h <= hStep; h++) {
                                var action = hHistory[h];
                                if (!action) continue;

                                if (action.type === "clear") {
                                    ctx.clearRect(0, 0, width, height);
                                } else if (action.type === "fill_bg") {
                                    ctx.globalCompositeOperation = "destination-over";
                                    ctx.fillStyle = action.color;
                                    ctx.fillRect(0, 0, width, height);
                                    ctx.globalCompositeOperation = "source-over";
                                } else {
                                    if (action.tool !== "eraser" && win.isElementFullyErased(h, hHistory, hStep)) continue;

                                    if (action.type === "stroke") {
                                        if (action.tool === "eraser") {
                                            // Check if this eraser is useful
                                            let isEraserUseful = false;
                                            for (let j = 0; j < h; j++) {
                                                let prevAct = hHistory[j];
                                                if (prevAct && prevAct.tool !== "eraser" && prevAct.type !== "clear" && prevAct.type !== "fill_bg") {
                                                    if (!win.isElementFullyErased(j, hHistory, hStep)) {
                                                        if (action.minX !== undefined && prevAct.minX !== undefined) {
                                                            let margin = 10;
                                                            let overlap = !(action.minX > prevAct.maxX + margin || 
                                                                            action.maxX < prevAct.minX - margin || 
                                                                            action.minY > prevAct.maxY + margin || 
                                                                            action.maxY < prevAct.minY - margin);
                                                            if (overlap) {
                                                                isEraserUseful = true;
                                                                break;
                                                            }
                                                        } else {
                                                            isEraserUseful = true;
                                                            break;
                                                        }
                                                    }
                                                }
                                            }
                                            if (!isEraserUseful) {
                                                continue; // Skip this eraser completely!
                                            }

                                            ctx.save();
                                            applyToolStyle(ctx, "eraser", "rgba(0,0,0,1)", action.penSize);
                                            if (action.segments && action.segments.length > 0) {
                                                ctx.beginPath();
                                                ctx.moveTo(action.segments[0].x1, action.segments[0].y1);
                                                for (var k = 0; k < action.segments.length; k++) {
                                                    ctx.lineTo(action.segments[k].x2, action.segments[k].y2);
                                                }
                                                ctx.stroke();
                                            }
                                            ctx.restore();
                                            continue;
                                        }
                                        if (win.selectedElementIndices.indexOf(h) !== -1 && (win.grabbedElementIndex !== -1 || win.resizeGrabbed || win.rotateGrabbed)) continue;
                                        ctx.save();
                                        if (action.rotation && action.rotation !== 0) {
                                            let cx = (action.minX + action.maxX) / 2;
                                            let cy = (action.minY + action.maxY) / 2;
                                            ctx.translate(cx, cy);
                                            ctx.rotate(action.rotation);
                                            ctx.translate(-cx, -cy);
                                        }
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
                                        win.drawLocalErasers(ctx, action);
                                        ctx.restore();
                                    } else if (action.type === "shape") {
                                        if (win.selectedElementIndices.indexOf(h) !== -1 && (win.grabbedElementIndex !== -1 || win.resizeGrabbed || win.rotateGrabbed)) continue;
                                        ctx.save();
                                        if (action.rotation && action.rotation !== 0) {
                                            let cx = (action.minX + action.maxX) / 2;
                                            let cy = (action.minY + action.maxY) / 2;
                                            ctx.translate(cx, cy);
                                            ctx.rotate(action.rotation);
                                            ctx.translate(-cx, -cy);
                                        }
                                        ctx.beginPath();
                                        applyToolStyle(ctx, "pen", action.color, action.penSize);
                                        if (action.shapeType === "rectangle") {
                                            let rx = Math.min(action.x1, action.x2);
                                            let ry = Math.min(action.y1, action.y2);
                                            let rw = Math.abs(action.x2 - action.x1);
                                            let rh = Math.abs(action.y2 - action.y1);
                                            ctx.rect(rx, ry, rw, rh);
                                            ctx.stroke();
                                        } else if (action.shapeType === "circle") {
                                            let rx = Math.min(action.x1, action.x2);
                                            let ry = Math.min(action.y1, action.y2);
                                            let rw = Math.abs(action.x2 - action.x1);
                                            let rh = Math.abs(action.y2 - action.y1);
                                            ctx.ellipse(rx, ry, rw, rh);
                                            ctx.stroke();
                                        } else if (action.shapeType === "line") {
                                            ctx.moveTo(action.x1, action.y1);
                                            ctx.lineTo(action.x2, action.y2);
                                            ctx.stroke();
                                        } else if (action.shapeType === "arrow") {
                                            win.drawArrow(ctx, action.x1, action.y1, action.x2, action.y2, action.penSize, action.color);
                                        }
                                        win.drawLocalErasers(ctx, action);
                                        ctx.restore();
                                    } else if (action.type === "text") {
                                        if (h === win.editingTextIndex || (win.selectedElementIndices.indexOf(h) !== -1 && (win.grabbedElementIndex !== -1 || win.resizeGrabbed || win.rotateGrabbed))) continue;
                                        ctx.save();
                                        if (action.rotation && action.rotation !== 0) {
                                            let cx = (action.minX + action.maxX) / 2;
                                            let cy = (action.minY + action.maxY) / 2;
                                            ctx.translate(cx, cy);
                                            ctx.rotate(action.rotation);
                                            ctx.translate(-cx, -cy);
                                        }
                                        ctx.globalCompositeOperation = "source-over";
                                        ctx.fillStyle = action.color;
                                        let weight = (action.isBold === undefined || action.isBold) ? "bold" : "normal";
                                        let style = action.isItalic ? "italic" : "normal";
                                        let family = "Inter, system-ui, sans-serif";
                                        if (action.fontFamily === "serif") family = "Georgia, serif";
                                        else if (action.fontFamily === "monospace") family = "JetBrains Mono, monospace";
                                        else if (action.fontFamily === "cursive") family = "Caveat, cursive";
                                        ctx.font = style + " " + weight + " " + action.fontSize + "px " + family;
                                        ctx.textBaseline = "middle";
                                        ctx.fillText(action.text, action.x, action.y);
                                        win.drawLocalErasers(ctx, action);
                                        ctx.restore();
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
                        acceptedButtons: Qt.LeftButton
                        hoverEnabled: win.currentTool === "text" || win.currentTool === "mouse"
                        propagateComposedEvents: true
                        
                        cursorShape: {
                            if (win.currentTool === "text") {
                                return win.isHoveringText ? Qt.IBeamCursor : Qt.CrossCursor;
                            }
                            if (win.currentTool === "mouse") {
                                if (win.resizeGrabbed) {
                                    return Qt.SizeAllCursor;
                                }
                                if (win.rotateGrabbed) {
                                    return Qt.PointingHandCursor;
                                }
                                if (win.grabbedElementIndex !== -1) return Qt.ClosedHandCursor;
                                
                                if (win.selectedElementIndex !== -1) {
                                    let handle = getHoveredHandle(win.lastHoverX, win.lastHoverY);
                                    if (handle === "ROT") return Qt.PointingHandCursor;
                                    if (handle === "TL" || handle === "BR") return Qt.SizeFDiagCursor;
                                    if (handle === "TR" || handle === "BL") return Qt.SizeBDiagCursor;
                                }
                                
                                return win.hoveredElementIndex !== -1 ? Qt.OpenHandCursor : Qt.ArrowCursor;
                            }
                            return Qt.CrossCursor;
                        }

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
                            rootRectangle.forceActiveFocus();
                            win.showSizeConfig = false;
                            win.showColorPicker = false;

                            if (win.currentTool === "mouse") {
                                if (win.selectedElementIndices.length > 0) {
                                    let handle = getHoveredHandle(mouse.x, mouse.y);
                                    if (handle === "ROT") {
                                        win.rotateGrabbed = true;
                                        let cx = (win.selectionMinX + win.selectionMaxX) / 2;
                                        let cy = (win.selectionMinY + win.selectionMaxY) / 2;
                                        win.grabbedInitialAngle = Math.atan2(mouse.y - cy, mouse.x - cx);
                                        win.grabbedElementInitialRotation = win.selectionRotation;
                                        
                                        mouse.accepted = true;
                                        win.triggerReplay();
                                        previewCanvas.requestPaint();
                                        return;
                                    } else if (handle !== "") {
                                        win.resizeHandle = handle;
                                        win.resizeGrabbed = true;
                                        win.grabStartMouseX = mouse.x;
                                        win.grabStartMouseY = mouse.y;
                                        win.grabbedMinX = win.selectionMinX;
                                        win.grabbedMaxX = win.selectionMaxX;
                                        win.grabbedMinY = win.selectionMinY;
                                        win.grabbedMaxY = win.selectionMaxY;
                                        win.grabbedElementDx = 0;
                                        win.grabbedElementDy = 0;
                                        
                                        win.actionsBeforeResize = [];
                                        for (let idx of win.selectedElementIndices) {
                                            win.actionsBeforeResize.push(cloneAction(win.actionHistory[idx]));
                                        }
                                        
                                        mouse.accepted = true;
                                        win.triggerReplay();
                                        previewCanvas.requestPaint();
                                        return;
                                    }
                                }
                                
                                if (win.hoveredElementIndex !== -1) {
                                    let isShiftHeld = (mouse.modifiers & Qt.ShiftModifier);
                                    let idx = win.hoveredElementIndex;
                                    
                                    if (isShiftHeld) {
                                        let foundIdx = win.selectedElementIndices.indexOf(idx);
                                        if (foundIdx !== -1) {
                                            let newIndices = win.selectedElementIndices.slice();
                                            newIndices.splice(foundIdx, 1);
                                            win.selectedElementIndices = newIndices;
                                        } else {
                                            let newIndices = win.selectedElementIndices.slice();
                                            newIndices.push(idx);
                                            win.selectedElementIndices = newIndices;
                                        }
                                    } else {
                                        if (win.selectedElementIndices.indexOf(idx) === -1) {
                                            win.selectedElementIndices = [idx];
                                        }
                                    }
                                    
                                    win.updateSelectionBounds();
                                    
                                    if (win.selectedElementIndices.length > 0) {
                                        win.grabbedElementIndex = idx;
                                        win.grabStartMouseX = mouse.x;
                                        win.grabStartMouseY = mouse.y;
                                        win.grabbedElementDx = 0;
                                        win.grabbedElementDy = 0;
                                        mouse.accepted = true;
                                    } else {
                                        mouse.accepted = false;
                                    }
                                    
                                    win.triggerReplay();
                                    previewCanvas.requestPaint();
                                } else {
                                    let isShiftHeld = (mouse.modifiers & Qt.ShiftModifier);
                                    if (!isShiftHeld) {
                                        if (win.selectedElementIndices.length > 0) {
                                            win.selectedElementIndices = [];
                                            win.updateSelectionBounds();
                                            win.triggerReplay();
                                            previewCanvas.requestPaint();
                                        }
                                    }
                                    mouse.accepted = false; // let DragHandler pan the board
                                }
                                return;
                            }

                            if (win.currentTool === "fill") {
                                let freezeCol = win.currentColor.toString();
                                win.commitAction({ type: "fill_bg", color: freezeCol });
                                drawCanvas._queue.push({ type: "fill_bg", color: freezeCol });
                                
                                drawCanvas.markDirty(Qt.rect(0, 0, drawCanvas.width, drawCanvas.height)); 
                                drawCanvas.requestPaint();
                                return;
                            }

                            if (win.currentTool === "text") {
                                if (activeTextEditor.visible) {
                                    activeTextEditor.commitText();
                                    return;
                                }
                                
                                if (win.isHoveringText && win.hoveredTextIndex !== -1) {
                                    let action = win.actionHistory[win.hoveredTextIndex];
                                    win.editingTextIndex = win.hoveredTextIndex;
                                    
                                    activeTextEditor.text = action.text;
                                    activeTextEditor.x = action.x - 12;
                                    activeTextEditor.y = action.y - activeTextEditor.height / 2;
                                    
                                    win.selectColor(action.color);
                                    win.penSizeRatio = Math.max(0.0, Math.min(1.0, (action.fontSize - 16) / 48));
                                    
                                    win.activeTextFontFamily = action.fontFamily || "sans-serif";
                                    win.activeTextIsBold = (action.isBold !== undefined) ? action.isBold : true;
                                    win.activeTextIsItalic = !!action.isItalic;
                                    
                                    activeTextEditor.visible = true;
                                    win.triggerReplay();
                                } else {
                                    win.editingTextIndex = -1;
                                    activeTextEditor.x = mouse.x;
                                    activeTextEditor.y = mouse.y - activeTextEditor.height / 2;
                                    
                                    win.activeTextFontFamily = "sans-serif";
                                    win.activeTextIsBold = true;
                                    win.activeTextIsItalic = false;
                                    
                                    activeTextEditor.visible = true;
                                }
                                return;
                            }

                            if (win.currentTool === "line" || win.currentTool === "rectangle" || win.currentTool === "circle" || win.currentTool === "arrow") {
                                shapePreview.startX = mouse.x;
                                shapePreview.startY = mouse.y;
                                shapePreview.curX = mouse.x;
                                shapePreview.curY = mouse.y;
                                shapePreview.shapeType = win.currentTool;
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
                            if (pressed) {
                                if (win.currentTool === "mouse" && win.rotateGrabbed) {
                                    let cx = (win.selectionMinX + win.selectionMaxX) / 2;
                                    let cy = (win.selectionMinY + win.selectionMaxY) / 2;
                                    let currentAngle = Math.atan2(mouse.y - cy, mouse.x - cx);
                                    let delta = currentAngle - win.grabbedInitialAngle;
                                    
                                    if (mouse.modifiers & Qt.ShiftModifier) {
                                        let totalRot = win.grabbedElementInitialRotation + delta;
                                        let snap = Math.PI / 12; // 15 deg
                                        totalRot = Math.round(totalRot / snap) * snap;
                                        delta = totalRot - win.grabbedElementInitialRotation;
                                    }
                                    win.grabbedElementRotationDelta = delta;
                                    previewCanvas.requestPaint();
                                    return;
                                }

                                if (win.currentTool === "mouse" && win.resizeGrabbed) {
                                    win.grabbedElementDx = mouse.x - win.grabStartMouseX;
                                    win.grabbedElementDy = mouse.y - win.grabStartMouseY;
                                    previewCanvas.requestPaint();
                                    return;
                                }

                                if (win.currentTool === "mouse" && win.grabbedElementIndex !== -1) {
                                    win.grabbedElementDx = mouse.x - win.grabStartMouseX;
                                    win.grabbedElementDy = mouse.y - win.grabStartMouseY;
                                    previewCanvas.requestPaint();
                                    return;
                                }

                                if (win.currentTool === "line" || win.currentTool === "rectangle" || win.currentTool === "circle" || win.currentTool === "arrow") {
                                    shapePreview.curX = mouse.x;
                                    shapePreview.curY = mouse.y;
                                    previewCanvas.requestPaint();
                                    return;
                                }

                                if (win.currentTool !== "fill" && win.currentTool !== "mouse" && win.currentTool !== "text" && win.currentAction) {
                                    let dx = mouse.x - drawCanvas.lastX;
                                    let dy = mouse.y - drawCanvas.lastY;
                                    let distSq = dx * dx + dy * dy;
                                    let minDistance = 3.0; // 3px distance filter for lightweight paths
                                    
                                    if (distSq >= minDistance * minDistance) {
                                        var segment = {
                                            x1: drawCanvas.lastX, y1: drawCanvas.lastY,
                                            x2: mouse.x, y2: mouse.y
                                        };
                                        
                                        win.currentAction.segments.push(segment);

                                        drawCanvas._queue.push({
                                            type: "stroke",
                                            tool: win.currentTool,
                                            color: win.currentColor.toString(),
                                            penSize: win.actualToolSize,
                                            x1: segment.x1, y1: segment.y1, 
                                            x2: segment.x2, y2: segment.y2
                                        });
                                        
                                        var rad = win.actualToolSize / 2 + 5;
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
                            } else {
                                let dist = Math.sqrt(Math.pow(mouse.x - win.lastHoverX, 2) + Math.pow(mouse.y - win.lastHoverY, 2));
                                if (win.selectedElementIndices.length > 0 || dist > 6) {
                                    win.lastHoverX = mouse.x;
                                    win.lastHoverY = mouse.y;
                                    win.updateHoverState(mouse.x, mouse.y);
                                }
                            }
                        }

                        onExited: {
                            win.isHoveringText = false;
                            win.hoveredTextIndex = -1;
                            win.hoveredElementIndex = -1;
                            win.lastHoverX = -1;
                            win.lastHoverY = -1;
                        }

                        onReleased: (mouse) => {
                            if (win.currentTool === "mouse") {
                                if (win.rotateGrabbed && win.selectedElementIndices.length > 0) {
                                    let cx = (win.selectionMinX + win.selectionMaxX) / 2;
                                    let cy = (win.selectionMinY + win.selectionMaxY) / 2;
                                    let delta = win.grabbedElementRotationDelta;
                                    
                                    if (mouse.modifiers & Qt.ShiftModifier) {
                                        let snap = Math.PI / 12; // 15 degrees
                                        delta = Math.round(delta / snap) * snap;
                                    }
                                    
                                    for (let i = 0; i < win.selectedElementIndices.length; i++) {
                                        let idx = win.selectedElementIndices[i];
                                        let action = win.actionHistory[idx];
                                        if (action) {
                                            rotateAction(action, delta, cx, cy);
                                            action.isFullyErasedCache = undefined;
                                            action.minX = undefined;
                                        }
                                    }
                                    
                                    win.rotateGrabbed = false;
                                    win.grabbedElementRotationDelta = 0;
                                    win.updateSelectionBounds();
                                    win.triggerReplay();
                                    previewCanvas.requestPaint();
                                } else if (win.resizeGrabbed && win.actionsBeforeResize.length > 0 && win.selectedElementIndices.length > 0) {
                                    let dx = win.grabbedElementDx;
                                    let dy = win.grabbedElementDy;
                                    
                                    let minX = win.grabbedMinX;
                                    let maxX = win.grabbedMaxX;
                                    let minY = win.grabbedMinY;
                                    let maxY = win.grabbedMaxY;
                                    
                                    if (win.resizeHandle === "BR") {
                                        maxX = Math.max(minX + 5, win.grabbedMaxX + dx);
                                        maxY = Math.max(minY + 5, win.grabbedMaxY + dy);
                                    } else if (win.resizeHandle === "TL") {
                                        minX = Math.min(maxX - 5, win.grabbedMinX + dx);
                                        minY = Math.min(maxY - 5, win.grabbedMinY + dy);
                                    } else if (win.resizeHandle === "TR") {
                                        maxX = Math.max(minX + 5, win.grabbedMaxX + dx);
                                        minY = Math.min(maxY - 5, win.grabbedMinY + dy);
                                    } else if (win.resizeHandle === "BL") {
                                        minX = Math.min(maxX - 5, win.grabbedMinX + dx);
                                        maxY = Math.max(minY + 5, win.grabbedMaxY + dy);
                                    }
                                    
                                    let W0 = win.grabbedMaxX - win.grabbedMinX;
                                    let H0 = win.grabbedMaxY - win.grabbedMinY;
                                    if (W0 === 0) W0 = 1;
                                    if (H0 === 0) H0 = 1;
                                    
                                    let scaleX = (maxX - minX) / W0;
                                    let scaleY = (maxY - minY) / H0;
                                    
                                    let refX = win.grabbedMinX;
                                    let refY = win.grabbedMinY;
                                    if (win.resizeHandle === "TL") { refX = win.grabbedMaxX; refY = win.grabbedMaxY; }
                                    else if (win.resizeHandle === "TR") { refX = win.grabbedMinX; refY = win.grabbedMaxY; }
                                    else if (win.resizeHandle === "BL") { refX = win.grabbedMaxX; refY = win.grabbedMinY; }
                                    
                                    for (let i = 0; i < win.selectedElementIndices.length; i++) {
                                        let idx = win.selectedElementIndices[i];
                                        let finalAction = cloneAction(win.actionsBeforeResize[i]);
                                        scaleAction(finalAction, scaleX, scaleY, refX, refY);
                                        finalAction.isFullyErasedCache = undefined;
                                        finalAction.minX = undefined;
                                        win.actionHistory[idx] = finalAction;
                                    }
                                    
                                    win.actionsBeforeResize = [];
                                    win.resizeGrabbed = false;
                                    win.resizeHandle = "";
                                    win.grabbedElementDx = 0;
                                    win.grabbedElementDy = 0;
                                    win.updateSelectionBounds();
                                    win.triggerReplay();
                                    previewCanvas.requestPaint();
                                } else if (win.grabbedElementIndex !== -1) {
                                    let dx = win.grabbedElementDx;
                                    let dy = win.grabbedElementDy;
                                    
                                    for (let i = 0; i < win.selectedElementIndices.length; i++) {
                                        let idx = win.selectedElementIndices[i];
                                        let action = win.actionHistory[idx];
                                        if (action) {
                                            win.shiftAction(action, dx, dy);
                                            action.isFullyErasedCache = undefined;
                                            action.minX = undefined;
                                        }
                                    }
                                    
                                    win.grabbedElementIndex = -1;
                                    win.grabbedElementDx = 0;
                                    win.grabbedElementDy = 0;
                                    win.updateSelectionBounds();
                                    win.triggerReplay();
                                    previewCanvas.requestPaint();
                                }
                                return;
                            }

                            if (win.currentTool === "line" || win.currentTool === "rectangle" || win.currentTool === "circle" || win.currentTool === "arrow") {
                                let shapeTypeSaved = shapePreview.shapeType;
                                shapePreview.shapeType = "";
                                previewCanvas.requestPaint();
                                let dist = Math.sqrt(Math.pow(mouse.x - shapePreview.startX, 2) + Math.pow(mouse.y - shapePreview.startY, 2));
                                if (dist > 2) {
                                    let action = {
                                        type: "shape",
                                        shapeType: shapeTypeSaved || win.currentTool,
                                        x1: shapePreview.startX,
                                        y1: shapePreview.startY,
                                        x2: mouse.x,
                                        y2: mouse.y,
                                        color: win.currentColor.toString(),
                                        penSize: win.actualToolSize
                                    };
                                    win.commitAction(action);
                                    win.triggerReplay();
                                }
                                return;
                            }

                            if (win.currentAction) {
                                // Add a final segment if the last mouse position changed
                                if (mouse.x !== drawCanvas.lastX || mouse.y !== drawCanvas.lastY) {
                                    var finalSegment = {
                                        x1: drawCanvas.lastX, y1: drawCanvas.lastY,
                                        x2: mouse.x, y2: mouse.y
                                    };
                                    win.currentAction.segments.push(finalSegment);
                                }
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
                        cameraRig.grabToImage(function(result) {
                            if (result.saveToFile(tempPath)) {
                                Quickshell.execDetached(["sh", "-c", "wl-copy -t image/png < \"" + tempPath + "\""]);
                                Toaster.toast("Pizarra", "Copiado al portapapeles", "content_copy", Toast.Success);
                            } else {
                                Toaster.toast("Pizarra", "Error al guardar el dibujo", "error", Toast.Error);
                            }
                        });
                    }
                }
            }

            // --- FULLSCREEN BUTTON ---
            Rectangle {
                width: 38; height: 38
                radius: Tokens.rounding.medium
                color: win.panelBgColor
                border.width: 1
                border.color: win.panelBorderColor
                
                Rectangle {
                    anchors.centerIn: parent; width: 28; height: 28; radius: Tokens.rounding.small; z:-1
                    color: fullscreenMouse.containsMouse ? Colours.palette.m3surfaceVariant : "transparent"
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: win.isFullScreen ? "fullscreen_exit" : "fullscreen"
                    color: win.baseTextColor
                }

                MouseArea {
                    id: fullscreenMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        win.isFullScreen = !win.isFullScreen;
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
                        win.selectedElementIndices = [];
                        win.grabbedElementIndex = -1;
                        win.resizeGrabbed = false;
                        win.rotateGrabbed = false;
                        win.actionHistory = [];
                        win.historyStep = -1;
                        win.jsState.history = [];
                        win.jsState.step = -1;
                        win.updateSelectionBounds();
                        drawCanvas._replayPending = true;
                        drawCanvas.requestPaint();
                        previewCanvas.requestPaint();
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

            MouseArea {
                anchors.fill: parent
                onPressed: (mouse) => { mouse.accepted = true; }
            }

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

                // --- TOOL: LINE ---
                ToolButton {
                    iconName: "horizontal_rule"
                    toolKey: "line"
                }

                // --- TOOL: ARROW ---
                ToolButton {
                    iconName: "north_east"
                    toolKey: "arrow"
                }

                // --- TOOL: RECTANGLE ---
                ToolButton {
                    iconName: "crop_square"
                    toolKey: "rectangle"
                }

                // --- TOOL: CIRCLE ---
                ToolButton {
                    iconName: "circle"
                    toolKey: "circle"
                }

                // --- TOOL: TEXT ---
                ToolButton {
                    iconName: "title"
                    toolKey: "text"
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
            
            MouseArea {
                anchors.fill: parent
                onPressed: (mouse) => { mouse.accepted = true; }
            }
            
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
            
            MouseArea {
                anchors.fill: parent
                onPressed: (mouse) => { mouse.accepted = true; }
            }
            
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
                                    win.selectColor(modelData);
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
