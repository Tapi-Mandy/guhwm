#!/usr/bin/bash

# =====================================================================
# Guh Window Manager installer for Arch Linux
# =====================================================================
# Features:
#   * Dry-run mode (--dry-run) to simulate installation without changes
#   * Color-coded, aligned status output with logging to ~/.guhwm/logs
#   * Auto-retry with mirror refresh for failed pacman/AUR installs
#   * AUR helper selection (yay or paru) with bootstrap if missing
#   * Optional software selection
#   * First successfully installed shell becomes the default shell
#   * Default shell setup (with /etc/shells patch if needed)
#   * Auto-start X on tty1 in the correct profile
#   * .xinitrc auto-generated with:
#       - Smart-default wallpaper system
#       - CPU/memory/disk/date status bar
#       - Notification daemon (dunst)
#       - Redshift for eye comfort
#       - Clipboard manager (clipmenu)
#       - Keyboard layout switching support
#       - Salah times with robust configuration for Muslims, disabled by default
#   * Builds and installs guhwm from source
#   * Installation summary (successes/failures) and launch prompt
# =====================================================================

set -eo pipefail

# ==============================
# Colors
# ==============================
RED="\e[31m"
PINK="\e[1;35m"
MAGENTA="\033[35m"
RESET="\e[0m"

# ==============================
# Help & Dry-run Flags
# ==============================
DRY_RUN=false
DRY_RUN_PREFIX="${PINK}[DRY-RUN]${RESET}"

show_help() {
    echo -e "${PINK}=================================${RESET}"
    echo -e "${PINK}Guh Window Manager Installer${RESET}"
    echo -e "${PINK}=================================${RESET}"
    echo
    echo -e "${PINK}Usage: ./install.sh [OPTIONS]${RESET}"
    echo
    echo -e "${PINK}Options:${RESET}"
    echo "  --dry-run    Simulate the installation without making changes"
    echo "  --help       Show this help message and exit"
    echo
    echo -e "${PINK}Logs are saved under: ~/.guhwm/logs/${RESET}"
    echo -e "${PINK}You can review successes, failures, and your final launch choice there.${RESET}"
    echo
    echo -e "${PINK}Features:${RESET}"
    echo "  * Dry-run mode (--dry-run) to simulate installation without changes"
    echo "  * Color-coded, aligned status output with logging to ~/.guhwm/logs"
    echo "  * Auto-retry with mirror refresh for failed pacman/AUR installs"
    echo "  * AUR helper selection (yay or paru) with bootstrap if missing"
    echo "  * Optional software selection"
    echo "  * First successfully installed shell becomes the default shell"
    echo "  * Default shell setup (with /etc/shells patch if needed)"
    echo "  * Auto-start X on tty1 in the correct profile"
    echo "  * .xinitrc auto-generated with:"
    echo "      - Smart-default wallpaper system"
    echo "      - CPU/memory/disk/date status bar"
    echo "      - Notification daemon (dunst)"
    echo "      - Redshift for eye comfort"
    echo "      - Clipboard manager (clipmenu)"
    echo "      - Keyboard layout switching support (commented example)"
    echo "      - Salah times with robust configuration for Muslims (disabled by default)"
    echo "  * Builds and installs guhwm from source"
    echo "  * Installation summary (successes/failures) and launch prompt"
    echo
}

if [[ "$1" == "--help" ]]; then
    show_help
    exit 0
