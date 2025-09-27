#!/usr/bin/bash

# =====================================================================
# Guh Window Manager installer for Arch Linux
# =====================================================================
# Features:
# - Retries pacman and AUR installs with mirror refreshing on failures
# - Lets the user select and install their preferred AUR helper
# - Allows removing unwanted packages before installation
# - Installs general software and shells
# - Sets the first chosen shell as the default
# - Autostarts startx (only in profile files, never rc files)
# - Creates/overwrites .xinitrc with:
#     • Random wallpaper
#     • Improved system monitor (CPU, RAM, Disk, Datetime)
#     • DBus session for dunst
#     • Redshift (recommended 4000K)
#     • Clipmenu functionality
#     • Optional keyboard layouts with Ctrl+Space switch
# - Builds and installs guhwm from source
# - Maintains a rotating log system for debugging
# - Provides a final summary of successes and failures
# - Prompts to launch guhwm immediately after installation
# - Safety checks: prevents running as root, verifies shell exists in /etc/shells
# - Dry-run mode (--dry-run) to simulate installation without changes
# - Help output describing usage, options, and logfiles
# =====================================================================

set -e

# ==============================
# Colors
# ==============================
RED="\e[31m"
PINK="\e[1;35m"
RESET="\e[0m"

# ==============================
# Help & Dry-run Flags
# ==============================
DRY_RUN=false

show_help() {
    echo -e "${PINK}Guh Window Manager Installer${RESET}"
    echo "============================"
    echo
    echo "Usage: ./install.sh [OPTIONS]"
    echo
    echo "Options:"
    echo "  --dry-run    Simulate the installation without making changes"
    echo "  --help       Show this help message and exit"
    echo
    echo "Notes:"
    echo "  - Logfiles are stored in ~/.guhwm/logs/"
    echo "  - Dry-run mode shows what WOULD be installed"
    echo "  - Startx is only configured in profile files, not rc files"
    echo "  - .xinitrc will be overwritten unless declined"
    echo
}

if [[ "$1" == "--help" ]]; then
    show_help
    exit 0
elif [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo -e "${PINK}[DRY-RUN] Simulation mode enabled. No changes will be made.${RESET}"
fi

# ==============================
# Root safety check
# ==============================
if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}!! Do not run this script as root. Exiting.${RESET}"
    exit 1
fi

# ==============================
# Aligned Section Header
# ==============================
header() {
    local title="$1"
    local width=45
    local tlen=${#title}
    local left right
    if [ "$tlen" -ge $((width-2)) ]; then
        printf "${PINK}== %s ==${RESET}\n" "$title"
        return
    fi
    local total_pad=$((width - tlen - 2))
    local left_pad=$((total_pad/2))
    local right_pad=$((total_pad - left_pad))
    left=$(printf '%*s' "$left_pad" '' | tr ' ' '=')
    right=$(printf '%*s' "$right_pad" '' | tr ' ' '=')
    printf "${PINK}%s %s %s${RESET}\n" "$left" "$title" "$right"
}

# ==============================
# Logging setup
# ==============================
LOG_DIR="$HOME/.guhwm/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/install_${TIMESTAMP}.log"

exec > >(tee -a "$LOG_FILE") 2>&1

# Rotate logs (keep 5 uncompressed, compress older)
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
    local time
    time=$(date +"%H:%M:%S")
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
    local pkg="$*"
    if $DRY_RUN; then
        echo -e "${PINK}[DRY-RUN] Would install via pacman:${RESET} $pkg"
        log_status "$pkg" "OK"
        return 0
    fi
    local retries=5 count=0
    until sudo pacman -S --noconfirm "$@"; do
        count=$((count+1))
        echo -e "${RED}!! pacman failed on $pkg (attempt $count/$retries)${RESET}"
        if [ $count -ge $retries ]; then
            log_status "$pkg" "FAIL"
            return 1
        fi
        echo -e "${RED}!! Retrying $pkg...${RESET}"
        sudo pacman -S --needed --noconfirm reflector
        sudo reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
        sleep 2
    done
    log_status "$pkg" "OK"
}

retry_aur() {
    local pkg="$*"
    if $DRY_RUN; then
        echo -e "${PINK}[DRY-RUN] Would install via $aur_helper:${RESET} $pkg"
        log_status "$pkg" "OK"
        return 0
    fi
    local retries=5 count=0
    until "$aur_helper" -S --noconfirm "$@"; do
        count=$((count+1))
        echo -e "${RED}!! $aur_helper failed on $pkg (attempt $count/$retries)${RESET}"
        if [ $count -ge $retries ]; then
            log_status "$pkg" "FAIL"
            return 1
        fi
        echo -e "${RED}!! Retrying $pkg...${RESET}"
        sudo pacman -S --needed --noconfirm reflector
        sudo reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
        sleep 2
    done
    log_status "$pkg" "OK"
}

