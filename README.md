# JesDev12U - Custom Caelestia Dotfiles

Bienvenidos a mi fork personalizado de Caelestia, un entorno de escritorio minimalista y altamente estético diseñado para el gestor de ventanas Hyprland en Arch Linux, potenciado por Quickshell y personalizado con utilidades modernas para la terminal.

Este repositorio contiene una versión optimizada, limpia y libre de bloatware, con integraciones específicas de flujo de trabajo diario y soporte completo para caracteres universales/chinos.

---

## Características de este Fork

### Interfaz y Escritorio (Hyprland & Quickshell)

- **Código QML Personalizado**: Optimización en los paneles del shell de Caelestia, corrigiendo bugs de visualización nativos.
- **Integración de Pizarra**: Botón de acceso rápido integrado en el control center para abrir la pizarra infinita nativa escrita en QML.
- **Tema de Cursores Apple**: Configuración y descarga del elegante juego de cursores de macOS (`apple_cursor`).
- **Soporte Tipográfico Universal**: Configuración nativa y tipografías CJK/UTF (`noto-fonts-cjk`, `wqy-zenhei`, `adobe-source-han-sans-cn-fonts`) para la visualización correcta de cualquier abecedario y caracteres especiales.

### Terminal & Shell (Kitty + Zsh + Starship)

- **Kitty Terminal**: Configurado con la fuente de alto rendimiento _Hack Nerd Font_, colores balanceados y atajos personalizados optimizados para productividad.
- **Zsh & Plugins**: Shell predeterminado enriquecido con:
  - `zsh-autosuggestions`: Autocompletado inteligente basado en historial.
  - `zsh-syntax-highlighting`: Resaltado de sintaxis visual (comandos válidos en verde, inválidos en rojo).
  - `fzf-tab`: Menú interactivo de autocompletado en Zsh utilizando `fzf`.
- **Starship Prompt**: Configurado con mi variante del tema _Cyberdream_, estructurado en bloques informáticos limpios (sin emojis intrusivos).
- **Utilidades de Terminal Integradas**:
  - `bat`: Reemplazo de `cat` con resaltado de código.
  - `eza`: Reemplazo de `ls` y `tree` con iconos estructurados.
  - `atuin`: Historial de comandos interactivo y de alto rendimiento.
  - `fzf`: Filtro fuzzy interactivo integrado con previsualizaciones en tiempo real usando `bat`.

---

## Instalación Rápida

Este repositorio incluye un instalador moderno escrito en POSIX Bash/Shell que no tiene dependencias previas de Fish, lo que permite instalar todo mediante una sola tubería de curl.

### Requisitos previos:

- Tener una instalación limpia de Arch Linux.
- Conexión a internet activa.

### Comando de Instalación:

```bash
curl -fsSL https://raw.githubusercontent.com/JesDev12U/jesdev12u-hyprland-dots/refs/heads/main/install.sh | bash
```

### ¿Qué hace el instalador automáticamente?

1. Detecta o instala tu helper de AUR (`paru` o `yay`).
2. Instala las dependencias del sistema y los paquetes de AUR necesarios.
3. Descarga de forma dinámica los repositorios de plugins de Zsh.
4. Enlaza los archivos de configuración (`hypr`, `kitty`, `starship.toml`, `.zshrc`, `uwsm`, etc.) a tu directorio `~/.config/`.
5. Enlaza los wallpapers a `~/Pictures/Wallpapers/` de manera no destructiva.
6. Configura tu shell por defecto a Zsh.

# Notas

Si el cursor se ve pequeño al momento de instalar, puedes colocar estos comandos para setear el tamaño a tu gusto:

```bash
hyprctl setcursor macOS 34
gsettings set org.gnome.desktop.interface cursor-size 34
```
