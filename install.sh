#!/bin/bash
# ==============================================================================
# Caelestia Custom Installer (POSIX/Bash)
# A clean, fast, dependency-free installer for customized Caelestia dotfiles.
# ==============================================================================
set -e

# Estado de la instalación
INSTALL_SUCCESS=0

REPO_URL="https://github.com/JesDev12U/jesdev12u-hyprland-dots.git"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[1;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper output functions
log() { echo -e "${CYAN}:: $1${NC}"; }
success() { echo -e "${GREEN}:: $1${NC}"; }
warning() { echo -e "${YELLOW}Warning: $1${NC}"; }
error() { echo -e "${RED}Error: $1${NC}" >&2; }

# Setup animator communication files
STATUS_STEP_FILE=$(mktemp)
STATUS_MSG_FILE=$(mktemp)
echo "0" > "$STATUS_STEP_FILE"
echo "Iniciando instalación..." > "$STATUS_MSG_FILE"

cleanup() {
    # Disable exit-on-error inside cleanup so it runs to completion even if some command fails
    set +e
    
    # Disable traps to prevent recursion/conflicts on interrupt
    trap - EXIT ERR INT TERM
    
    # 1. Kill background animator immediately
    if [ -n "$ANIMATOR_PID" ]; then
        kill "$ANIMATOR_PID" 2>/dev/null || true
        wait "$ANIMATOR_PID" 2>/dev/null || true
    fi
    
    # 2. Kill any other child processes of this script (like pacman, yay, paru, git, etc.)
    local child_pids
    child_pids=$(pgrep -P $$ 2>/dev/null)
    if [ -n "$child_pids" ]; then
        # Send SIGTERM first to allow clean shutdown
        for pid in $child_pids; do
            if [ "$pid" != "$ANIMATOR_PID" ]; then
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
        # Give them a brief moment to finish
        sleep 0.2
        # Forcefully kill any child process that is still running
        for pid in $child_pids; do
            if [ "$pid" != "$ANIMATOR_PID" ]; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
    fi
    
    # 3. Show cursor and reset text formatting immediately
    echo -ne "\e[?25h"  # Show cursor
    echo -ne "\e[0m"    # Reset text formatting
    stty sane 2>/dev/null || true
    
    # 4. Restore the scroll region to the full height of the terminal
    echo -ne "\e[r"
    
    # 5. Save the current cursor position (now that full scroll region is active)
    # We use DEC Save Cursor (\e7) and Restore Cursor (\e8) which are more robust
    echo -ne "\e7"
    
    # 6. Clear the top two lines where the progress bar and separator were
    echo -ne "\e[1;1H\e[K"
    echo -ne "\e[2;1H\e[K"
    
    # 7. Restore the cursor to the end of the output
    echo -ne "\e8"
    echo -e "\n"
    
    # 8. Print final status message
    if [ "$INSTALL_SUCCESS" -eq 1 ]; then
        echo -e "\n${BLUE}╭────────────────────────────────────────────────────────────────────────╮${NC}"
        echo -e "${BLUE}│            ¡INSTALACIÓN COMPLETADA CON ÉXITO!  (•‿•)                   │${NC}"
        echo -e "${BLUE}├────────────────────────────────────────────────────────────────────────┤${NC}"
        echo -e "${BLUE}│${NC}  Tu entorno Caelestia personalizado ha sido instalado correctamente.   ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC}  Tu código de quickshell se enlazó a ~/.config/quickshell/caelestia    ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC}  Puedes iniciar el shell con: ${YELLOW}caelestia shell -d                       ${BLUE}│${NC}"
        echo -e "${BLUE}│${NC}  ¡Disfruta de tus nuevos dots!                                         ${BLUE}│${NC}"
        echo -e "${BLUE}╰────────────────────────────────────────────────────────────────────────╯${NC}\n"
    else
        echo -e "\n${RED}╭────────────────────────────────────────────────────────────────────────╮${NC}"
        echo -e "${RED}│                 ¡HUBO UN ERROR EN LA INSTALACIÓN!  (T_T)               │${NC}"
        echo -e "${RED}├────────────────────────────────────────────────────────────────────────┤${NC}"
        echo -e "${RED}│${NC}  El instalador se interrumpió debido a un fallo en alguna tarea.       ${RED}│${NC}"
        echo -e "${RED}│${NC}  Por favor, revisa los mensajes de error mostrados arriba para        ${RED}│${NC}"
        echo -e "${RED}│${NC}  identificar el problema.                                               ${RED}│${NC}"
        echo -e "${RED}╰────────────────────────────────────────────────────────────────────────╯${NC}\n"
    fi
    rm -f "$STATUS_STEP_FILE" "$STATUS_MSG_FILE"
    
    # If not successful (e.g. aborted by Ctrl+C or failed), force exit with error code
    if [ "$INSTALL_SUCCESS" -ne 1 ]; then
        exit 1
    fi
}
trap cleanup EXIT ERR INT TERM

animate_status_bar() {
    local chars="/-\|"
    local i=0
    local pulse_chars=("░" "▒" "▓" "█" "▓" "▒")
    local pulse_idx=0
    
    # Hide cursor
    echo -ne "\e[?25l"
    
    # Enable clean exit (catch both TERM and INT to show cursor)
    trap 'echo -ne "\e[?25h"; exit 0' TERM INT
    
    while true; do
        local step=$(cat "$STATUS_STEP_FILE" 2>/dev/null || echo "0")
        local msg=$(cat "$STATUS_MSG_FILE" 2>/dev/null || echo "")
        
        # Calculate progress bar
        local total=10
        local percent=$(( step * 100 / total ))
        local completed=$(( step * 25 / total ))
        local remaining=$(( 25 - completed ))
        
        local bar=""
        for ((k=0; k<completed; k++)); do bar="${bar}█"; done
        
        local pulse_char=${pulse_chars[$pulse_idx]}
        pulse_idx=$(( (pulse_idx + 1) % 6 ))
        
        local rem_bar=""
        if [ $remaining -gt 0 ]; then
            rem_bar="${pulse_char}"
            for ((k=1; k<remaining; k++)); do rem_bar="${rem_bar}░"; done
        fi
        
        local spinner="${chars:i++%4:1}"
        
        # Save cursor, move to line 1, draw, and restore cursor
        echo -ne "\e[s"
        echo -ne "\e[1;1H"
        
        local text="  ${BLUE}Progreso: [${BLUE}${bar}${rem_bar}${BLUE}] ${percent}% (${step}/${total}) ${spinner} — ${CYAN}${msg}${NC}"
        echo -ne "${text}\e[K"
        echo -ne "\e[u"
        
        sleep 0.15
    done
}

# Clear the terminal first to prevent any overlay/mixing with old output
clear

# Start animator in background
animate_status_bar &
ANIMATOR_PID=$!

# Reserve lines 1 and 2 for the progress bar and visual separator padding.
# Set the scrolling region from line 3 to the bottom of the screen.
echo ""
echo -e "${BLUE} ────────────────────────────────────────────────────────────────────────${NC}"
echo -ne "\e[3;1H"
lines=$(tput lines 2>/dev/null || echo 24)
echo -ne "\e[3;${lines}r"

# Spacing (padding) under the separator line before the ASCII art
echo ""
echo ""

show_progress() {
    echo "$1" > "$STATUS_STEP_FILE"
    echo "$2" > "$STATUS_MSG_FILE"
}

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

# Check if running on Arch Linux
if [ ! -f /etc/arch-release ]; then
    error "Este instalador está diseñado únicamente para Arch Linux."
    exit 1
fi

show_progress 1 "Detectando e instalando helper de AUR"
# Detect or install AUR helper
AUR_HELPER=""
if command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
elif command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
else
    log "Instalando dependencias base y paru (AUR Helper)..."
    sudo pacman -S --needed --noconfirm git base-devel
    cd /tmp
    git clone https://aur.archlinux.org/paru.git
    cd paru
    makepkg -si --noconfirm
    cd ..
    rm -rf paru
    AUR_HELPER="paru"
fi
success "Helper de AUR detectado/instalado: $AUR_HELPER"

# Setup variables
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"

# Determine installation directory (clone if piped via curl | bash)
if [ -f "$CURRENT_DIR/install.sh" ] && [ -d "$CURRENT_DIR/hypr" ]; then
    INSTALL_DIR="$CURRENT_DIR"
    log "Ejecutando desde el directorio local: $INSTALL_DIR"
else
    INSTALL_DIR="$HOME/.jesdev12u-hyprland-dots"
    if [ -d "$INSTALL_DIR" ]; then
        log "Actualizando repositorio local en $INSTALL_DIR..."
        cd "$INSTALL_DIR"
        git pull
    else
        log "Clonando repositorio en $INSTALL_DIR..."
        git clone "$REPO_URL" "$INSTALL_DIR"
    fi
fi

show_progress 2 "Configurando Pacman (ILoveCandy y multilib)"
# Apply custom pacman.conf
if [ -f "$INSTALL_DIR/pacman.conf" ]; then
    log "Aplicando configuración de pacman.conf (multilib, ILoveCandy, etc.)..."
    if [ ! -f /etc/pacman.conf.bak ]; then
        sudo cp /etc/pacman.conf /etc/pacman.conf.bak
    fi
    sudo cp "$INSTALL_DIR/pacman.conf" /etc/pacman.conf
    # Refresh databases
    sudo pacman -Sy
fi

show_progress 3 "Realizando respaldo de la carpeta ~/.config"
# Ask for backup
echo -ne "\e[?25h" # Temporarily show cursor for user prompt
echo -e "${BLUE}:: ¿Deseas hacer un respaldo de tu carpeta ~/.config actual? [Y/n]${NC}"
read -r -p "=> " backup_choice
echo -ne "\e[?25l" # Hide cursor again
if [[ "$backup_choice" != "n" && "$backup_choice" != "N" ]]; then
    log "Realizando copia de seguridad de ~/.config en ~/.config.bak..."
    if [ -d "$CONFIG_DIR.bak" ]; then
        warning "Ya existe un respaldo ~/.config.bak. Se sobreescribirá."
        rm -rf "$CONFIG_DIR.bak"
    fi
    cp -r "$CONFIG_DIR" "$CONFIG_DIR.bak"
    success "Copia de seguridad completada."
fi

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
    app2unit
    qtengine
)