elif [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo -e "${PINK}[DRY-RUN] Simulation mode enabled. No changes will be made.${RESET}"
    echo -e "${PINK}[DRY-RUN] This dry-run will display exact commands that would be executed, and show simulated success/failure outcomes.${RESET}"
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
    if [ "$tlen" -ge $((width-2)) ]; then
        printf "${PINK}== %s ==${RESET}\n" "$title"
        return
    fi
    local total_pad=$((width - tlen - 2))
    local left_pad=$((total_pad/2))
    local right_pad=$((total_pad - left_pad))
    local left=$(printf '%*s' "$left_pad" '' | tr ' ' '=')
    local right=$(printf '%*s' "$right_pad" '' | tr ' ' '=')
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

# Rotate logs (keep 5 latest, compress older ones)
ls -1t "$LOG_DIR"/install_*.log 2>/dev/null | tail -n +6 | xargs -r gzip --force

FAILED_COUNT=0
FAILED_LIST=()
SUCCEEDED_COUNT=0

# Track first successfully installed shell path
INSTALLED_SHELL_PATH=""

# ==============================
# Dry-run helper (descriptive)
# ==============================
# Use this to consistently print and log what would happen.
dry_run_action() {
    # $1 = short label for the action (used for status tracking)
    # $2 = human-readable description
    # $3 = the exact command that would be run (single string)
    local label="$1"
    local desc="$2"
    local cmd="$3"
    # Print clearly to the user in the PINK theme
    echo -e "${PINK}[DRY-RUN] ACTION:${RESET} $desc"
    if [ -n "$cmd" ]; then
        echo -e "${PINK}[DRY-RUN] COMMAND:${RESET} $cmd"
    fi
    # Also add a short line to the logfile (so dry-run is traceable)
    {
        echo "[DRY-RUN] ACTION: $desc"
        [ -n "$cmd" ] && echo "[DRY-RUN] CMD: $cmd"
    } >> "$LOG_FILE"
    # Mark it as a simulated success for summary purposes
    log_status "$label" "OK"
}

# ==============================
# Status Logging Function
# ==============================
log_status() {
    local pkg="$1"
    local status="$2"
    local time=$(date +"%H:%M:%S")
    if [ "$status" = "OK" ]; then
        if $DRY_RUN; then
            # Show that it's a simulated OK in dry-run mode
            printf "[%s] --> %-44s [%bDRY-OK%b]\n" "$time" "$pkg" "$PINK" "$RESET"
            SUCCEEDED_COUNT=$((SUCCEEDED_COUNT+1))
        else
            printf "[%s] --> %-44s [%bOK%b]\n" "$time" "$pkg" "$PINK" "$RESET"
            SUCCEEDED_COUNT=$((SUCCEEDED_COUNT+1))
        fi
    else
        if $DRY_RUN; then
            printf "[%s] --> %-44s [%bDRY-FAIL%b]\n" "$time" "$pkg" "$RED" "$RESET"
            FAILED_COUNT=$((FAILED_COUNT+1))
            FAILED_LIST+=("$pkg")
        else
            printf "[%s] --> %-44s [%bFAIL%b]\n" "$time" "$pkg" "$RED" "$RESET"
            FAILED_COUNT=$((FAILED_COUNT+1))
            FAILED_LIST+=("$pkg")
        fi
    fi
}

# ==============================
# Safe heredoc-marker checker
# ==============================
check_heredoc_markers_in_file() {
    file="${1:-$0}"
    markers=$(grep -oE '^[[:space:]]*<<-?[[:space:]]*["'\'']?[A-Za-z0-9_]+["'\'']?' "$file" \
        | sed -E 's/^[[:space:]]*<<-?[[:space:]]*["'\'']?//; s/["'\'']?$//')

    for m in $markers; do
        if ! grep -qE "^[[:space:]]*$m\$" "$file"; then
            printf "HEREDOC MISMATCH: marker \"%s\" opens but no closing line found\n" "$m" >&2
            return 1
        fi
    done
    return 0
}

# ==============================
# Retry Functions
# ==============================
retry_pacman() {
    local pkg=("$@")
    local pkgstr="${pkg[*]}"
    if $DRY_RUN; then
        # Show exact pacman command we would run
        dry_run_action "$pkgstr" "Simulate: install via pacman (would run as shown)" "sudo pacman -S --noconfirm ${pkg[*]}"
        return 0
    fi
    local retries=5
    local count=0
    until sudo pacman -S --noconfirm "${pkg[@]}"; do
        count=$((count+1))
        echo -e "${RED}!! pacman failed on ${pkgstr} (attempt $count/$retries)${RESET}"
        if [ $count -ge $retries ]; then
            log_status "$pkgstr" "FAIL"
            return 1
        fi
        echo -e "${RED}!! Retrying ${pkgstr}... refreshing mirrors${RESET}"
        sudo pacman -S --needed --noconfirm reflector
        sudo reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
        sleep 2
    done
    log_status "$pkgstr" "OK"
}

retry_aur() {
    local pkg=("$@")
    local pkgstr="${pkg[*]}"
    if $DRY_RUN; then
        # Show exact AUR helper command we would run
        dry_run_action "$pkgstr" "Simulate: install via AUR helper (${aur_helper})" "${aur_helper} -S --noconfirm ${pkg[*]}"
        return 0
    fi
    local retries=5
    local count=0
    until "$aur_helper" -S --noconfirm "${pkg[@]}"; do
        count=$((count+1))
        echo -e "${RED}!! $aur_helper failed on ${pkgstr} (attempt $count/$retries)${RESET}"
        if [ $count -ge $retries ]; then
            log_status "$pkgstr" "FAIL"
            return 1
        fi
        echo -e "${RED}!! Retrying ${pkgstr}... refreshing mirrors${RESET}"
        sudo pacman -S --needed --noconfirm reflector
        sudo reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
        sleep 2
    done
    log_status "$pkgstr" "OK"
}

# ==============================
# Welcome
# ==============================
header "Welcome"
echo -e "${PINK}Thank you for trying guhwm! ;3${RESET}"
echo -e "${PINK}You'll be prompted to install optional software, which is highly recommended.${RESET}"
echo -e "${PINK}Next, you will be prompted to select your preferred AUR helper.${RESET}"
if $DRY_RUN; then
    echo -e "${PINK}[DRY-RUN] You will still be prompted for choices (AUR helper, overwriting files, launch). Responses will only affect the simulation.${RESET}"
fi
sleep 3

# ==============================
# Base Packages
# ==============================
header "Base Packages"
retry_pacman xorg reflector kitty feh clipmenu nano dunst libnotify xdg-desktop-portal xdg-desktop-portal-gtk p7zip jq alsa-utils noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-dejavu ttf-fira-code ttf-jetbrains-mono ttf-jetbrains-mono-nerd

# ==============================
# Kitty font configuration
# ==============================
KITTY_CONF_DIR="$HOME/.config/kitty"
KITTY_CONF_FILE="$KITTY_CONF_DIR/kitty.conf"

if ! $DRY_RUN; then
    mkdir -p "$KITTY_CONF_DIR"

    if grep -q "^font_family" "$KITTY_CONF_FILE" 2>/dev/null; then
        sed -i 's/^font_family.*/font_family JetBrainsMono Nerd Font/' "$KITTY_CONF_FILE"
    else
        echo "font_family JetBrainsMono Nerd Font" >> "$KITTY_CONF_FILE"
    fi

    if grep -q "^font_size" "$KITTY_CONF_FILE" 2>/dev/null; then
        sed -i 's/^font_size.*/font_size 14.0/' "$KITTY_CONF_FILE"
    else
        echo "font_size 14.0" >> "$KITTY_CONF_FILE"
    fi
    echo -e "${PINK}Kitty font configured: JetBrainsMono Nerd Font, size 14.0, with fallback.${RESET}"
else
    # Dry-run: clearly show what would be created/modified
    dry_run_action "kitty.conf" "Would create/modify kitty config to set font_family and font_size" "mkdir -p \"$KITTY_CONF_DIR\" && echo 'font_family JetBrainsMono Nerd Font' >> \"$KITTY_CONF_FILE\" && echo 'font_size 14.0' >> \"$KITTY_CONF_FILE\""
fi

# ==============================
# AUR Helper
# ==============================
header "AUR Helper"
echo -e "${PINK}Choose your preferred AUR helper:${RESET}"
select aur_helper in yay paru; do
    if [[ "$aur_helper" =~ ^(yay|paru)$ ]]; then
        echo -e "${PINK}Selected AUR helper: $aur_helper${RESET}"
        break
    else
        echo -e "${RED}Invalid choice. Try again.${RESET}"
    fi
done

if ! command -v "$aur_helper" &>/dev/null && ! $DRY_RUN; then
    echo -e "${PINK}$aur_helper not found. Installing...${RESET}"
    retry_pacman base-devel git curl
    tmpdir=$(mktemp -d)
    cd "$tmpdir"
    git clone "https://aur.archlinux.org/$aur_helper.git"
    cd "$aur_helper"
    makepkg -si --noconfirm
    cd ~
    rm -rf "$tmpdir"
elif ! command -v "$aur_helper" &>/dev/null && $DRY_RUN; then
    # Dry-run: show exact steps we'd perform to bootstrap the AUR helper
    dry_run_action "aur-helper-bootstrap" "AUR helper ($aur_helper) not found. Would install base-devel, git, curl and build the AUR helper from AUR." "sudo pacman -S --noconfirm base-devel git curl && tmpdir=\$(mktemp -d) && cd \$tmpdir && git clone https://aur.archlinux.org/${aur_helper}.git && cd ${aur_helper} && makepkg -si --noconfirm && cd ~ && rm -rf \$tmpdir"
fi

# ==============================
# Software Lists
# ==============================
general_software=(
    "firefox - Fast, Private & Safe Web Browser"
    "vesktop-bin - The cutest Discord client"
    "uwufetch - Cute system info tool for Linux"
    "krita - Full-featured free digital painting studio by KDE"
    "scrot - Simple command-line screenshot utility for X"
    "vim - Vi IMproved, a highly configurable, improved version of Vi"
    "yazi - Blazing fast terminal file manager written in Rust"
    "htop - Interactive system resource monitor"
    "mpv - Lightweight media player"
    "redshift - Adjusts the color temperature of your screen"
)

shells=(
    "zsh - Z-Shell, a very advanced and programmable shell"
    "oh-my-zsh - Community-driven framework for managing your zsh configuration"
    "fish - User-friendly shell intended mostly for interactive use"
    "ksh - KornShell, a classic Unix shell"
)

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
            name="${items[$i]%% -*}"   # package name
            desc="${items[$i]#*- }"   # description
            printf "${MAGENTA}%d)${RESET} %s - ${MAGENTA}%s${RESET}\n" "$i" "$name" "$desc"
        done
        echo
        echo -e "${PINK}Enter numbers to remove (comma-separated), or press Enter to keep all:${RESET}"
        read -r input
        [[ -z "$input" ]] && break
        IFS=',' read -ra indices <<< "$input"
        for index in "${indices[@]}"; do
            index=$(echo "$index" | xargs)
            unset 'items[index]'
        done
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
for pkg in "${general_software[@]}"; do
    retry_aur "${pkg%% -*}"   # strip description
done

for pkg in "${shells[@]}"; do
    name="${pkg%% -*}"        # strip description
    if [[ "$name" == "oh-my-zsh" ]]; then
        if ! $DRY_RUN; then
            echo -e "${PINK}Installing Oh My Zsh...${RESET}"
            if ! command -v zsh &>/dev/null; then retry_aur zsh; fi
            if [ ! -d "$HOME/.oh-my-zsh" ]; then
                sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
                log_status "oh-my-zsh" "OK"
                # >>> Force theme to agnoster <<<
                if [ -f "$HOME/.zshrc" ]; then
                    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="agnoster"/' "$HOME/.zshrc"
                else
                    echo 'ZSH_THEME="agnoster"' >> "$HOME/.zshrc"
                fi
            else
                echo -e "${PINK}Oh My Zsh already installed. Skipping.${RESET}"
            fi
            # === Ensure zsh is recorded as the default shell ===
            if [ -z "$INSTALLED_SHELL_PATH" ] && command -v zsh &>/dev/null; then
                INSTALLED_SHELL_PATH=$(command -v zsh)
            fi
        else
            # Dry-run simulation of the Oh My Zsh install flow
            if ! command -v zsh &>/dev/null; then
                dry_run_action "zsh" "Would install zsh via AUR helper" "${aur_helper} -S --noconfirm zsh || sudo pacman -S --noconfirm zsh"
            else
                echo -e "${PINK}[DRY-RUN] zsh already present on system (simulation: would check before installing).${RESET}"
            fi
            dry_run_action "oh-my-zsh" "Would download and run Oh My Zsh installer (unattended) and set ZSH_THEME in ~/.zshrc" "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" \"\" --unattended && sed -i 's/^ZSH_THEME=.*/ZSH_THEME=\"agnoster\"/' ~/.zshrc || echo 'ZSH_THEME=\"agnoster\"' >> ~/.zshrc"
            # Simulate setting INSTALLED_SHELL_PATH if zsh would be present
            INSTALLED_SHELL_PATH="/usr/bin/zsh" # simulated canonical path for summary
            log_status "oh-my-zsh" "OK"
        fi
    else
        if retry_aur "$name"; then
            if [ -z "$INSTALLED_SHELL_PATH" ]; then
                case "$name" in
                    zsh) INSTALLED_SHELL_PATH=$(command -v zsh) ;;
                    fish) INSTALLED_SHELL_PATH=$(command -v fish) ;;
                    ksh) INSTALLED_SHELL_PATH=$(command -v ksh) ;;
                esac
            fi
        fi
    fi
