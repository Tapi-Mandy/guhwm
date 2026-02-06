#!/usr/bin/env bash

# Detect if running via pipe (curl...) and redirect stdin from /dev/tty
if [[ ! -t 0 ]]; then
    exec < /dev/tty
fi

# --- Colors ---
YLW=$'\033[1;33m'; WHT=$'\033[0;37m'; GRA=$'\033[1;30m'
RED=$'\033[0;31m'; GRN=$'\033[0;32m'; MAG=$'\033[1;35m'
PUR=$'\033[0;35m'; CYN=$'\033[0;36m'; BLU=$'\033[1;34m'
ORA=$'\033[0;33m'; NC=$'\033[0m'

# --- Prevent Root Execution ---
if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}[!] ERROR: Do not run this script as root.${NC}"
    echo -e "${RED}==> AUR helpers cannot be built as root. Please log in as a normal user with sudo privileges.${NC}"
    exit 1
fi

# --- Sudo Check ---
if ! sudo -v; then
    echo -e "${RED}[!] Please ensure you have sudo privileges before running this script.${NC}"
    exit 1
fi

# Keep-alive: update existing sudo time stamp if set
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_PID=$!

# --- Logging ---
mkdir -p "$HOME/.cache"
LOG_FILE="$HOME/.cache/guhwizard.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[$(date)]"

# --- Temp Directory Setup ---
TEMP_DIR=$(mktemp -d -t guhwizard.XXXXXX)
trap 'kill $SUDO_PID 2>/dev/null; rm -rf "$TEMP_DIR"' EXIT

# --- Consolidated User Group Setup ---
setup_user_groups() {
    local groups="seat,video,audio,render,dbus"
    echo -e "${GRA}--> Adding $USER to groups: $groups${NC}"
    sudo usermod -aG "$groups" "$USER" 2>/dev/null || true
}

# --- AUR Helper Detection ---
detect_aur() {
    AUR_HELPER=""
    BROKEN_HELPER=""
    local helpers=("yay" "paru" "aurman" "pikaur" "trizen")

    for h in "${helpers[@]}"; do
        # 1. Check if the command exists in the system path
        if command -v "$h" >/dev/null 2>&1; then
            # 2. Check if the command actually runs correctly
            if "$h" --version >/dev/null 2>&1; then
                AUR_HELPER="$h"
                case "$h" in
                    yay) AUR_CLR=$CYN ;;
                    paru) AUR_CLR=$PUR ;;
                    aurman) AUR_CLR=$YLW ;;
                    pikaur) AUR_CLR=$BLU ;;
                    trizen) AUR_CLR=$GRN ;;
                esac
                return 0 # Found a working one!
            else
                # Found it, but it's broken (library error)
                BROKEN_HELPER="$h"
                case "$h" in
                    yay) AUR_CLR=$CYN ;;
                    paru) AUR_CLR=$PUR ;;
                    aurman) AUR_CLR=$YLW ;;
                    pikaur) AUR_CLR=$BLU ;;
                    trizen) AUR_CLR=$GRN ;;
                esac
                return 0
            fi
        fi

        # 3. GHOST CHECK: If command is missing, check if pacman still sees the package
        if pacman -Qq | grep -q "^${h}"; then
            BROKEN_HELPER="$h"
            case "$h" in
                yay) AUR_CLR=$CYN ;;
                paru) AUR_CLR=$PUR ;;
                aurman) AUR_CLR=$YLW ;;
                pikaur) AUR_CLR=$BLU ;;
                trizen) AUR_CLR=$GRN ;;
            esac
            return 0
        fi
    done
}