show_progress 4 "Instalando paquetes esenciales del sistema con pacman"
# Install packages
log "Instalando paquetes esenciales del sistema..."
sudo pacman -S --needed --noconfirm "${SYSTEM_PACKAGES[@]}"

show_progress 5 "Instalando paquetes de AUR ($AUR_HELPER)"
log "Instalando paquetes esenciales desde AUR..."
$AUR_HELPER -S --needed --noconfirm "${AUR_PACKAGES[@]}"

# Helper to safely create symlinks
create_symlink() {
    local src="$1"
    local dest="$2"
    
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        log "Sobreescribiendo configuración existente en $dest..."
        rm -rf "$dest"
    fi
    
    mkdir -p "$(dirname "$dest")"
    ln -s "$src" "$dest"
}

show_progress 6 "Creando enlaces simbólicos de las configuraciones"
log "Instalando archivos de configuración personalizada..."

# Link configurations
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

show_progress 7 "Instalando y enlazando fondos de pantalla"
# Link wallpapers
log "Instalando fondos de pantalla..."
mkdir -p "$HOME/Pictures/Wallpapers"
for wp in "$INSTALL_DIR/wallpapers/"*; do
    if [ -f "$wp" ]; then
        ln -sf "$wp" "$HOME/Pictures/Wallpapers/$(basename "$wp")"
    fi