done

# ==============================
# Default Shell Setup
# ==============================
header "Default Shell Setup"
if [ -n "$INSTALLED_SHELL_PATH" ]; then
    # Ensure the shell path is in /etc/shells
    if ! grep -q "$INSTALLED_SHELL_PATH" /etc/shells; then
        echo -e "${PINK}Adding $INSTALLED_SHELL_PATH to /etc/shells...${RESET}"
        if $DRY_RUN; then
            dry_run_action "/etc/shells" "Would append $INSTALLED_SHELL_PATH to /etc/shells (so chsh can set it)" "echo \"$INSTALLED_SHELL_PATH\" | sudo tee -a /etc/shells >/dev/null"
        else
            echo "$INSTALLED_SHELL_PATH" | sudo tee -a /etc/shells >/dev/null
        fi
    fi

    if $DRY_RUN; then
        echo -e "${PINK}[DRY-RUN] Would set default shell to:${RESET} $INSTALLED_SHELL_PATH"
        log_status "Default shell" "OK"
    else
        echo -e "${PINK}Setting default shell to $INSTALLED_SHELL_PATH...${RESET}"
        if chsh -s "$INSTALLED_SHELL_PATH" "$USER"; then
            log_status "Default shell" "OK"
            export SHELL="$INSTALLED_SHELL_PATH"   # <-- Force update SHELL
        else
            log_status "Default shell" "FAIL"
        fi
    fi