# --- Smart Installer ---
smart_install() {
    local pkgs=("$@")
    local repo_pkgs=()
    local aur_pkgs=()

    for pkg in "${pkgs[@]}"; do
        # Skip 'oh-my-zsh' here because it is handled by the official curl installer
        [[ "$pkg" == "oh-my-zsh" ]] && continue
        
        # Direct database check
        if pacman -Si "$pkg" >/dev/null 2>&1; then
            repo_pkgs+=("$pkg")
        else
            aur_pkgs+=("$pkg")
        fi
    done

    [[ ${#repo_pkgs[@]} -gt 0 ]] && sudo pacman -S --needed --noconfirm "${repo_pkgs[@]}"
    
    if [[ ${#aur_pkgs[@]} -gt 0 ]]; then
        if [[ -n "$AUR_HELPER" ]]; then
            "$AUR_HELPER" -S --needed --noconfirm "${aur_pkgs[@]}"
        else
            echo -e "${RED}[!] AUR helper missing. Skipping: ${aur_pkgs[*]}${NC}"
        fi
    fi
}

# --- Visuals ---
print_banner() {
    clear
    echo -e "${YLW}"
    cat << "EOF"
                __            _                      __
   ____ ___  __/ /_ _      __(_)___  ____ __________/ /
  / __ `/ / / / __ \ | /| / / /_  / / __ `/ ___/ __  / 
 / /_/ / /_/ / / / / |/ |/ / / / /_/ /_/ / /  / /_/ /  
 \__, /\__,_/_/ /_/|__/|__/_/ /___/\__,_/_/   \__,_/   
/____/
EOF
    echo -e "${NC}"
    echo -e "${YLW}Thank you for trying guhwm! :3${NC}"

    if [[ -n "$AUR_HELPER" ]]; then
        echo -e "${YLW}AUR Helper: ${AUR_CLR}$AUR_HELPER${NC}"
    elif [[ -n "$BROKEN_HELPER" ]]; then
        # If it's broken, show it in Red
        echo -e "${YLW}AUR Helper: ${RED}$BROKEN_HELPER (Needs Repair)${NC}"
    fi
    echo ""
}

# --- Systemd Service Helper ---
enable_service() {
    local service=$1
    echo -e "${GRA}--> Enabling service: $service...${NC}"

    setup_user_groups

    if [[ "$service" == "ly" ]]; then
        echo -e "${GRA}--> Deconflicting Display Managers...${NC}"
        sudo systemctl disable sddm gdm lightdm > /dev/null 2>&1
        sudo rm -f /etc/systemd/system/display-manager.service
        sudo systemctl mask getty@tty2.service > /dev/null 2>&1
    fi

    sudo systemctl daemon-reload
    local unit_to_enable="$service"
    if ! systemctl list-unit-files "${service}.service" >/dev/null 2>&1; then
        if systemctl list-unit-files "${service}@.service" >/dev/null 2>&1; then
            unit_to_enable="${service}@tty2"
            echo -e "${GRA}--> Template unit detected. Using $unit_to_enable...${NC}"
        fi
    fi

    sleep 1
    if sudo systemctl enable --force "$unit_to_enable"; then
        echo -e "${GRN}[SUCCESS] $unit_to_enable enabled.${NC}"
        # Start dbus immediately so other services can use it
        if [[ "$service" == "dbus" ]]; then
            sudo systemctl start dbus 2>/dev/null || true
            sleep 1
        fi
    else
        echo -e "${RED}[ERROR] Systemd could not enable $unit_to_enable${NC}"
        read -rp "${YLW}==> Press Enter to continue...${NC}"
    fi
    sleep 2
}

# --- Menu Helper Function ---
prompt_selection() {
    print_banner
    local title=$1
    local mode=$2
    shift 2
    local options=("$@")
    local count=$((${#options[@]} / 4))
    
    echo -e "${YLW}==> $title${NC}"
    for ((i=0; i<count; i++)); do
        local clr="${options[i*4]}"
        local name="${options[i*4+1]}"
        local desc="${options[i*4+3]}"
        echo -e "$((i+1))) ${clr}${name}${GRA} -- ${WHT}${desc}${NC}"
    done
    
    echo -e "0) None/Skip"
    
    if [[ "$mode" == "multi" ]]; then
        read -rp "Enter numbers (e.g., 1 2 3 or 1,2,3): " choice
        choice="${choice//,/ }"
    else
        read -rp "Select: " choice
    fi

    if [[ "$choice" == "0" || -z "$choice" ]]; then 
        LAST_SELECTION=""
        return 1
    fi

    local pkgs_to_install=()
    for idx in $choice; do
        if [[ "$idx" =~ ^[0-9]+$ ]]; then
            if [[ $idx -gt 0 && $idx -le $count ]]; then
                local pkg_idx=$(( (idx-1) * 4 + 2 ))
                pkgs_to_install+=("${options[pkg_idx]}")
                LAST_SELECTION="${options[pkg_idx]}"

                if [[ "$mode" == "single" ]]; then
                    break
                fi
            else
                echo -e "${RED}[!] Choice $idx is out of range. Skipping...${NC}"
            fi
        else
            echo -e "${ORA}[!] '$idx' is not a valid number. Skipping...${NC}"
        fi
    done

    if [[ ${#pkgs_to_install[@]} -eq 0 ]]; then
        LAST_SELECTION=""
        return 1
    fi

    if [[ "$title" != "AUR Helpers" ]]; then
        # Check if Ly was selected and if it needs Zig to build
        for pkg in "${pkgs_to_install[@]}"; do
            if [[ "$pkg" == "ly" ]]; then
                if ! pacman -Si ly >/dev/null 2>&1; then
                    echo -e "${GRA}--> Ly not in repos. Pre-installing Zig for AUR build...${NC}"
                    sudo pacman -S --needed --noconfirm zig
                    hash -r
                fi
            fi
        done
        smart_install "${pkgs_to_install[@]}"
    fi
    return 0
}

# --- Network Check ---
check_connection() {
    # 1. Check general internet
    if ! curl -Is --connect-timeout 5 https://www.google.com > /dev/null; then
        echo -e "${RED}[!] No internet connection.${NC}"
        return 1
    fi

    # 2. Check AUR specifically
    if ! curl -Is --connect-timeout 5 https://aur.archlinux.org > /dev/null; then
        echo -e "${RED}[!] Internet is fine, but AUR is currently unreachable.${NC}"
        return 1
    fi
    return 0
}

# --- System Preparation ---
prepare_system() {
    print_banner
    echo -e "${YLW}==> Preparing System...${NC}"

    # Call the network check
    echo -e "${GRA}--> Verifying connectivity...${NC}"
    if ! check_connection; then
        exit 1
    fi
    echo -e "${GRN}[OK] Network and AUR are available.${NC}"

    # Update Keyring (Crucial for old installs)
    echo -e "${GRA}--> Refreshing Arch Keyring...${NC}"
    sudo pacman -Sy archlinux-keyring --noconfirm

    # Essential build tools
    echo -e "${GRA}--> Installing base-devel and git...${NC}"
    sudo pacman -S --needed --noconfirm base-devel git
}

# --- Install AUR Helper ---
setup_aur_helper() {
    echo -e "${GRA}--> Syncing package databases...${NC}"
    sudo pacman -Syu --noconfirm

    # If it works, we leave.
    if [[ -n "$AUR_HELPER" ]]; then
        return 0
    fi

    # --- Repair Helper Message ---
    if [[ -n "$BROKEN_HELPER" ]]; then
        echo -e "\n${RED}┌─ Broken AUR Helper Detected ───────────────────────────────┐${NC}"
        echo -e "${RED}│${NC}  ${RED}$BROKEN_HELPER${NC}, is currently failing.                               ${RED}│${NC}"
        echo -e "${RED}│${NC}  This usually happens after a major Pacman update.         ${RED}│${NC}"
        echo -e "${RED}│${NC}  Building a fresh version will fix the library links.      ${RED}│${NC}"
        echo -e "${RED}└────────────────────────────────────────────────────────────┘${NC}\n"
        echo -ne "${WHT}==> Press ${GRN}[Enter]${WHT} to open the repair prompt...${NC}"
        read -r
    fi

    prompt_selection "AUR Helpers" "single" \
        "$CYN" "yay" "yay" "Yet Another Yogurt, fast and feature-rich, written in Go" \
        "$PUR" "paru" "paru" "Feature-packed helper and pacman wrapper written in Rust" \
        "$YLW" "aurman" "aurman" "Known for its security and syntax similarities to pacman" \
        "$BLU" "pikaur" "pikaur" "AUR helper with minimal dependencies" \
        "$GRN" "trizen" "trizen" "Lightweight AUR helper written in Perl"

    if [[ -n "$LAST_SELECTION" ]]; then
        AUR_HELPER="$LAST_SELECTION"
        AUR_HELPER_PKG="$LAST_SELECTION"
        case "$AUR_HELPER" in
            yay)    AUR_CLR=$CYN ;;
            paru)   AUR_CLR=$PUR ;;
            aurman) AUR_CLR=$YLW ;;
            pikaur) AUR_CLR=$BLU ;;
            trizen) AUR_CLR=$GRN ;;
        esac
        unset LAST_SELECTION
    else
        echo -e "${RED}[ERROR] An AUR helper is required.${NC}"; exit 1
    fi

    # --- Conflict Handling ---
    echo -e "${GRA}--> Preparing environment for $AUR_HELPER...${NC}"
    local search_pattern="^${AUR_HELPER}"
    local conflicts=$(pacman -Qq | grep -E "${search_pattern}" 2>/dev/null)

    if [[ -n "$conflicts" ]]; then
        echo -e "${GRN}[+] Cleaning up existing ${AUR_HELPER} files for a fresh start...${NC}"
        sudo pacman -Rns --noconfirm $conflicts 2>/dev/null || true
    fi

    # Pre-install compilers
    if [[ "$AUR_HELPER" == "yay" ]]; then
        sudo pacman -S --needed --noconfirm go
    elif [[ "$AUR_HELPER" == "paru" ]]; then
        sudo pacman -S --needed --noconfirm rust
    fi

    cd "$TEMP_DIR" || exit
    git clone "https://aur.archlinux.org/${AUR_HELPER_PKG}.git"
    cd "${AUR_HELPER_PKG}" || exit 1

    export MAKEFLAGS="-j$(nproc)"
    export PKGEXT='.pkg.tar' 

    if ! makepkg -si --noconfirm; then
        echo -e "${RED}[!] Failed to build AUR helper. Please try manually.${NC}"
        exit 1
    fi

    cd ~ || exit
    hash -r
    detect_aur
    echo -e
    read -rp "${YLW}==> $AUR_HELPER is ready. Press Enter to continue...${NC}"
}

install_base() {
    print_banner
    echo -e "${YLW}==> Installing Base System Packages...${NC}"

    BASE_PKGS=(
        # --- System Utilities ---
        "meson" "ninja" "tar" "curl" "jq" "zip" "unzip"
        "xdg-desktop-portal" "xdg-utils" "xdg-user-dirs" "libxcb" "pcre2"

        # --- Network & Bluetooth Manager ---
        "networkmanager" "network-manager-applet"
        "bluez" "bluez-utils" "blueman"

        # --- Wayland & WM ---
        "glibc" "wayland" "wayland-protocols" "libinput" "libxkbcommon"
        "libdrm" "pixman" "libdisplay-info" "libliftoff" "seatd" "hwdata" "polkit-gnome" 
        "wtype" "wl-clipboard" "wlsunset" "xorg-xwayland" "mangowc-git"

        # --- UI Components ---
        "waybar" "rofi" "swaync" "libnotify"

        # --- Audio Stack ---
        "alsa-utils" "pipewire" "pipewire-pulse" "wireplumber"

        # --- Fonts ---
        "noto-fonts" "noto-fonts-cjk" "noto-fonts-emoji"
        "ttf-jetbrains-mono-nerd" "cantarell-fonts"
    )

    smart_install "${BASE_PKGS[@]}"

    # Initialize standard user directories
    xdg-user-dirs-update
    # Remove some default user directories
    rm -rf Public Templates

    # Essential: Ensure user is in groups for Wayland/Hardware access
    setup_user_groups

    echo -e
    read -rp "${YLW}==> Base packages are installed. Press Enter to continue...${NC}"
    
    enable_service "seatd"

    echo -e "${GRA}--> Enabling PipeWire user services...${NC}"
    systemctl --user enable pipewire pipewire-pulse wireplumber > /dev/null 2>&1

    # Enable NetworkManager
    echo -e "${GRA}--> Enabling NetworkManager...${NC}"
    sudo systemctl enable --now NetworkManager

    # Enable Bluetooth service
    echo -e "${GRA}--> Enabling Bluetooth service...${NC}"
    enable_service bluetooth
    sleep 2
}

install_custom_repos() {
    print_banner
    echo -e "${YLW}==> Setting up guhwm...${NC}"

    # 1. Clone guhwm
    if ! git clone https://github.com/Tapi-Mandy/guhwm.git "$TEMP_DIR/guhwm"; then
        echo -e "${RED}[!] Failed to clone guhwm repository.${NC}"
        exit 1
    fi
    
    # 2. Copy all configs
    if [ -d "$TEMP_DIR/guhwm/confs" ]; then
        echo -e "${GRA}--> Deploying configuration files...${NC}"
        cp -r "$TEMP_DIR/guhwm/confs/"* ~/.config/
    fi

    # 3. Copy wallpapers
    mkdir -p ~/Wallpapers
    cp -r "$TEMP_DIR/guhwm/Wallpapers/"* ~/Wallpapers/

    # 4. Make default-wallpaper.sh executable and run it
    if [ -f "$HOME/.config/mango/scripts/default-wallpaper.sh" ]; then
        chmod +x "$HOME/.config/mango/scripts/default-wallpaper.sh"
        echo -e "${GRA}--> Setting default wallpaper...${NC}"
        bash "$HOME/.config/mango/scripts/default-wallpaper.sh" 2>/dev/null || echo -e "${GRA}--> Wallpaper is ready.${NC}"
    fi

    # 5. Make nightlight toggle script executable
    if [ -f "$HOME/.config/mango/scripts/nightlight-toggle.sh" ]; then
        chmod +x "$HOME/.config/mango/scripts/nightlight-toggle.sh"
        echo -e "${GRA}--> Nightlight is ready.${NC}"
    fi

    # 6. Install guhwall (Wallpaper Manager)
    echo -e
    echo -e "${YLW}==> Installing guhwall | Guh?? Set a Wallpaper!...${NC}"
    if git clone https://github.com/Tapi-Mandy/guhwall.git "$TEMP_DIR/guhwall"; then
        (cd "$TEMP_DIR/guhwall" && makepkg -si --noconfirm)
        echo -e "${GRN}[SUCCESS] guhwall is installed.${NC}"
    else
        echo -e "${RED}[!] Failed to clone guhwall repository.${NC}"
        exit 1
    fi

    # 7. Install guhShot (Screenshot utility)
    echo -e
    echo -e "${YLW}==> Installing guhShot | Guh?? Take a Screenshot!...${NC}"
    if git clone https://github.com/Tapi-Mandy/guhShot.git "$TEMP_DIR/guhShot"; then
        (cd "$TEMP_DIR/guhShot" && makepkg -si --noconfirm)
        echo -e "${GRN}[SUCCESS] guhShot is installed.${NC}"
    else
        echo -e "${RED}[!] Failed to clone guhShot repository.${NC}"
        exit 1
    fi

    echo -e
    read -rp "${YLW}==> guhwm & guhwall & guhShot are installed. Press Enter to continue...${NC}"
}

optional_software() {
    # Ensure config directory exists before we try to 'sed' files in it
    mkdir -p "$HOME/.config/mango"
    
    print_banner

    # SHELLS
    prompt_selection "Shells" "single" \
        "$GRA" "Bash" "bash" "GNU Bourne Again Shell" \
        "$RED" "Fish" "fish" "Friendly Interactive Shell" \
        "$ORA" "Zsh" "zsh" "Z Shell" \
        "$MAG" "Oh-My-Zsh" "oh-my-zsh" "Community-driven framework for Zsh"

    if [[ -n "$LAST_SELECTION" ]]; then
        TARGET_SHELL="bash"
        [[ "$LAST_SELECTION" == "fish" ]] && TARGET_SHELL="fish"
        [[ "$LAST_SELECTION" == "zsh" || "$LAST_SELECTION" == "oh-my-zsh" ]] && TARGET_SHELL="zsh"

        if [[ "$LAST_SELECTION" == "oh-my-zsh" ]]; then
            echo -e "${MAG}--> Running official Oh-My-Zsh installer...${NC}"
            sudo pacman -S --needed --noconfirm zsh
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
            [ -f "$HOME/.zshrc" ] && sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' "$HOME/.zshrc"
        fi

        # Change shell after installation
        hash -r
        SHELL_PATH=$(command -v "$TARGET_SHELL" 2>/dev/null)
        if [[ -n "$SHELL_PATH" ]]; then
            if ! grep -Fxq "$SHELL_PATH" /etc/shells; then
                echo "$SHELL_PATH" | sudo tee -a /etc/shells > /dev/null
            fi
            echo -e "${GRA}--> Setting default shell to $TARGET_SHELL...${NC}"
            sudo chsh -s "$SHELL_PATH" "$USER"
        fi
        unset LAST_SELECTION
    fi
    echo -e
    read -rp "${YLW}==> Press Enter to continue...${NC}"

    # TERMINALS
    prompt_selection "Terminals" "single" \
        "$ORA" "Alacritty" "alacritty" "Fast, cross-platform, OpenGL terminal" \
        "$YLW" "Foot" "foot" "Fast, lightweight Wayland terminal" \
        "$MAG" "Kitty" "kitty" "Modern, hackable, featureful, OpenGL terminal"
    
    if [[ -n "$LAST_SELECTION" ]]; then
        sed -i "s/YOURTERMINAL/$LAST_SELECTION/g" ~/.config/mango/config.conf 2>/dev/null || true
        unset LAST_SELECTION
    fi

    # BROWSERS
    prompt_selection "Browsers" "multi" \
        "$ORA" "Brave" "brave-bin" "Privacy-focused browser" \
        "$ORA" "Firefox" "firefox" "Fast, Private & Safe" \
        "$PUR" "Floorp" "floorp-bin" "Firefox fork focused on performance" \
        "$CYN" "LibreWolf" "librewolf-bin" "Fork of Firefox focused on privacy" \
        "$WHT" "Lynx" "lynx" "Text-based web browser" \
        "$GRA" "Zen Browser" "zen-browser-bin" "Experience tranquillity while browsing"

    # CHAT CLIENTS
    prompt_selection "Chat Clients" "multi" \
        "$BLU" "Discord" "discord" "All-in-one voice and text chat" \
        "$BLU" "Dissent" "dissent-bin" "Discord client written in Go/GTK4" \
        "$CYN" "Telegram" "telegram-desktop" "Official Telegram Desktop client" \
        "$MAG" "Vesktop" "vesktop-bin" "The cutest Discord client" \
        "$CYN" "WebCord" "webcord-bin" "Discord client using the web version"

    # FILE MANAGERS
    prompt_selection "File Managers" "single" \
        "$BLU" "Nautilus" "nautilus" "GNOME's file manager" \
        "$WHT" "Nemo" "nemo" "Cinnamon's file manager" \
        "$CYA" "Dolphin" "dolphin" "KDE's feature-rich file manager" \
        "$GRA" "nnn" "nnn" "The unorthodox terminal file manager" \
        "$ORA" "ranger" "ranger" "Vim-inspired terminal file manager" \
        "$YLW" "yazi" "yazi" "Blazing fast terminal file manager written in Rust"

    if [[ -n "$LAST_SELECTION" ]]; then
        sed -i "s/YOURFILEMANAGER/$LAST_SELECTION/g" ~/.config/mango/config.conf 2>/dev/null || true
        unset LAST_SELECTION
    fi

    # EDITORS
    prompt_selection "Editors" "multi" \
        "$PUR" "Emacs" "emacs" "The extensible, self-documenting editor" \
        "$YLW" "Geany" "geany" "Flyweight IDE" \
        "$GRN" "Neovim" "neovim" "Vim-fork focused on extensibility" \
        "$GRA" "Sublime Text" "sublime-text-4" "Sophisticated text editor" \
        "$GRN" "Vim" "vim" "The ubiquitous text editor" \
        "$BLU" "VSCodium" "vscodium-bin" "Free/Libre Open Source VSCode"
        
    if [[ -n "$LAST_SELECTION" ]]; then
        sed -i "s/YOUREDITOR/$LAST_SELECTION/g" ~/.config/mango/config.conf 2>/dev/null || true
        unset LAST_SELECTION
    fi

    # GRAPHICS
    prompt_selection "Graphics" "multi" \
        "$ORA" "Blender" "blender" "3D creation suite for modeling, rigging, and animation" \
        "$GRA" "GIMP" "gimp" "GNU Image Manipulation Program" \
        "$MAG" "Krita" "krita" "Digital painting studio"

    # MEDIA
    prompt_selection "Media" "multi" \
        "$WHT" "imv" "imv" "Command-line image viewer for Wayland and X11" \
        "$BLU" "Loupe" "loupe" "Simple and modern image viewer from GNOME" \
        "$PUR" "mpv" "mpv" "Free, open source, and cross-platform media player" \
        "$CYN" "swayimg" "swayimg" "Lightweight image viewer for Wayland" \
        "$ORA" "VLC" "vlc" "Multi-platform multimedia player and framework"

    # UTILITIES
    prompt_selection "Utilities" "multi" \
        "$GRA" "Fastfetch" "fastfetch" "Like neofetch, but much faster" \
        "$MAG" "fzf" "fzf" "Command-line fuzzy finder" \
        "$GRA" "htop" "htop" "Interactive process viewer" \
        "$GRA" "nvtop" "nvtop" "GPUs process monitor for AMD, NVIDIA, and Intel" \
        "$CYN" "tldr" "tldr" "Simplified and community-driven man pages" \
        "$MAG" "uwufetch" "uwufetch" "Cute system info fetcher"

    # EMULATORS
    prompt_selection "Emulators" "multi" \
        "$BLU" "Dolphin" "dolphin-emu-git" "Gamecube & Wii emulator" \
        "$YLW" "DuckStation" "duckstation-git" "PS1 Emulator aiming for accuracy and support" \
        "$GRN" "melonDS" "melonds-bin" "DS emulator, sorta" \
        "$BLU" "PCSX2" "pcsx2" "PlayStation 2 emulator" \
        "$GRA" "RetroArch" "retroarch" "Frontend for emulators, game engines and media players." \
        "$GRN" "ScummVM" "scummvm" "'Virtual machine' for several classic graphical point-and-click adventure games." \
        "$GRN" "xemu" "xemu-bin" "Emulator for the original Xbox"

    # DISPLAY MANAGER (Ly)
    prompt_selection "Display Manager" "single" "$PUR" "Ly" "ly" "TUI display manager"
    local prompt_rc=$?

    if [[ $prompt_rc -eq 0 && -n "$LAST_SELECTION" ]]; then
        echo -e "${GRA}--> Verifying installation...${NC}"
        if pacman -Qq ly >/dev/null 2>&1; then
            enable_service "ly"
            echo -e
            read -rp "${YLW}==> Ly setup finished. Press Enter to continue...${NC}"
        else
            echo -e "${RED}[ERROR] Ly package not found in database.${NC}"
            read -rp "${YLW}==> Press Enter to continue...${NC}"
        fi
        unset LAST_SELECTION
    fi
}

print_outro() {
    print_banner
    cat << "EOF"
    *                  *
        __                *
     ,db'    *     *
    ,d8/       *        *    *
    888
    `db\       *     *
      `o`_                    **
 *               *   *    _      *
       *                 / )
    *    (\__/) *       ( (  *
  ,-.,-.,)    (.,-.,-.,-.) ).,-.,-.
 | @|  ={      }= | @|  / / | @|o |
_j__j__j_)     `-------/ /__j__j__j_
________(               /___________
 |  | @| \              || o|O | @|
 |o |  |,'\       ,   ,'"|  |  |  |
vV\|/vV|`-'\  ,---\   | \Vv\hjwVv\//v
           _) )    `. \ /
          (__/       ) )
                    (_/
EOF
    echo -e "${GRN}System setup complete! Everything is ready.${NC}"
    echo -e
    read -rp "Would you like to reboot now? (y/n): " rb
    
    if [[ "$rb" == [yY] ]]; then
        systemctl reboot
    fi
}

# --- Execution Flow ---
prepare_system        # Refresh keys, install git/base-devel
detect_aur            # Check if a helper is already there
setup_aur_helper      # Repair or Install AUR helper
install_base          # System utils, Wayland, Audio, Fonts
install_custom_repos  # Clone configs, Wallpapers, guhwall, guhShot
optional_software     # Shells, Browsers, Apps, and 'sed' tweaks
print_outro           # Final ASCII and reboot prompt