done

# Make scripts executable
chmod +x "$CONFIG_DIR/hypr/scripts/configs.sh"
chmod +x "$CONFIG_DIR/hypr/scripts/wsaction.sh"
chmod +x "$CONFIG_DIR/caelestia/toggle_whiteboard.sh"

show_progress 8 "Clonando e instalando plugins de Zsh"
log "Instalando plugins de Zsh..."
mkdir -p "$HOME/.zsh"

clone_or_update_plugin() {
    local repo_url="$1"
    local dest_dir="$2"
    if [ -d "$dest_dir" ]; then
        log "Actualizando plugin Zsh en $dest_dir..."
        (cd "$dest_dir" && git pull)
    else
        log "Clonando plugin Zsh de $repo_url..."
        git clone "$repo_url" "$dest_dir"
    fi
}

clone_or_update_plugin "https://github.com/zsh-users/zsh-autosuggestions" "$HOME/.zsh/zsh-autosuggestions"
clone_or_update_plugin "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$HOME/.zsh/zsh-syntax-highlighting"
clone_or_update_plugin "https://github.com/Aloxaf/fzf-tab.git" "$HOME/.zsh/fzf-tab"

show_progress 9 "Configurando gestores de pantalla y arranque (SDDM/GRUB)"
# Post install config initialization
log "Inicializando esquema de colores..."
if ! [ -f "$STATE_DIR/caelestia/scheme.json" ]; then
    caelestia scheme set -n shadotheme || true
    sleep 0.5
fi

# Reload Hyprland config
hyprctl reload || true

# Apply SDDM configuration
if [ -f "$INSTALL_DIR/sddm.conf" ]; then
    log "Aplicando configuración de SDDM (tema silent)..."
    if [ ! -f /etc/sddm.conf.bak ]; then
        sudo cp /etc/sddm.conf /etc/sddm.conf.bak 2>/dev/null || true
    fi
    sudo cp "$INSTALL_DIR/sddm.conf" /etc/sddm.conf
    # Enable sddm service
    sudo systemctl enable sddm.service || true
fi

# Apply GRUB theme configuration
if [ -d "$INSTALL_DIR/grub-theme" ]; then
    log "Instalando tema de GRUB..."
    sudo mkdir -p /boot/grub/themes/custom-theme
    sudo cp -r "$INSTALL_DIR/grub-theme/"* /boot/grub/themes/custom-theme/
    
    # Update /etc/default/grub
    if [ -f /etc/default/grub ]; then
        log "Configurando /etc/default/grub..."
        if [ ! -f /etc/default/grub.bak ]; then
            sudo cp /etc/default/grub /etc/default/grub.bak
        fi
        if grep -q "^GRUB_THEME=" /etc/default/grub; then
            sudo sed -i 's|^GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/custom-theme/theme.txt"|' /etc/default/grub
        else
            echo 'GRUB_THEME="/boot/grub/themes/custom-theme/theme.txt"' | sudo /usr/bin/tee -a /etc/default/grub >/dev/null
        fi
        # Regenerate grub.cfg
        log "Regenerando configuración de GRUB (grub-mkconfig)..."
        sudo grub-mkconfig -o /boot/grub/grub.cfg || true
    fi
fi

show_progress 10 "Configurando Zsh como shell predeterminado y finalizando"
# Cambiar shell predeterminado a Zsh
if [ "$SHELL" != "$(which zsh)" ]; then
    log "Cambiando shell predeterminado a zsh para $USER..."
    sudo chsh -s "$(which zsh)" "$USER"
fi

# Mark installation as successful before exiting so the trap knows to print the success box
INSTALL_SUCCESS=1