else
    echo -e "${PINK}No custom shell installed, keeping bash.${RESET}"
fi

# ==============================
# Auto-start X in correct profile
# ==============================
header "Startx Setup"
if [ -n "$INSTALLED_SHELL_PATH" ]; then
    case "$INSTALLED_SHELL_PATH" in
        */bash) profile_file="$HOME/.bash_profile" ;;
        */zsh)  profile_file="$HOME/.zprofile" ;;
        */ksh)  profile_file="$HOME/.profile" ;;
        */fish) profile_file="$HOME/.config/fish/config.fish" ;;
        *)      profile_file="$HOME/.bash_profile" ;;
    esac

    if [ -n "$profile_file" ] && ! grep -q "exec startx" "$profile_file" 2>/dev/null; then
        if $DRY_RUN; then
            dry_run_action "startx-auto" "Would add startx auto-start snippet to $profile_file (only on tty1)" "append to $profile_file: if [[ -z \$DISPLAY ]] && [[ \$(tty) == /dev/tty1 ]]; then exec startx; fi"
            log_status "Startx in $profile_file" "OK"
        else
            echo -e "${PINK}Adding startx auto-start to $profile_file...${RESET}"
            # create parent directory if needed (safe minimal addition)
            mkdir -p "$(dirname "$profile_file")"
            {
                echo
                echo "# Auto-start X only on tty1"
                if [[ "$profile_file" == *"config.fish" ]]; then
                    # fish syntax
                    echo 'if test -z "$DISPLAY"; and test (tty) = "/dev/tty1"'
                    echo '    exec startx'
                    echo 'end'
                else
                    # POSIX / bash style
                    echo 'if [[ -z $DISPLAY ]] && [[ $(tty) == /dev/tty1 ]]; then'
                    echo '    exec startx'
                    echo 'fi'
                fi
            } >> "$profile_file"
            log_status "Startx in $profile_file" "OK"
        fi
    else
        echo -e "${PINK}Startx already present or skipped. Skipping.${RESET}"
    fi
