import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

ShellRoot {
    id: root

    // Reactive Theme Colors (loaded from Caelestia scheme)
    property var themeColours: ({
        "background": "#131317",
        "onBackground": "#e5e1e7",
        "primary": "#c2c1ff",
        "secondary": "#c6c4e0",
        "tertiary": "#f5b2e0",
        "surfaceContainer": "#1c1b1f",
        "surfaceContainerHigh": "#2a292e",
        "onSurface": "#e5e1e7",
        "onSurfaceVariant": "#918f9a"
    })

    // Load active Caelestia theme colors
    function loadTheme() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", "file:///home/jesdev12u/.local/state/caelestia/scheme.json", true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data && data.colours) {
                            var cols = data.colours;
                            themeColours = {
                                "background": "#" + cols.background,
                                "onBackground": "#" + cols.onBackground,
                                "primary": "#" + cols.primary,
                                "secondary": "#" + cols.secondary,
                                "tertiary": "#" + cols.tertiary,
                                "surfaceContainer": "#" + (cols.surfaceContainerLow || cols.surfaceContainer || "1c1b1f"),
                                "surfaceContainerHigh": "#" + (cols.surfaceContainerHigh || "2a292e"),
                                "onSurface": "#" + cols.onSurface,
                                "onSurfaceVariant": "#" + (cols.onSurfaceVariant || cols.subtext1 || "918f9a")
                            };
                        }
                    } catch (e) {
                        console.log("Error parsing scheme.json:", e);
                    }
                }
            }
        };
        xhr.send();
    }

    FloatingWindow {
        id: win
        visible: true
        width: 800
        height: 600
        title: "Glosario de Keybinds"
        color: "transparent"

        // Handle ESC key to exit
        Shortcut {
            sequence: "Escape"
            onActivated: Quickshell.exit(0)
        }

        // Main window container
        Rectangle {
            anchors.fill: parent
            color: themeColours.background
            opacity: 0.96
            radius: 16
            border.width: 1
            border.color: themeColours.primary

            // Layout
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 15

                // Header section
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 15

                    // Title
                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: "GLOSARIO DE KEYBINDS"
                            color: themeColours.primary
                            font.bold: true
                            font.pixelSize: 18
                            font.family: "Hack Nerd Font"
                        }
                        Text {
                            text: "Atajos de teclado de tu sistema Hyprland"
                            color: themeColours.onSurfaceVariant
                            font.pixelSize: 12
                            font.family: "Hack Nerd Font"
                        }
                    }

                    Spacer { Layout.fillWidth: true }

                    // Close Button
                    Button {
                        id: closeBtn
                        implicitWidth: 32
                        implicitHeight: 32
                        flat: true
                        background: Rectangle {
                            color: closeBtn.hovered ? themeColours.surfaceContainerHigh : "transparent"
                            radius: 16
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        contentItem: Text {
                            text: "󰅖" // Nerd font close icon
                            color: closeBtn.hovered ? "#ffb4ab" : themeColours.onBackground
                            font.pixelSize: 18
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: Quickshell.exit(0)
                    }
                }

                // Search Box
                Rectangle {
                    Layout.fillWidth: true
                    height: 45
                    color: themeColours.surfaceContainer
                    radius: 8
                    border.width: 1
                    border.color: searchField.activeFocus ? themeColours.primary : themeColours.surfaceContainerHigh
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 15
                        anchors.rightMargin: 15
                        spacing: 10

                        Text {
                            text: "󰍉" // Search icon
                            color: themeColours.onSurfaceVariant
                            font.pixelSize: 16
                            verticalAlignment: Text.AlignVCenter
                        }

                        TextField {
                            id: searchField
                            Layout.fillWidth: true
                            placeholderText: "Buscar atajo, comando o descripción..."
                            placeholderTextColor: themeColours.onSurfaceVariant
                            color: themeColours.onBackground
                            font.pixelSize: 14
                            font.family: "Hack Nerd Font"
                            background: null
                            focus: true
                            verticalAlignment: TextInput.AlignVCenter

                            onTextChanged: applyFilter()
                        }

                        Button {
                            id: clearBtn
                            visible: searchField.text !== ""
                            implicitWidth: 24
                            implicitHeight: 24
                            flat: true
                            background: null
                            contentItem: Text {
                                text: "󰅖"
                                color: themeColours.onSurfaceVariant
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                searchField.text = "";
                                searchField.forceActiveFocus();
                            }
                        }
                    }
                }

                // Keybinds List
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: themeColours.surfaceContainer
                    radius: 8
                    border.width: 1
                    border.color: themeColours.surfaceContainerHigh
                    clip: true

                    ListView {
                        id: listView
                        anchors.fill: parent
                        anchors.margins: 10
                        model: filteredModel
                        spacing: 5
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: Rectangle {
                            width: listView.width
                            height: 48
                            color: itemMouseArea.containsMouse ? themeColours.surfaceContainerHigh : "transparent"
                            radius: 6
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 15

                                // Keybadge container
                                Rectangle {
                                    Layout.preferredWidth: 240
                                    Layout.fillHeight: true
                                    Layout.topMargin: 6
                                    Layout.bottomMargin: 6
                                    color: themeColours.background
                                    radius: 4
                                    border.width: 1
                                    border.color: themeColours.surfaceContainerHigh

                                    Text {
                                        anchors.centerIn: parent
                                        text: model.keys
                                        color: themeColours.secondary
                                        font.bold: true
                                        font.pixelSize: 11
                                        font.family: "Hack Nerd Font"
                                        elide: Text.ElideRight
                                    }
                                }

                                // Description
                                Text {
                                    Layout.fillWidth: true
                                    text: model.desc
                                    color: themeColours.onBackground
                                    font.pixelSize: 13
                                    font.family: "Hack Nerd Font"
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: itemMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                            }
                        }

                        // Category Section Headers
                        section.property: "category"
                        section.criteria: ViewSection.FullString
                        section.delegate: Component {
                            Rectangle {
                                width: listView.width
                                height: 35
                                color: "transparent"
                                Text {
                                    text: section
                                    color: themeColours.tertiary
                                    font.bold: true
                                    font.pixelSize: 12
                                    font.family: "Hack Nerd Font"
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 6
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                }
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            active: true
                            policy: ScrollBar.AsNeeded
                        }
                    }
                }

                // Footer section
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Presiona [ESC] o vuelve a presionar [Super + H] para salir"
                        color: themeColours.onSurfaceVariant
                        font.pixelSize: 11
                        font.family: "Hack Nerd Font"
                    }
                    Spacer { Layout.fillWidth: true }
                    Text {
                        text: "Total: " + filteredModel.count + " atajos"
                        color: themeColours.onSurfaceVariant
                        font.pixelSize: 11
                        font.family: "Hack Nerd Font"
                    }
                }
            }
        }
    }

    // Helper item for layout spacing
    component Spacer: Item {}

    // Filtered data model
    ListModel {
        id: filteredModel
    }

    // Master list model containing all system keybinds
    ListModel {
        id: masterModel

        // NAVEGACIÓN Y ESPACIOS DE TRABAJO
        ListElement { category: "NAVEGACIÓN Y ESPACIOS DE TRABAJO"; keys: "Super + [1-0]"; desc: "Ir al espacio de trabajo [1-10]" }
        ListElement { category: "NAVEGACIÓN Y ESPACIOS DE TRABAJO"; keys: "Ctrl + Super + [1-0]"; desc: "Ir al grupo de espacio de trabajo [1-10]" }
        ListElement { category: "NAVEGACIÓN Y ESPACIOS DE TRABAJO"; keys: "Super + Page Up / Down"; desc: "Ir al espacio de trabajo anterior / siguiente" }
        ListElement { category: "NAVEGACIÓN Y ESPACIOS DE TRABAJO"; keys: "Super + Shift + Rueda Scroll"; desc: "Cambiar de espacio de trabajo rápidamente (+/- 1)" }
        ListElement { category: "NAVEGACIÓN Y ESPACIOS DE TRABAJO"; keys: "Ctrl + Super + Rueda Scroll"; desc: "Cambiar de espacio de trabajo en pasos de (+/- 10)" }
        ListElement { category: "NAVEGACIÓN Y ESPACIOS DE TRABAJO"; keys: "Super + S"; desc: "Alternar espacio de trabajo especial (Scratchpad)" }

        // CONTROL DE VENTANAS
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Super + Flechas"; desc: "Cambiar el foco (moverse entre ventanas)" }
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Super + Shift + Flechas"; desc: "Mover ventana activa de posición" }
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Super + Alt + Flechas"; desc: "Redimensionar ventana activa" }
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Super + - / ="; desc: "Redimensionar ventana horizontalmente (-10% / +10%)" }
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Super + Shift + - / ="; desc: "Redimensionar ventana verticalmente (-10% / +10%)" }
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Super + Drag Click Izq"; desc: "Arrastrar para mover ventana flotante" }
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Super + Drag Click Der"; desc: "Arrastrar para redimensionar ventana flotante" }
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Ctrl + Super + \\"; desc: "Centrar ventana en pantalla" }
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Ctrl + Super + Alt + \\"; desc: "Ajustar ventana a tamaño exacto (55% 70%) y centrar" }
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Super + Alt + \\"; desc: "Mover ventana al modo Picture-in-Picture (PiP)" }
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Super + P"; desc: "Fijar ventana (Pin) en todos los espacios de trabajo" }
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Super + F"; desc: "Alternar pantalla completa (Fullscreen)" }
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Super + Alt + F"; desc: "Alternar pantalla completa con bordes visibles" }
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Super + Alt + Espacio"; desc: "Alternar ventana flotante / mosaico (Floating)" }
        ListElement { category: "CONTROL DE VENTANAS"; keys: "Super + Q"; desc: "Cerrar ventana activa (Kill)" }

        // GRUPOS DE VENTANAS
        ListElement { category: "GRUPOS DE VENTANAS"; keys: "Super + , (Coma)"; desc: "Agrupar ventana activa (Toggle Group)" }
        ListElement { category: "GRUPOS DE VENTANAS"; keys: "Super + U"; desc: "Desagrupar ventana (Mover fuera del grupo)" }
        ListElement { category: "GRUPOS DE VENTANAS"; keys: "Alt + Tab / Shift+Alt+Tab"; desc: "Cambiar foco a la ventana siguiente/anterior del grupo" }
        ListElement { category: "GRUPOS DE VENTANAS"; keys: "Ctrl+Alt+Tab / Ctrl+Shift+Alt+Tab"; desc: "Cambiar ventana activa dentro del grupo" }

        // APLICACIONES RÁPIDAS
        ListElement { category: "APLICACIONES RÁPIDAS"; keys: "Super + T"; desc: "Abrir Terminal (Kitty)" }
        ListElement { category: "APLICACIONES RÁPIDAS"; keys: "Super + B"; desc: "Abrir Navegador Web (Vivaldi)" }
        ListElement { category: "APLICACIONES RÁPIDAS"; keys: "Super + C"; desc: "Abrir Editor de Código (VS Code)" }
        ListElement { category: "APLICACIONES RÁPIDAS"; keys: "Super + E"; desc: "Abrir Explorador de Archivos (Thunar)" }
        ListElement { category: "APLICACIONES RÁPIDAS"; keys: "Super + Alt + E"; desc: "Abrir Explorador de Archivos alternativo (Nemo)" }
        ListElement { category: "APLICACIONES RÁPIDAS"; keys: "Ctrl + Alt + Escape"; desc: "Abrir Administrador de Tareas (Qps)" }
        ListElement { category: "APLICACIONES RÁPIDAS"; keys: "Ctrl + Alt + V"; desc: "Abrir Control de Volumen (Pavucontrol)" }

        // ESPACIOS DE TRABAJO ESPECIALES
        ListElement { category: "ESPACIOS DE TRABAJO ESPECIALES"; keys: "Ctrl + Shift + Escape"; desc: "Monitor de Sistema (Btop)" }
        ListElement { category: "ESPACIOS DE TRABAJO ESPECIALES"; keys: "Super + M"; desc: "Alternar Ventana de Música (Spotify/Feishin/etc.)" }
        ListElement { category: "ESPACIOS DE TRABAJO ESPECIALES"; keys: "Super + D"; desc: "Alternar Ventana de Comunicación (Discord/Vesktop/WhatsApp)" }
        ListElement { category: "ESPACIOS DE TRABAJO ESPECIALES"; keys: "Super + R"; desc: "Alternar Lista de Tareas Pendientes (Todoist)" }

        // UTILIDADES Y ZOOM
        ListElement { category: "UTILIDADES Y ZOOM"; keys: "Super + Rueda Scroll"; desc: "Acercar / Alejar zoom de pantalla (Estilo macOS)" }
        ListElement { category: "UTILIDADES Y ZOOM"; keys: "Super+Esc / Super+Shift+Z"; desc: "Restablecer zoom de pantalla" }
        ListElement { category: "UTILIDADES Y ZOOM"; keys: "Print"; desc: "Capturar pantalla completa y guardar al portapapeles" }
        ListElement { category: "UTILIDADES Y ZOOM"; keys: "Super + Shift + S"; desc: "Capturar región de la pantalla (congelada)" }
        ListElement { category: "UTILIDADES Y ZOOM"; keys: "Super + Shift + Alt + S"; desc: "Capturar región de la pantalla" }
        ListElement { category: "UTILIDADES Y ZOOM"; keys: "Super + Alt + R"; desc: "Iniciar grabación de pantalla completa con sonido" }
        ListElement { category: "UTILIDADES Y ZOOM"; keys: "Ctrl + Alt + R"; desc: "Iniciar grabación de pantalla completa" }
        ListElement { category: "UTILIDADES Y ZOOM"; keys: "Super + Shift + Alt + R"; desc: "Iniciar grabación de una región de pantalla" }
        ListElement { category: "UTILIDADES Y ZOOM"; keys: "Super + Shift + C"; desc: "Selector de Color en pantalla (Hyprpicker)" }
        ListElement { category: "UTILIDADES Y ZOOM"; keys: "Super + V"; desc: "Historial del Portapapeles (Caelestia Clipboard)" }
        ListElement { category: "UTILIDADES Y ZOOM"; keys: "Super + Alt + V"; desc: "Historial del Portapapeles (modo alternativo)" }
        ListElement { category: "UTILIDADES Y ZOOM"; keys: "Super + . (Punto)"; desc: "Selector de Emojis" }

        // SISTEMA Y MULTIMEDIA
        ListElement { category: "SISTEMA Y MULTIMEDIA"; keys: "Ctrl + Alt + Delete"; desc: "Abrir Menú de Sesión (Apagar/Reiniciar/Cerrar sesión)" }
        ListElement { category: "SISTEMA Y MULTIMEDIA"; keys: "Super + N"; desc: "Alternar Barra Lateral (Sidebar)" }
        ListElement { category: "SISTEMA Y MULTIMEDIA"; keys: "Ctrl + Alt + C"; desc: "Limpiar todas las notificaciones" }
        ListElement { category: "SISTEMA Y MULTIMEDIA"; keys: "Super + K"; desc: "Mostrar/Ocultar todos los paneles de Caelestia" }
        ListElement { category: "SISTEMA Y MULTIMEDIA"; keys: "Super + L"; desc: "Bloquear pantalla" }
        ListElement { category: "SISTEMA Y MULTIMEDIA"; keys: "Super + Alt + L"; desc: "Restaurar bloqueo de pantalla" }
        ListElement { category: "SISTEMA Y MULTIMEDIA"; keys: "Super + Shift + L"; desc: "Suspender e hibernar el equipo" }
        ListElement { category: "SISTEMA Y MULTIMEDIA"; keys: "Super + Shift + M"; desc: "Silenciar / Activar sonido (Mute)" }
    }

    // Filter Logic
    function applyFilter() {
        filteredModel.clear();
        var filter = searchField.text.toLowerCase();
        for (var i = 0; i < masterModel.count; i++) {
            var item = masterModel.get(i);
            if (filter === "" || 
                item.keys.toLowerCase().indexOf(filter) !== -1 || 
                item.desc.toLowerCase().indexOf(filter) !== -1 || 
                item.category.toLowerCase().indexOf(filter) !== -1) {
                filteredModel.append(item);
            }
        }
    }

    Component.onCompleted: {
        loadTheme();
        applyFilter();
    }
}
