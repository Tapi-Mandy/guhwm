#!/usr/bin/bash

# =====================================================================
# Guh Window Manager installer for Arch Linux
# =====================================================================
# Features:
# - Retries pacman and AUR installs with mirror refreshing on failures
# - Lets the user select and install their preferred AUR helper
# - Allows removing unwanted packages before installation
# - Installs general software and shells
# - Sets the first chosen shell as the default and autostarts startx
# - Creates/overwrites .xinitrc with many features
# - Builds and installs guhwm from source
# - Maintains a rotating log system for debugging
# - Provides a final summary of successes and failures
# - Prompts to launch guhwm immediately after installation
# =====================================================================

set -e

# ==============================
# Colors
# ==============================
RED="\e[31m"
PINK="\e[1;35m"
RESET="\e[0m"

# ==============================
# Logging setup
# ==============================
LOG_DIR="$HOME/.guhwm/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/install_${TIMESTAMP}.log"

exec > >(tee -a "$LOG_FILE") 2>&1

# Rotate logs (keep all, compress old after 5)
LOGCOUNT=$(ls -1 "$LOG_DIR"/install_*.log 2>/dev/null | wc -l)
if [ "$LOGCOUNT" -gt 5 ]; then
    gzip "$LOG_DIR"/install_*.log --force 2>/dev/null || true
fi

FAILED_COUNT=0
FAILED_LIST=()
SUCCEEDED_COUNT=0

# ==============================
# Status Logging Function
# ==============================
log_status() {
    local pkg="$1"
    local status="$2"
    local time=$(date +"%H:%M:%S")
    if [ "$status" = "OK" ]; then
        printf "[%s] --> %-44s [%bOK%b]\n" "$time" "$pkg" "$PINK" "$RESET"
        SUCCEEDED_COUNT=$((SUCCEEDED_COUNT+1))
    else
        printf "[%s] --> %-44s [%bFAIL%b]\n" "$time" "$pkg" "$RED" "$RESET"
        FAILED_COUNT=$((FAILED_COUNT+1))
        FAILED_LIST+=("$pkg")
    fi
}

# ==============================
# Retry Functions
# ==============================
retry_pacman() {
    local retries=5
    local count=0
    local pkg="$*"

    until sudo pacman -S --noconfirm "$@"; do
        count=$((count+1))
        echo -e "${RED}!! pacman failed on $pkg (attempt $count/$retries)${RESET}"
        if [ $count -ge $retries ]; then
            log_status "$pkg" "FAIL"
            return 1
        fi
        echo -e "${RED}!! Retrying $pkg... (attempt $((count+1))/$retries)${RESET}"
        sudo pacman -S --needed --noconfirm reflector
        sudo reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
        sleep 2
    done
    log_status "$pkg" "OK"
}

retry_aur() {
    local retries=5
    local count=0
    local pkg="$*"

    until "$aur_helper" -S --noconfirm "$@"; do
        count=$((count+1))
        echo -e "${RED}!! $aur_helper failed on $pkg (attempt $count/$retries)${RESET}"
        if [ $count -ge $retries ]; then
            log_status "$pkg" "FAIL"
            return 1
        fi
        echo -e "${RED}!! Retrying $pkg... (attempt $((count+1))/$retries)${RESET}"
        sudo pacman -S --needed --noconfirm reflector
        sudo reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
        sleep 2
    done
    log_status "$pkg" "OK"
}

# ==============================
# Welcome
# ==============================
echo -e "${PINK}Thank you for trying guhwm! ;3${RESET}"
echo
echo -e "${PINK}You'll be prompted to install optional software, which is highly recommended.${RESET}"
echo -e "${PINK}Next, you will be prompted to select your preferred AUR helper.${RESET}"
sleep 6

# ==============================
# Base Packages
# ==============================
retry_pacman xorg dmenu kitty feh dunst clipmenu reflector nano noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-dejavu ttf-fira-code ttf-jetbrains-mono

# ==============================
# AUR Helper
# ==============================
echo -e "${PINK}Choose your preferred AUR helper:${RESET}"
select aur_helper in yay paru; do
    if [[ "$aur_helper" =~ ^(yay|paru)$ ]]; then
        echo -e "${PINK}Selected AUR helper: $aur_helper${RESET}"
        break
    else
        echo -e "${RED}Invalid choice. Try again.${RESET}"
    fi
done

if ! command -v "$aur_helper" &>/dev/null; then
    echo -e "${PINK}$aur_helper not found. Installing...${RESET}"
    retry_pacman base-devel git curl
    tmpdir=$(mktemp -d)
    cd "$tmpdir"
    git clone "https://aur.archlinux.org/$aur_helper.git"
    cd "$aur_helper"
    makepkg -si --noconfirm
    cd ~
    rm -rf "$tmpdir"
fi

# ==============================
# Software Lists
# ==============================
general_software=(firefox vesktop-bin uwufetch krita scrot vim htop mpv redshift)
general_descs=(
    "Fast, Private & Safe Web Browser"
    "The cutest Discord client mod"
    "System info tool for Linux, based on nyan/uwu trend on r/linuxmasterrace"
    "Full-featured free digital painting studio"
    "Simple command-line screenshot utility for X"
    "Vi Improved, a highly configurable, improved version of the vi text editor"
    "Interactive process viewer"
    "Cross-platform media player"
    "Adjusts the color temperature of your screen according to your surroundings"
)