else
    echo -e "${PINK}No installed shell, skipping startx setup.${RESET}"
fi

# ==============================
# .xinitrc Setup
# ==============================
header ".xinitrc Setup"
XINITRC_PATH="$HOME/.xinitrc"
overwrite=true
if [ -f "$XINITRC_PATH" ] && ! $DRY_RUN; then
    echo -e "${PINK}.xinitrc already exists. Overwrite? (y/n)${RESET}"
    read -r choice
    [[ "$choice" =~ ^[Yy]$ ]] || overwrite=false
fi
if $overwrite; then
    if $DRY_RUN; then
        echo -e "${PINK}[DRY-RUN] Would write .xinitrc to:${RESET} $XINITRC_PATH"
        dry_run_action ".xinitrc" "Simulate generating .xinitrc file (full content shown earlier in the installer script)" "cat > \"$XINITRC_PATH\" <<'XINITRC' ... XINITRC && chmod +x \"$XINITRC_PATH\""
        log_status ".xinitrc" "OK"
    else
        # --- Sanity check the installer itself for heredoc marker mismatches
        if ! check_heredoc_markers_in_file "$0"; then
            echo -e "${RED}Heredoc marker mismatch detected in installer script. Aborting to avoid writing broken .xinitrc.${RESET}"
            echo "Heredoc marker mismatch in installer. Aborting." >> "$LOG_FILE"
            exit 1
        fi

        cat > "$XINITRC_PATH" <<'XINITRC'
#!/bin/sh

# ============================================
# ----------- .xinitrc for guhwm -------------
# ============================================

# =======================================================
# --- Set a background image ----------------------------
# =======================================================
WALLPAPER_DIR="$HOME/guhwm/Wallpapers"
DEFAULT_WALLPAPER="$WALLPAPER_DIR/guhwm-default.png"

if [ -f "$DEFAULT_WALLPAPER" ]; then
    feh --bg-scale "$DEFAULT_WALLPAPER" &