# ==============================
# Welcome
# ==============================
header "Welcome"
echo -e "${PINK}Thank you for trying guhwm!${RESET}"
echo -e "${PINK}You'll be prompted to install optional software, which is highly recommended.${RESET}"
echo -e "${PINK}Next, you will be prompted to select your preferred AUR helper.${RESET}"
sleep 6

# ==============================
# Base Packages
# ==============================
header "Base Packages"
retry_pacman xorg dmenu feh dunst clipmenu reflector nano noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-dejavu ttf-fira-code ttf-jetbrains-mono

# ==============================
# AUR Helper
# ==============================
header "AUR Helper"
echo -e "${PINK}Choose your preferred AUR helper:${RESET}"
select aur_helper in yay paru; do
    [[ "$aur_helper" =~ ^(yay|paru)$ ]] && break
done

if ! command -v "$aur_helper" &>/dev/null && ! $DRY_RUN; then
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
shells=(zsh oh-my-zsh fish ksh)

# ==============================
# Removal Menu
# ==============================
remove_items() {
    local -n items=$1
    local title=$2
    while true; do
        echo
        header "$title"
        for i in "${!items[@]}"; do
            printf "%d) %s\n" "$i" "${items[$i]}"
        done
        echo
        echo -e "${PINK}Enter numbers to remove (comma-separated), or press Enter to keep all:${RESET}"
        read -r input
        [[ -z "$input" ]] && break
        IFS=',' read -ra indices <<< "$input"
        for index in "${indices[@]}"; do unset 'items[index]'; done
        items=("${items[@]}")
        break
    done
}

remove_items general_software "General Software"
remove_items shells "Shells"

# ==============================
# Install Software
# ==============================
header "Installing Software"
for pkg in "${general_software[@]}"; do retry_aur "$pkg"; done
for pkg in "${shells[@]}"; do
    if [[ "$pkg" == "oh-my-zsh" ]]; then
        if ! $DRY_RUN; then
            if ! command -v zsh &>/dev/null; then retry_aur zsh; fi
            if [ ! -d "$HOME/.oh-my-zsh" ]; then
                sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
                log_status "oh-my-zsh" "OK"
            else
                echo -e "${PINK}Oh My Zsh already installed. Skipping.${RESET}"
            fi
        fi
    else
        retry_aur "$pkg"
    fi
done

# ==============================
# Default Shell Setup
# ==============================
header "Default Shell Setup"
if [ ${#shells[@]} -gt 0 ]; then
    first_shell="${shells[0]}"
    case "$first_shell" in
        zsh|oh-my-zsh) shell_path="/bin/zsh" ;;
        fish)          shell_path="/usr/bin/fish" ;;
        ksh)           shell_path="/usr/bin/ksh" ;;
        *)             shell_path="/bin/bash" ;;
    esac
    if [[ "$shell_path" != "/bin/bash" && "$shell_path" != "/usr/bin/fish" ]]; then
        if grep -q "$shell_path" /etc/shells; then
            if $DRY_RUN; then
                echo -e "${PINK}[DRY-RUN] Would set default shell to${RESET} $shell_path"
                log_status "Default shell ($first_shell)" "OK"
            else
                chsh -s "$shell_path" "$USER" && log_status "Default shell ($first_shell)" "OK"
            fi
        else
            log_status "Default shell ($first_shell)" "FAIL"
        fi
    fi
fi

# ==============================
# Auto-start X in profile
# ==============================
header "Startx Setup"
if [[ "$shell_path" != "/usr/bin/fish" ]]; then
    case "$shell_path" in
        /bin/bash) profile_file="$HOME/.bash_profile" ;;
        /bin/zsh)  profile_file="$HOME/.zprofile" ;;
        /usr/bin/ksh) profile_file="$HOME/.profile" ;;
        *) profile_file="$HOME/.bash_profile" ;;
    esac
    if ! grep -q "exec startx" "$profile_file" 2>/dev/null; then
        if $DRY_RUN; then
            echo -e "${PINK}[DRY-RUN] Would add startx auto-start to${RESET} $profile_file"
        else
            {
                echo
                echo "# Auto-start X only on tty1"
                echo 'if [[ -z $DISPLAY ]] && [[ $(tty) == /dev/tty1 ]]; then'
                echo '    exec startx'
                echo 'fi'
            } >> "$profile_file"
        fi
    fi
fi

# ==============================
# .xinitrc Setup
# ==============================
header ".xinitrc Setup"
XINITRC_PATH="$HOME/.xinitrc"
overwrite=true
if [ -f "$XINITRC_PATH" ] && ! $DRY_RUN; then
    echo ".xinitrc exists. Overwrite? (y/n)"
    read -r choice
    [[ "$choice" =~ ^[Yy]$ ]] || overwrite=false
