#!/bin/bash
# ==============================================================================
# Caelestia Custom Installer (POSIX/Bash)
# A clean, fast, dependency-free installer for customized Caelestia dotfiles.
# ==============================================================================
set -eo pipefail

# Estado de la instalación
INSTALL_SUCCESS=0
CURRENT_STEP=0
STEPS_COMPLETED=0
START_TIME=0
AUR_HELPER=""
INSTALL_DIR=""

REPO_URL="https://github.com/JesDev12U/jesdev12u-hyprland-dots.git"
ENV_FILE="$HOME/.caelestia_install_env"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[1;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Helper output functions (mainly for logging)
log() { echo -e "${CYAN}:: $1${NC}"; }
success() { echo -e "${GREEN}:: $1${NC}"; }
warning() { echo -e "${YELLOW}Warning: $1${NC}"; }
error() { echo -e "${RED}Error: $1${NC}" >&2; }

# Setup log file
LOG_FILE="$HOME/.jesdev12u-hyprland-install.log"
echo "=== LOG DE INSTALACIÓN - $(date) ===" > "$LOG_FILE"

# Setup variables
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"

# Define step messages
STEP_MSGS=(
    ""
    "Detectando e instalando helper de AUR"
    "Configurando Pacman (ILoveCandy y multilib)"
    "Realizando respaldo de la carpeta ~/.config"
    "Instalando paquetes esenciales del sistema con pacman"
    "Instalando paquetes de AUR"
    "Creando enlaces simbólicos de las configuraciones"
    "Instalando y enlazando fondos de pantalla"
    "Clonando e instalando plugins de Zsh"
    "Configurando gestores de pantalla y arranque (SDDM/GRUB)"
    "Configurando Zsh como shell predeterminado y finalizando"
)

# Check if running on Arch Linux
if [ ! -f /etc/arch-release ]; then
    error "Este instalador está diseñado únicamente para Arch Linux."
    exit 1
fi

# Banner
echo -e "${MAGENTA}"
echo '     ██╗███████╗███████╗██████╗ ███████╗██╗   ██╗ ██╗██████╗ ██╗   ██╗'
echo '     ██║██╔════╝██╔════╝██╔══██╗██╔════╝██║   ██║███║╚════██╗██║   ██║'
echo '     ██║█████╗  ███████╗██║  ██║█████╗  ██║   ██║╚██║ █████╔╝██║   ██║'
echo '██   ██║██╔══╝  ╚════██║██║  ██║██╔══╝  ╚██╗ ██╔╝ ██║██╔═══╝ ██║   ██║'
echo '╚█████╔╝███████╗███████║██████╔╝███████╗ ╚████╔╝  ██║███████╗╚██████╔╝'
echo ' ╚════╝ ╚══════╝╚══════╝╚═════╝ ╚══════╝  ╚═══╝   ╚═╝╚══════╝ ╚═════╝'
echo -e "            ${YELLOW}\"Mis Dots de Hyprland forkeados de Caelestia\"${NC}"
echo '                 - Custom Clean POSIX Shell Installer -'
echo -e "${NC}"

# Preguntar sobre el respaldo al inicio solo si existe la carpeta ~/.config
BACKUP_CONFIG=0
if [ -d "$CONFIG_DIR" ]; then
    echo -e "${BLUE}:: Configuración inicial${NC}"
    echo -ne "${CYAN}¿Deseas hacer un respaldo de tu carpeta ~/.config actual? [Y/n] ${NC}"
    # Leer de /dev/tty para dar soporte a la ejecución mediante pipe (curl | bash)
    if [ -t 0 ]; then
        read -r backup_choice
    else
        read -r backup_choice < /dev/tty 2>/dev/null || backup_choice="y"
    fi
    BACKUP_CONFIG=1
    if [[ "$backup_choice" == "n" || "$backup_choice" == "N" ]]; then
        BACKUP_CONFIG=0
    fi
fi

# Solicitar privilegios de administrador al inicio
echo -e "${BLUE}:: Solicitando privilegios de administrador...${NC}"
sudo_password=""
if ! sudo -n -v 2>/dev/null; then
    # Se requiere contraseña
    if [ -t 0 ]; then
        read -rs -p "Introduce tu contraseña de sudo: " sudo_password
        echo ""
    else
        read -rs -p "Introduce tu contraseña de sudo: " sudo_password < /dev/tty
        echo "" > /dev/tty
    fi
    
    # Validar la contraseña
    if ! echo "$sudo_password" | sudo -S -v 2>/dev/null; then
        error "Contraseña incorrecta o el usuario no tiene privilegios de sudo."
        exit 1
    fi
fi

# Configurar helpers de sudo para automatizar la autenticación
HELPERS_DIR="$HOME/.caelestia-install-helpers"
mkdir -p "$HELPERS_DIR"
chmod 700 "$HELPERS_DIR"

# Escribir el script askpass
cat << 'EOF' > "$HELPERS_DIR/caelestia-askpass"
#!/bin/bash
echo "${CAELESTIA_SUDO_PASSWORD:-}"
EOF
chmod +x "$HELPERS_DIR/caelestia-askpass"

# Escribir el wrapper de sudo
cat << 'EOF' > "$HELPERS_DIR/sudo"
#!/bin/bash
if [ -n "${CAELESTIA_SUDO_PASSWORD:-}" ]; then
    export SUDO_ASKPASS="$HOME/.caelestia-install-helpers/caelestia-askpass"
    exec /usr/bin/sudo -A "$@"
else
    exec /usr/bin/sudo "$@"
fi
EOF
chmod +x "$HELPERS_DIR/sudo"

# Exportar las variables para activar el wrapper
export PATH="$HELPERS_DIR:$PATH"
export CAELESTIA_SUDO_PASSWORD="$sudo_password"

# Mantener vivo el token de sudo en segundo plano
(
    while true; do
        sudo -v
        sleep 30
        kill -0 "$$" || exit
    done 2>/dev/null
) &
SUDO_KEEP_ALIVE_PID=$!

echo ""

cleanup() {
    # Disable exit-on-error inside cleanup so it runs to completion even if some command fails
    set +e
    
    # Disable traps to prevent recursion/conflicts on interrupt
    trap - EXIT ERR INT TERM
    
    # Stop the active spinner if running
    stop_spinner
    
    if [ "${LAYOUT_PRINTED:-0}" -eq 1 ]; then
        # Clear the detailed status and log viewport (lines 12 to 17)
        echo -ne "\e[5A"
        for i in {1..5}; do
            echo -ne "\e[2K\r\e[1B"
        done
        echo -ne "\e[2K\r"
        echo -ne "\e[5A\r"
    fi
    
    # Kill the sudo keep alive daemon
    if [ -n "${SUDO_KEEP_ALIVE_PID:-}" ]; then
        kill "$SUDO_KEEP_ALIVE_PID" 2>/dev/null || true
    fi
    # Clean up sudo helpers
    if [ -d "$HOME/.caelestia-install-helpers" ]; then
        rm -rf "$HOME/.caelestia-install-helpers" 2>/dev/null || true
    fi
    
    # Remove temporary environment file if exists
    if [ -f "$ENV_FILE" ]; then
        rm -f "$ENV_FILE" 2>/dev/null || true
    fi
    
    # Si la instalación falló (p. ej., por interrupción o comando fallido),
    # actualizamos el paso actual in-situ con una cruz roja
    if [ "$INSTALL_SUCCESS" -ne 1 ] && [ "${CURRENT_STEP:-0}" -gt 0 ]; then
        local elapsed=$(( $(date +%s) - START_TIME ))
        local lines_up=$((11 - CURRENT_STEP))
        echo -ne "\e[${lines_up}A\e[2K\r ${RED}✘${NC} [$(printf "%02d" $CURRENT_STEP)/10] ${RED}${STEP_MSGS[CURRENT_STEP]}${NC} (${elapsed}s, fallido)\e[${lines_up}B\r"
    fi
    
    # 1. Kill any other child processes of this script (like pacman, yay, paru, git, etc.)
    local child_pids
    child_pids=$(pgrep -P $$ 2>/dev/null)
    if [ -n "$child_pids" ]; then
        # Send SIGTERM first to allow clean shutdown
        for pid in $child_pids; do
            kill -TERM "$pid" 2>/dev/null || true
        done
        # Give them a brief moment to finish
        sleep 0.2
        # Forcefully kill any child process that is still running
        for pid in $child_pids; do
            kill -9 "$pid" 2>/dev/null || true
        done
    fi
    
    # 2. Show cursor and reset text formatting immediately
    echo -ne "\e[?25h"  # Show cursor
    echo -ne "\e[0m"    # Reset text formatting
    stty sane 2>/dev/null || true
    
    # 3. Print final status message (Responsive and elegant, borderless layout)
    local width=$(tput cols 2>/dev/null || echo 80)
    if [ $width -gt 72 ]; then width=72; fi
    local sep_line=""
    for ((i=0; i<width; i++)); do sep_line="${sep_line}─"; done
    
    if [ "$INSTALL_SUCCESS" -eq 1 ]; then
        echo -e "\n${BLUE}${sep_line}${NC}"
        echo -e "       ${BLUE}¡INSTALACIÓN COMPLETADA CON ÉXITO!  (•‿•)${NC}"
        echo -e "${BLUE}${sep_line}${NC}"
        echo -e "  Tu entorno Caelestia personalizado ha sido instalado correctamente."
        echo -e "  Tu código de quickshell se enlazó a ~/.config/quickshell/caelestia"
        echo -e "  Puedes iniciar el shell con: ${YELLOW}caelestia shell -d${NC}"
        echo -e "  ¡Disfruta de tus nuevos dots!"
        echo -e "${BLUE}${sep_line}${NC}\n"
    else
        echo -e "\n${RED}${sep_line}${NC}"
        echo -e "       ${RED}¡HUBO UN ERROR EN LA INSTALACIÓN!  (T_T)${NC}"
        echo -e "${RED}${sep_line}${NC}"
        echo -e "  El instalador se interrumpió debido a un fallo en alguna tarea."
        echo -e "  Por favor, revisa los mensajes de error mostrados arriba o consulta"
        echo -e "  el archivo de log detallado en:"
        echo -e "${RED}${sep_line}${NC}"
        echo -e "  ${YELLOW}Log de instalación: ${LOG_FILE}${NC}\n"
    fi
    
    # If not successful (e.g. aborted by Ctrl+C or failed), force exit with error code
    if [ "$INSTALL_SUCCESS" -ne 1 ]; then
        exit 1
    fi
}
trap cleanup EXIT ERR INT TERM

update_header() {
    local completed="$1"
    local total=10
    local lines_up=16
    echo -ne "\e[${lines_up}A\e[2K\r${BLUE}[+] Instalando Caelestia [${completed}/${total}]${NC}\e[${lines_up}B\r"
}

start_spinner() {
    local step="$1"
    local msg="$2"
    local lines_up=$((16 - step))
    
    stop_spinner
    
    (
        local spinner=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
        local i=0
        local start_t=$(date +%s)
        while true; do
            local elapsed=$(( $(date +%s) - start_t ))
            local log_lines=()
            if [ -f "$LOG_FILE" ]; then
                mapfile -t log_lines < <(tail -n 20 "$LOG_FILE" 2>/dev/null | tr '\r' '\n' | grep -v '^$' | tail -n 5)
            fi
            for ((l=${#log_lines[@]}; l<5; l++)); do
                log_lines=("" "${log_lines[@]}")
            done
            
            echo -ne "\e[${lines_up}A\e[2K\r ${BLUE}${spinner[i]}${NC} [$(printf "%02d" $step)/10] ${CYAN}${msg}${NC} ... (${elapsed}s)\e[${lines_up}B\r"
            
            echo -ne "\e[4A"
            for ((l=0; l<5; l++)); do
                local line="${log_lines[l]}"
                line=$(echo "$line" | sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/^[[:space:]]*//' | cut -c 1-72)
                if [ $l -lt 4 ]; then
                    echo -ne "\e[2K\r ${GRAY}│${NC} ${GRAY}${line}${NC}\e[1B"
                  else
                    echo -ne "\e[2K\r ${GRAY}│${NC} ${GRAY}${line}${NC}\r"
                fi
            done
            
            i=$(( (i + 1) % 10 ))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
}
    
stop_spinner() {
    if [ -n "${SPINNER_PID:-}" ]; then
        kill -9 "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        unset SPINNER_PID
    fi
}
    
end_step() {
    local step="$1"
    local status="$2"
    local msg="$3"
    local start_t="$4"
    local lines_up=$((16 - step))
    
    stop_spinner
    
    local elapsed=$(( $(date +%s) - start_t ))
    
    echo -ne "\e[${lines_up}A\e[2K\r"
    if [ "$status" -eq 0 ]; then
        echo -ne " ${GREEN}✔${NC} [$(printf "%02d" $step)/10] ${NC}${msg}${NC} (${elapsed}s)"
    elif [ "$status" -eq 2 ]; then
        echo -ne " ${YELLOW}❯${NC} [$(printf "%02d" $step)/10] ${YELLOW}${msg}${NC} (omitido)"
    else
        echo -ne " ${RED}✘${NC} [$(printf "%02d" $step)/10] ${RED}${msg}${NC} (${elapsed}s)"
    fi
    echo -ne "\e[${lines_up}B\r"
}

run_step() {
    local step="$1"
    local msg="$2"
    shift 2
    
    CURRENT_STEP="$step"
    START_TIME=$(date +%s)
    
    start_spinner "$step" "$msg"
    
    # Temporarily disable set -e in the main shell, but run the step function in a subshell with set -eo pipefail active
    set +e
    ( set -eo pipefail; "$@" ) >> "$LOG_FILE" 2>&1
    local status=$?
    set -e
    
    end_step "$step" "$status" "$msg" "$START_TIME"
    
    if [ "$status" -eq 0 ] || [ "$status" -eq 2 ]; then
        # If there's a temporary environment file, source it to import global variables from the subshell step
        if [ -f "$ENV_FILE" ]; then
            source "$ENV_FILE"
            rm -f "$ENV_FILE"
        fi
        STEPS_COMPLETED=$((STEPS_COMPLETED + 1))
        update_header "$STEPS_COMPLETED"
        return 0
    else
        # If it failed, exit the main shell with the status
        exit "$status"
    fi
}

# Helper to safely create symlinks
create_symlink() {
    local src="$1"
    local dest="$2"
    
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        log "Sobreescribiendo configuración existente en $dest..." >> "$LOG_FILE" 2>&1
        rm -rf "$dest" >> "$LOG_FILE" 2>&1
    fi
    
    mkdir -p "$(dirname "$dest")" >> "$LOG_FILE" 2>&1
    ln -s "$src" "$dest" >> "$LOG_FILE" 2>&1
}

# Helper to clone or update Zsh plugins
clone_or_update_plugin() {
    local repo_url="$1"
    local dest_dir="$2"
    if [ -d "$dest_dir" ]; then
        log "Actualizando plugin Zsh en $dest_dir..." >> "$LOG_FILE" 2>&1
        (cd "$dest_dir" && git pull) >> "$LOG_FILE" 2>&1
    else
        log "Clonando plugin Zsh de $repo_url..." >> "$LOG_FILE" 2>&1
        git clone "$repo_url" "$dest_dir" >> "$LOG_FILE" 2>&1
    fi
}

# List of essential system packages (excluding bloat terminal/browser)
SYSTEM_PACKAGES=(
    hyprland
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    hyprpicker
    wl-clipboard
    cliphist
    inotify-tools
    wireplumber
    trash-cli
    jq
    eza
    less
    adw-gtk-theme
    papirus-icon-theme
    ttf-jetbrains-mono-nerd
    ttf-hack-nerd
    fastfetch
    btop
    starship
    fish # Required by caelestia-shell PKGBUILD internally
    # Fonts and Emojis (including CJK/Chinese support)
    noto-fonts-cjk
    noto-fonts-emoji
    wqy-zenhei
    adobe-source-han-sans-cn-fonts
    adobe-source-han-serif-cn-fonts
    # Zsh and terminal utilities
    zsh
    fzf
    bat
    atuin
    # Keyboard shortcut applications
    kitty
    firefox
    vivaldi
    nemo
    qps
    pavucontrol
    thunar
    # Display manager
    sddm
)

AUR_PACKAGES=(
    caelestia-cli
    caelestia-shell-git
    apple_cursor
    lorien-bin
    ttf-iosevka-nerd
    visual-studio-code-bin
    sddm-silent-theme
)

# Define functions for each step
step_1() {
    # Determine installation directory (clone if piped via curl | bash)
    if [ -f "$CURRENT_DIR/install.sh" ] && [ -d "$CURRENT_DIR/hypr" ]; then
        INSTALL_DIR="$CURRENT_DIR"
        log "Ejecutando desde el directorio local: $INSTALL_DIR" >> "$LOG_FILE" 2>&1
    else
        INSTALL_DIR="$HOME/.jesdev12u-hyprland-dots"
        if [ -d "$INSTALL_DIR" ]; then
            log "Actualizando repositorio local en $INSTALL_DIR..." >> "$LOG_FILE" 2>&1
            cd "$INSTALL_DIR"
            git pull >> "$LOG_FILE" 2>&1
        else
            log "Clonando repositorio en $INSTALL_DIR..." >> "$LOG_FILE" 2>&1
            git clone "$REPO_URL" "$INSTALL_DIR" >> "$LOG_FILE" 2>&1
        fi
    fi

    # Detect or install AUR helper
    AUR_HELPER=""
    if command -v paru >/dev/null 2>&1; then
        AUR_HELPER="paru"
        log "Se detectó paru como helper de AUR." >> "$LOG_FILE" 2>&1
    elif command -v yay >/dev/null 2>&1; then
        AUR_HELPER="yay"
        log "Se detectó yay como helper de AUR." >> "$LOG_FILE" 2>&1
    else
        log "Instalando dependencias base y paru-bin (AUR Helper)..." >> "$LOG_FILE" 2>&1
        sudo pacman -S --needed --noconfirm git base-devel >> "$LOG_FILE" 2>&1
        local tmp_dir
        tmp_dir=$(mktemp -d)
        cd "$tmp_dir"
        git clone https://aur.archlinux.org/paru-bin.git >> "$LOG_FILE" 2>&1
        cd paru-bin
        makepkg -si --noconfirm >> "$LOG_FILE" 2>&1
        cd "$CURRENT_DIR"
        rm -rf "$tmp_dir" >> "$LOG_FILE" 2>&1
        AUR_HELPER="paru"
    fi

    # Guardar variables globales para transferir al proceso padre
    echo "AUR_HELPER=\"$AUR_HELPER\"" > "$ENV_FILE"
    echo "INSTALL_DIR=\"$INSTALL_DIR\"" >> "$ENV_FILE"
}

step_2() {
    if [ -f "$INSTALL_DIR/pacman.conf" ]; then
        log "Aplicando configuración de pacman.conf (multilib, ILoveCandy, etc.)...." >> "$LOG_FILE" 2>&1
        if [ ! -f /etc/pacman.conf.bak ]; then
            sudo cp /etc/pacman.conf /etc/pacman.conf.bak >> "$LOG_FILE" 2>&1
        fi
        sudo cp "$INSTALL_DIR/pacman.conf" /etc/pacman.conf >> "$LOG_FILE" 2>&1
        sudo pacman -Sy >> "$LOG_FILE" 2>&1
    else
        log "No se encontró pacman.conf en $INSTALL_DIR, omitiendo configuración." >> "$LOG_FILE" 2>&1
    fi
}

step_3() {
    if [ "$BACKUP_CONFIG" -eq 1 ]; then
        log "Realizando copia de seguridad de ~/.config en ~/.config.bak..." >> "$LOG_FILE" 2>&1
        if [ -d "$CONFIG_DIR.bak" ]; then
            warning "Ya existe un respaldo ~/.config.bak. Se sobreescribirá." >> "$LOG_FILE" 2>&1
            rm -rf "$CONFIG_DIR.bak" >> "$LOG_FILE" 2>&1
        fi
        if [ -d "$CONFIG_DIR" ]; then
            cp -r "$CONFIG_DIR" "$CONFIG_DIR.bak" >> "$LOG_FILE" 2>&1
        fi
        success "Copia de seguridad completada." >> "$LOG_FILE" 2>&1
        return 0
    else
        if [ ! -d "$CONFIG_DIR" ]; then
            log "Respaldo de ~/.config omitido porque la carpeta no existe." >> "$LOG_FILE" 2>&1
        else
            log "Respaldo de ~/.config omitido por elección del usuario." >> "$LOG_FILE" 2>&1
        fi
        return 2
    fi
}

step_4() {
    log "Instalando paquetes esenciales del sistema..." >> "$LOG_FILE" 2>&1
    sudo pacman -S --needed --noconfirm --overwrite "*" "${SYSTEM_PACKAGES[@]}" >> "$LOG_FILE" 2>&1
}

step_5() {
    log "Instalando paquetes esenciales desde AUR..." >> "$LOG_FILE" 2>&1
    
    local AUR_PACKAGES_TO_INSTALL=()
    for pkg in "${AUR_PACKAGES[@]}"; do
        # 1. Evitar conflicto entre versión git y normal de caelestia-shell
        if [ "$pkg" = "caelestia-shell-git" ]; then
            if pacman -Qi caelestia-shell >/dev/null 2>&1 || pacman -Qi caelestia-shell-git >/dev/null 2>&1; then
                log "   -> caelestia-shell ya está instalado. Omitiendo $pkg para evitar conflictos." >> "$LOG_FILE" 2>&1
                continue
            fi
        fi
        # 2. Evitar conflicto entre versión git y normal de caelestia-cli
        if [ "$pkg" = "caelestia-cli" ]; then
            if pacman -Qi caelestia-cli >/dev/null 2>&1 || pacman -Qi caelestia-cli-git >/dev/null 2>&1; then
                log "   -> caelestia-cli ya está instalado. Omitiendo $pkg para evitar conflictos." >> "$LOG_FILE" 2>&1
                continue
            fi
        fi
        # 3. Evitar conflicto de VS Code (code vs visual-studio-code-bin)
        if [ "$pkg" = "visual-studio-code-bin" ]; then
            if pacman -Qi code >/dev/null 2>&1 || pacman -Qi visual-studio-code-bin >/dev/null 2>&1; then
                log "   -> Visual Studio Code ya está instalado. Omitiendo $pkg para evitar conflictos." >> "$LOG_FILE" 2>&1
                continue
            fi
        fi
        # 4. Evitar conflicto de apple_cursor si la carpeta física ya existe o el paquete está instalado
        if [ "$pkg" = "apple_cursor" ]; then
            if [ -d "/usr/share/icons/macOS" ] || pacman -Qi apple_cursor >/dev/null 2>&1; then
                log "   -> Cursor de Apple ya está instalado o los archivos ya existen en el sistema. Omitiendo $pkg." >> "$LOG_FILE" 2>&1
                continue
            fi
        fi
        # Agregar paquete filtrado a la lista
        AUR_PACKAGES_TO_INSTALL+=("$pkg")
    done
    
    if [ ${#AUR_PACKAGES_TO_INSTALL[@]} -gt 0 ]; then
        # Usamos echo para responder automáticamente con 'Enter' ante selección de proveedores
        # y --overwrite "*" para forzar la sobrescritura de archivos en conflicto si hiciera falta
        echo | $AUR_HELPER -S --needed --noconfirm --overwrite "*" "${AUR_PACKAGES_TO_INSTALL[@]}" >> "$LOG_FILE" 2>&1
    else
        log "Todos los paquetes de AUR ya están instalados." >> "$LOG_FILE" 2>&1
    fi
}

step_6() {
    log "Instalando archivos de configuración personalizada..." >> "$LOG_FILE" 2>&1
    create_symlink "$INSTALL_DIR/hypr" "$CONFIG_DIR/hypr"
    create_symlink "$INSTALL_DIR/quickshell/caelestia" "$CONFIG_DIR/quickshell/caelestia"
    create_symlink "$INSTALL_DIR/starship.toml" "$CONFIG_DIR/starship.toml"
    create_symlink "$INSTALL_DIR/fastfetch" "$CONFIG_DIR/fastfetch"
    create_symlink "$INSTALL_DIR/btop" "$CONFIG_DIR/btop"
    create_symlink "$INSTALL_DIR/thunar" "$CONFIG_DIR/thunar"
    create_symlink "$INSTALL_DIR/uwsm" "$CONFIG_DIR/uwsm"
    create_symlink "$INSTALL_DIR/kitty" "$CONFIG_DIR/kitty"
    create_symlink "$INSTALL_DIR/zshrc" "$HOME/.zshrc"
    create_symlink "$INSTALL_DIR/caelestia" "$CONFIG_DIR/caelestia"
}

step_7() {
    log "Instalando fondos de pantalla..." >> "$LOG_FILE" 2>&1
    mkdir -p "$HOME/Pictures/Wallpapers" >> "$LOG_FILE" 2>&1
    for wp in "$INSTALL_DIR/wallpapers/"*; do
        if [ -f "$wp" ]; then
            ln -sf "$wp" "$HOME/Pictures/Wallpapers/$(basename "$wp")" >> "$LOG_FILE" 2>&1
        fi
    done
    
    chmod +x "$CONFIG_DIR/hypr/scripts/configs.sh" >> "$LOG_FILE" 2>&1
    chmod +x "$CONFIG_DIR/hypr/scripts/wsaction.sh" >> "$LOG_FILE" 2>&1
    chmod +x "$CONFIG_DIR/caelestia/toggle_whiteboard.sh" >> "$LOG_FILE" 2>&1
}

step_8() {
    log "Instalando plugins de Zsh..." >> "$LOG_FILE" 2>&1
    mkdir -p "$HOME/.zsh" >> "$LOG_FILE" 2>&1
    
    clone_or_update_plugin "https://github.com/zsh-users/zsh-autosuggestions" "$HOME/.zsh/zsh-autosuggestions"
    clone_or_update_plugin "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$HOME/.zsh/zsh-syntax-highlighting"
    clone_or_update_plugin "https://github.com/Aloxaf/fzf-tab.git" "$HOME/.zsh/fzf-tab"
}

step_9() {
    log "Inicializando esquema de colores..." >> "$LOG_FILE" 2>&1
    if ! [ -f "$STATE_DIR/caelestia/scheme.json" ]; then
        caelestia scheme set -n shadotheme >> "$LOG_FILE" 2>&1 || true
        sleep 0.5
    fi
    
    hyprctl reload >> "$LOG_FILE" 2>&1 || true
    
    if [ -f "$INSTALL_DIR/sddm.conf" ]; then
        log "Aplicando configuración de SDDM (tema silent)..." >> "$LOG_FILE" 2>&1
        if [ ! -f /etc/sddm.conf.bak ]; then
            sudo cp /etc/sddm.conf /etc/sddm.conf.bak >> "$LOG_FILE" 2>&1 || true
        fi
        sudo cp "$INSTALL_DIR/sddm.conf" /etc/sddm.conf >> "$LOG_FILE" 2>&1
        sudo systemctl enable sddm.service >> "$LOG_FILE" 2>&1 || true
    fi
    
    if [ -d "$INSTALL_DIR/grub-theme" ]; then
        log "Instalando tema de GRUB..." >> "$LOG_FILE" 2>&1
        sudo mkdir -p /boot/grub/themes/custom-theme >> "$LOG_FILE" 2>&1
        sudo cp -r "$INSTALL_DIR/grub-theme/"* /boot/grub/themes/custom-theme/ >> "$LOG_FILE" 2>&1
        
        if [ -f /etc/default/grub ]; then
            log "Configurando /etc/default/grub..." >> "$LOG_FILE" 2>&1
            if [ ! -f /etc/default/grub.bak ]; then
                sudo cp /etc/default/grub /etc/default/grub.bak >> "$LOG_FILE" 2>&1
            fi
            if grep -q "^GRUB_THEME=" /etc/default/grub; then
                sudo sed -i 's|^GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/custom-theme/theme.txt"|' /etc/default/grub >> "$LOG_FILE" 2>&1
            else
                echo 'GRUB_THEME="/boot/grub/themes/custom-theme/theme.txt"' | sudo /usr/bin/tee -a /etc/default/grub >> "$LOG_FILE" 2>&1
            fi
            log "Regenerando configuración de GRUB (grub-mkconfig)..." >> "$LOG_FILE" 2>&1
            sudo grub-mkconfig -o /boot/grub/grub.cfg >> "$LOG_FILE" 2>&1 || true
        fi
    fi
}

step_10() {
    if [ "$SHELL" != "$(which zsh)" ]; then
        log "Cambiando shell predeterminado a zsh para $USER..." >> "$LOG_FILE" 2>&1
        sudo chsh -s "$(which zsh)" "$USER" >> "$LOG_FILE" 2>&1
    fi
}

# Print layout
echo -e "${BLUE}[+] Instalando Caelestia [0/10]${NC}"
for i in {1..10}; do
    echo -e " ${GRAY}⠇${NC} [$(printf "%02d" $i)/10] ${GRAY}${STEP_MSGS[i]}${NC}"
done
echo -e "  ${GRAY}────────────────────────────────────────────────────────────────────────${NC}"
for i in {1..4}; do
    echo -e " ${GRAY}│${NC}"
done
echo -ne " ${GRAY}│${NC}"
LAYOUT_PRINTED=1

echo -ne "\e[?25l" # Hide cursor

# Run steps
run_step 1 "${STEP_MSGS[1]}" step_1
run_step 2 "${STEP_MSGS[2]}" step_2
run_step 3 "${STEP_MSGS[3]}" step_3
run_step 4 "${STEP_MSGS[4]}" step_4
run_step 5 "Instalando paquetes de AUR ($AUR_HELPER)" step_5
run_step 6 "${STEP_MSGS[6]}" step_6
run_step 7 "${STEP_MSGS[7]}" step_7
run_step 8 "${STEP_MSGS[8]}" step_8
run_step 9 "${STEP_MSGS[9]}" step_9
run_step 10 "${STEP_MSGS[10]}" step_10

# Mark installation as successful before exiting so the trap knows to print the success box
INSTALL_SUCCESS=1