else
    ALT_WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' \) | head -n 1)
    if [ -n "$ALT_WALLPAPER" ]; then
        feh --bg-scale "$ALT_WALLPAPER" &
    else
        # Fallback: solid dark background if no wallpaper is found
        xsetroot -solid "#282c34" &
    fi
fi

# =======================================================
# --- Start D-Bus (needed for notification services) ----
# =======================================================
if command -v dbus-launch >/dev/null 2>&1 && [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
fi

# =======================================================
# --- Start the notification daemon ---------------------
# =======================================================
command -v dunst >/dev/null 2>&1 && dunst &

# =======================================================
# --- Redshift for Eye Comfort --------------------------
# =======================================================
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

# =======================================================
# --- Clipboard Manager (Clipmenu) ----------------------
# =======================================================
command -v clipmenud >/dev/null 2>&1 && clipmenud &

# =======================================================
# --- Keyboard Layout Switching -------------------------
# =======================================================
# Uncomment and adjust the next line to enable multiple layouts
# Example: US English, Bulgarian phonetic, Arabic phonetic

# setxkbmap -layout "us,bg,ara" -variant ",bas_phonetic,mac-phonetic" -option "grp:ctrl_space_toggle" &

# =======================================================
# --- System monitor & datetime -------------------------
# =======================================================
(
  prev_total=0
  prev_idle=0

  while true; do
    # -------------------------------
    # CPU usage (from /proc/stat)
    # -------------------------------
    read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
    idle_all=$((idle + iowait))
    total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    diff_total=$((total - prev_total))
    diff_idle=$((idle_all - prev_idle))
    if [ $diff_total -gt 0 ]; then
      cpu_usage=$((100 * (diff_total - diff_idle) / diff_total))
    else
      cpu_usage=0
    fi
    prev_total=$total
    prev_idle=$idle_all

    # -------------------------------
    # Memory, disk, datetime
    # -------------------------------
    mem_usage=$(free -h | awk '/^Mem:/ {print ($2-$7) "/" $2}')
    disk_usage=$(df -h --output=used,size,target | awk '$3=="/"{print $1 "/" $2}')
    datetime=$(date +"%A, %b %d, %-I:%M %p")

    # -------------------------------
    # Salah (if enabled)
    # -------------------------------
    salah_str=$(cat /tmp/dwm-salah 2>/dev/null || echo "")

    # -------------------------------
    # Final status string
    # -------------------------------
    xsetroot -name "$cpu_usage% CPU | $mem_usage Mem | $disk_usage Disk | $datetime${salah_str:+ | $salah_str}"

    sleep 2
  done
) &

# =======================================================
# --- Salah times (optional) ----------------------------
# =======================================================
# Toggle Salah times here: 1 = enabled, 0 = disabled
ENABLE_SALAH=0

if [ "$ENABLE_SALAH" -eq 1 ]; then
(
    # ---------------------------------------------------
    # Location settings (Change these!)
    # ---------------------------------------------------
    CITY="Sofia"             # Your city name (Example: Sofia)
    COUNTRY="Bulgaria"       # Your country name (Example: Bulgaria)
    TIMEZONE="Europe/Sofia"  # Examples: Europe/London, America/New_York
                             # !! Must match your system timezone
                             # --> Run `timedatectl` or check /usr/share/zoneinfo

    METHOD=3   # Muslim World League (MWL) — Very popular globally.
               #
               # Other popular methods:
               #   2 = Islamic Society of North America (ISNA)
               #   4 = Umm al-Qura, Makkah
               #   5 = Egyptian General Authority of Survey
               #   14 = Spiritual Administration of Muslims of Russia
               # API reference: https://api.aladhan.com/v1/methods
               # Choose the one matching your mosque/local practice.

    # ---------------------------------------------------
    # Cache settings (API calls are cached daily/monthly)
    # ---------------------------------------------------
    CACHE_DIR="$HOME/.cache/salah"
    mkdir -p "$CACHE_DIR"

    # ----------------------------------------------------------
    # Salah offsets (minutes) — tweak for mosque adjustments
    # ----------------------------------------------------------
    # Example:
    #   If your local mosque does Fajr 5 min later, set OFFSET_Fajr=5
    #   If Isha is called 10 min earlier, set OFFSET_Isha=-10
    #   Leave as 0 if no adjustment is needed.
    OFFSET_Fajr=0
    OFFSET_Dhuhr=0
    OFFSET_Asr=0
    OFFSET_Maghrib=0
    OFFSET_Isha=0

    # ---------------------------------------------------
    # Offline fallback times (used if API unreachable)
    # ---------------------------------------------------
    # Always in 24h HH:MM format. These are only used as a backup.
    OFFLINE_TIMES="Fajr 05:10
Dhuhr 12:30
Asr 15:45
Maghrib 18:20
Isha 19:45"

    # ====================================================
    # Adjust a given HH:MM by prayer offset and format
    # ====================================================
    adjust_time() {
        prayer="$1"; time="$2"
        hour=${time%:*}
        min=${time#*:}
        total=$((10#$hour * 60 + 10#$min))

        case "$prayer" in
            Fajr)     total=$((total + OFFSET_Fajr)) ;;
            Dhuhr)    total=$((total + OFFSET_Dhuhr)) ;;
            Asr)      total=$((total + OFFSET_Asr)) ;;
            Maghrib)  total=$((total + OFFSET_Maghrib)) ;;
            Isha)     total=$((total + OFFSET_Isha)) ;;
        esac

        # Wrap around if time goes before 00:00 or after 23:59
        if [ $total -lt 0 ]; then total=$((total + 1440)); fi
        if [ $total -ge 1440 ]; then total=$((total - 1440)); fi

        hh=$((total / 60))
        mm=$((total % 60))
        printf -v raw "%02d:%02d" "$hh" "$mm"

        # Always return in 12h with AM/PM (e.g. 5:49 AM, 7:15 PM)
        date -d "$raw" +"%-I:%M %p"
    }

    # ---------------------------------------------------
    # Fetch & cache prayer times from API
    # ---------------------------------------------------
    fetch_month_file() {
        yr="$1"; mo="$2"
        cache="$CACHE_DIR/$yr-$mo.json"
        tmp="$(mktemp)"

        # Download only if cache is missing or stale
        if [ ! -f "$cache" ] || [ "$(date -r "$cache" +%Y-%m-%d)" != "$(date +%Y-%m-%d)" ]; then
            if curl -fsS --retry 2 --max-time 15 \
               "https://api.aladhan.com/v1/calendarByCity/$yr/$mo?city=$CITY&country=$COUNTRY&method=$METHOD&timezonestring=$TIMEZONE" \
               -o "$tmp"; then
                mv "$tmp" "$cache"
            else
                rm -f "$tmp"
            fi
        fi

        [ -f "$cache" ] && echo "$cache"
    }

    # ---------------------------------------------------
    # Extract times for a specific date (from cache or fallback)
    # ---------------------------------------------------
    get_times_for_date() {
        target_date="$1"
        year=$(date -d "$target_date" +%Y)
        month=$(date -d "$target_date" +%m)
        daynum=$(date -d "$target_date" +%d)
        cachefile="$(fetch_month_file "$year" "$month")" || cachefile=""

        if [ -n "$cachefile" ] && [ -s "$cachefile" ]; then
            jq -r --argjson idx $((10#$daynum-1)) '
.data[$idx].timings
| {Fajr, Dhuhr, Asr, Maghrib, Isha}
| to_entries[]
| "\(.key) \(.value)"' "$cachefile" \
            | sed -E 's/ ([0-9]{1,2}:[0-9]{2}).*/ \1/' \
            || return 1
        else
            echo "$OFFLINE_TIMES"; return 0
        fi
    }

    # ====================================================
    # Main Salah loop — writes "☪ NextPrayer HH:MM AM/PM"
    # ====================================================
    while true; do
        now=$(date +%H:%M)
        today=$(date +%Y-%m-%d)

        # Try to fetch today's times, else fallback
        times=$(get_times_for_date "$today" 2>/dev/null)
        [ -z "$times" ] && times="$OFFLINE_TIMES"

        next_prayer=""; next_time=""

        # Compare each prayer to current time
        while read -r prayer time; do
            adj_time=$(adjust_time "$prayer" "$time")
            comp_time=$(date -d "$adj_time" +%H:%M)  # For math comparison
            prayer_minutes=$((10#${comp_time%:*} * 60 + 10#${comp_time#*:}))
            now_minutes=$((10#${now%:*} * 60 + 10#${now#*:}))

            if [ "$prayer_minutes" -gt "$now_minutes" ]; then
                next_prayer=$prayer
                next_time=$adj_time
                break
            fi
        done <<PRAYERDATA
$times
PRAYERDATA

        # If all prayers passed, fall back to tomorrow's Fajr
        if [ -z "$next_prayer" ]; then
            tomorrow=$(date -d tomorrow +%Y-%m-%d)
            ttimes=$(get_times_for_date "$tomorrow" 2>/dev/null)

            if [ -n "$ttimes" ]; then
                next_prayer="Fajr"
                next_time=$(adjust_time "Fajr" "$(printf "%s" "$ttimes" | awk '/^Fajr / {print $2; exit}')")
            else
                next_prayer="Fajr"
                next_time=$(adjust_time "Fajr" "$(echo "$OFFLINE_TIMES" | awk '/^Fajr / {print $2; exit}')")
            fi
        fi

        # Output for dwm bar (example: "☪ Dhuhr 1:23 PM")
        echo "☪ $next_prayer $next_time" > /tmp/dwm-salah

        # Sleep until next prayer
        now_minutes=$((10#${now%:*} * 60 + 10#${now#*:}))
        comp_time=$(date -d "$next_time" +%H:%M)
        next_minutes=$((10#${comp_time%:*} * 60 + 10#${comp_time#*:}))
        sleep_minutes=$((next_minutes - now_minutes))
        [ $sleep_minutes -lt 1 ] && sleep_minutes=1

        sleep $((sleep_minutes * 60))
    done
) &
fi

# --- This must be the last line! ------------------------
exec dbus-run-session dwm
XINITRC
        chmod +x "$XINITRC_PATH"

        # --- Sanity-check: validate the generated .xinitrc
        if /bin/sh -n "$XINITRC_PATH"; then
            echo -e "${PINK}.xinitrc written and syntax-checked OK.${RESET}"
            echo ".xinitrc syntax check: OK" >> "$LOG_FILE"
        else
            echo -e "${RED}Warning: syntax errors detected in generated .xinitrc. Please inspect $XINITRC_PATH${RESET}"
            echo ".xinitrc syntax check: FAILED" >> "$LOG_FILE"
        fi

        echo -e "${PINK}.xinitrc written.${RESET}"
    fi
else
    echo -e "${PINK}Skipped overwriting .xinitrc${RESET}"
fi

# ==============================
# guhwm Build + Install
# ==============================
header "guhwm Build + Install"
if $DRY_RUN; then
    # Show the exact sequence we'd run
    dry_run_action "guhwm-build" "Would clone/pull and run make install for guhwm" "if [ ! -d \"$HOME/guhwm\" ]; then git clone https://github.com/Tapi-Mandy/guhwm.git \"$HOME/guhwm\"; else git -C \"$HOME/guhwm\" pull; fi && cd \"$HOME/guhwm\" && make clean && sudo make install"
    log_status "guhwm" "OK"
else
    if [ ! -d "$HOME/guhwm" ]; then
        git clone https://github.com/Tapi-Mandy/guhwm.git "$HOME/guhwm"
    else
        git -C "$HOME/guhwm" pull
    fi
    cd "$HOME/guhwm" || { echo -e "${RED}!! guhwm dir missing${RESET}"; exit 1; }
    make clean && sudo make install
    log_status "guhwm" "OK"
    cd ~ # return to home after build
fi

# ==============================
# Summary
# ==============================
header "Summary"
echo "Succeeded: $SUCCEEDED_COUNT"
echo "Failed:    $FAILED_COUNT"
if [ "$FAILED_COUNT" -gt 0 ]; then
    for item in "${FAILED_LIST[@]}"; do
        echo "  - $item"
    done
fi

# Log summary to logfile
{
    echo
    echo "===== Installation Summary ====="
    echo "Succeeded: $SUCCEEDED_COUNT"
    echo "Failed:    $FAILED_COUNT"
    if [ "$FAILED_COUNT" -gt 0 ]; then
        for item in "${FAILED_LIST[@]}"; do
            echo "  - $item"
        done
    fi
} >> "$LOG_FILE"

# ==============================
# Final Launch Prompt
# ==============================
cd ~ # always return to home before prompting
header "Launch"
printf "${PINK}Do you want to start guhwm now? (y/n): ${RESET}"
read -r launch_now
if [[ "$launch_now" =~ ^[Yy]$ ]]; then
    if $DRY_RUN; then
        echo -e "${PINK}[DRY-RUN] Would run startx now.${RESET}"
        echo "[DRY-RUN] Would run startx now." >> "$LOG_FILE"
    else
        echo -e "${PINK}Starting guhwm...${RESET}"
        echo "User chose to start guhwm immediately." >> "$LOG_FILE"
        sleep 1
        exec startx
    fi
else
    echo -e "${PINK}guhwm will start automatically on reboot.${RESET}"
    echo "User chose not to start guhwm immediately." >> "$LOG_FILE"
fi