fi
if $overwrite; then
    if $DRY_RUN; then
        echo -e "${PINK}[DRY-RUN] Would write .xinitrc${RESET}"
    else
        WALLPAPER_DIR="$HOME/guhwm/Wallpapers"
        WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname \*.jpg -o -iname \*.png -o -iname \*.jpeg \) | shuf -n 1)
        [ -z "$WALLPAPER" ] && WALLPAPER="$HOME/guhwm/Wallpapers/guhwm-default.png"
        cat > "$XINITRC_PATH" <<EOF
#!/bin/sh
# ==============================
# .xinitrc for guhwm
# ==============================

# --- Random Wallpaper (requires feh, installed by guhwm) ----------------------------
WALLPAPER_DIR="$HOME/guhwm/Wallpapers"
WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname \*.jpg -o -iname \*.png -o -iname \*.jpeg \) | shuf -n 1)
[ -z "$WALLPAPER" ] && WALLPAPER="$HOME/guhwm/Wallpapers/guhwm-default.png"
feh --bg-scale "$WALLPAPER" &

# --- System Monitor (CPU, Mem, Disk, Datetime) --------
while true; do
  # CPU usage via /proc/stat (lightweight)
  read -r user nice system idle rest < /proc/stat
  prev_total=$((user + nice + system + idle))
  prev_idle=$idle
  sleep 2
  read -r user nice system idle rest < /proc/stat
  total=$((user + nice + system + idle))
  diff_total=$((total - prev_total))
  diff_idle=$((idle - prev_idle))
  cpu_usage=$(( (100 * (diff_total - diff_idle)) / diff_total ))

  mem_usage=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
  disk_usage=$(df -h | awk '$NF=="/"{printf "%s", $5}')
  datetime=$(date +"%a, %b %d, %R")

  xsetroot -name "$cpu_usage% CPU | $mem_usage Mem | $disk_usage Disk | $datetime"
done &

# --- Notification Daemon (dunst needs D-Bus) ----------
if command -v dbus-launch >/dev/null 2>&1 && ! pgrep -x dbus-daemon >/dev/null; then
  eval "$(dbus-launch --sh-syntax --exit-with-session)"
fi
dunst &

# --- Redshift for Eye Comfort --------------------------
if command -v redshift >/dev/null 2>&1; then
  TEMP=4000   # Recommended warm color temperature
  if redshift -m randr -O $TEMP >/dev/null 2>&1; then
    redshift -m randr -O $TEMP &
  elif redshift -m vidmode -O $TEMP >/dev/null 2>&1; then
    redshift -m vidmode -O $TEMP &
  else
    redshift -O $TEMP &
  fi
fi

# --- Clipboard Manager (Clipmenu, installed by guhwm) ----------------------
if command -v clipmenud >/dev/null 2>&1; then
  clipmenud &
fi

# --- Optional: Keyboard Layout Switching ---------------
# Uncomment and adjust the next line to enable multiple layouts
# Example: US English, Bulgarian phonetic, Arabic phonetic
# setxkbmap -layout "us,bg,ara" -variant ",bas_phonetic,mac-phonetic" -option "grp:ctrl_space_toggle" &

# --- Window Manager ------------------------------------
# This must be the last line!
exec dwm
EOF
        chmod +x "$XINITRC_PATH"
    fi
fi

# ==============================
# guhwm Build + Install
# ==============================
header "guhwm Build + Install"
if $DRY_RUN; then
    echo -e "${PINK}[DRY-RUN] Would build and install guhwm${RESET}"
else
    if [ ! -d "$HOME/guhwm" ]; then
        git clone https://github.com/Tapi-Mandy/guhwm.git "$HOME/guhwm"
    else
        git -C "$HOME/guhwm" pull
    fi
    cd "$HOME/guhwm"
    make clean && sudo make install
fi

# ==============================
# Summary
# ==============================
header "Summary"
echo "Succeeded: $SUCCEEDED_COUNT"
echo "Failed:    $FAILED_COUNT"
for item in "${FAILED_LIST[@]}"; do echo "  - $item"; done

# ==============================
# Final Launch Prompt
# ==============================
header "Launch"
printf "${PINK}Do you want to start guhwm now? (y/n): ${RESET}"
read -r launch_now
if [[ "$launch_now" =~ ^[Yy]$ ]]; then
    $DRY_RUN && echo -e "${PINK}[DRY-RUN] Would run startx now.${RESET}" || exec startx
else
    echo -e "${PINK}guhwm will start automatically on reboot.${RESET}"
fi