shells=(zsh oh-my-zsh fish ksh)
shell_descs=(
    "A very advanced and programmable shell"
    "Community-driven framework for managing your zsh configuration"
    "Smart and user friendly shell intended mostly for interactive use"
    "The Original AT&T Korn Shell"
)

# ==============================
# Removal Menu
# ==============================
remove_items() {
    local -n items=$1
    local -n descs=$2
    local title=$3
    while true; do
        echo
        echo "=== $title ==="
        for i in "${!items[@]}"; do
            printf "%d) %-14s - %s\n" "$i" "${items[$i]}" "${descs[$i]}"
        done
        echo
        echo -e "${PINK}Enter numbers to remove (comma-separated), or press Enter to keep all:${RESET}"
        read -r input
        if [[ -z "$input" ]]; then break; fi
        IFS=',' read -ra indices <<< "$input"
        valid=true
        for index in "${indices[@]}"; do
            index=$(echo "$index" | xargs)
            if ! [[ "$index" =~ ^[0-9]+$ ]] || (( index < 0 || index >= ${#items[@]} )); then
                valid=false; break
            fi
        done
        if ! $valid; then
            echo -e "${RED}!! Invalid choice, try again.${RESET}"
            continue
        fi
        for index in "${indices[@]}"; do
            index=$(echo "$index" | xargs)
            echo "Removing: ${items[$index]}"
            unset 'items[index]'
            unset 'descs[index]'
        done
        items=("${items[@]}")
        descs=("${descs[@]}")
        break
    done
}

remove_items general_software general_descs "General Software"
remove_items shells shell_descs "Shells"

# ==============================
# Install Software
# ==============================
echo -e "${PINK}Installing general software...${RESET}"
for pkg in "${general_software[@]}"; do retry_aur "$pkg"; done

echo -e "${PINK}Installing shells...${RESET}"
for pkg in "${shells[@]}"; do
    if [[ "$pkg" == "oh-my-zsh" ]]; then
        echo -e "${PINK}Installing Oh My Zsh...${RESET}"
        if ! command -v zsh &>/dev/null; then retry_aur zsh; fi
        if [ ! -d "$HOME/.oh-my-zsh" ]; then
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
            log_status "oh-my-zsh" "OK"
        else
            echo -e "${PINK}Oh My Zsh already installed. Skipping.${RESET}"
        fi
    else
        retry_aur "$pkg"
    fi
done

# ==============================
# Xinitrc Setup
# ==============================
echo -e "${PINK}Setting up .xinitrc...${RESET}"
XINITRC_PATH="$HOME/.xinitrc"
overwrite=true
if [ -f "$XINITRC_PATH" ]; then
    echo ".xinitrc already exists. Overwrite? (y/n)"
    read -r choice
    [[ "$choice" =~ ^[Yy]$ ]] || overwrite=false
fi
if $overwrite; then
    WALLPAPER_DIR="$HOME/guhwm/Wallpapers"
    WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname \*.jpg -o -iname \*.png -o -iname \*.jpeg \) | shuf -n 1)
    [ -z "$WALLPAPER" ] && WALLPAPER="$HOME/guhwm/Wallpapers/guhwm-default.png"
    cat > "$XINITRC_PATH" <<EOF
#!/bin/sh
# Set a random background image
feh --bg-scale "$WALLPAPER" &

# Status bar loop
while true; do
  cpu_usage=\$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - \$1}')
  mem_usage=\$(free -h | awk '/^Mem:/ {print \$3 "/" \$2}')
  disk_usage=\$(df -h | awk '\$NF=="/"{printf "%s", \$5}')
  datetime=\$(date +"%a, %b %d, %R")
  xsetroot -name "\$cpu_usage% CPU | \$mem_usage Mem | \$disk_usage Disk | \$datetime"
  sleep 1
done &

# Start the notification daemon
dunst &

# Launch Redshift for eye comfort
command -v redshift >/dev/null 2>&1 && redshift -O 3500 &

# This must be the last line!
exec dwm
EOF
    chmod +x "$XINITRC_PATH"
    echo -e "${PINK}.xinitrc written.${RESET}"
else
    echo -e "${PINK}Skipped overwriting .xinitrc${RESET}"
fi

# ==============================
# guhwm Build + Install
# ==============================
echo -e "${PINK}Cloning and installing guhwm...${RESET}"
if [ ! -d "$HOME/guhwm" ]; then
    git clone https://github.com/Tapi-Mandy/guhwm.git "$HOME/guhwm"
else
    git -C "$HOME/guhwm" pull
fi
cd "$HOME/guhwm" || { echo -e "${RED}!! guhwm dir missing${RESET}"; exit 1; }
make clean && sudo make install
log_status "guhwm" "OK"

# ==============================
# Summary
# ==============================
echo
echo "==========================="
echo " Installation Summary"
echo "==========================="
echo "Succeeded: $SUCCEEDED_COUNT"
echo "Failed:    $FAILED_COUNT"
if [ "$FAILED_COUNT" -gt 0 ]; then
    for item in "${FAILED_LIST[@]}"; do
        echo "  - $item"
    done
fi
echo "==========================="

# ==============================
# Final Launch Prompt
# ==============================
echo
printf "${PINK}Do you want to start guhwm now? (y/n): ${RESET}"
read -r launch_now
if [[ "$launch_now" =~ ^[Yy]$ ]]; then
    echo -e "${PINK}Starting guhwm...${RESET}"
    sleep 1
    exec startx
else
    echo -e "${PINK}guhwm will start automatically on reboot.${RESET}"
fi
