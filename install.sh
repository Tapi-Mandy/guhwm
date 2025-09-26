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
# - Creates a Kitty config with a preset theme
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
# Aligned Section Header (fixed width)
# ==============================
# Use: header "Section Name"
header() {
    local title="$1"
    local width=45
    local tlen=${#title}
    if [ "$tlen" -ge $((width-2)) ]; then
        printf "== %s ==\n" "$title"
        return
    fi
    local total_pad=$((width - tlen - 2))
    local left_pad=$((total_pad/2))
    local right_pad=$((total_pad - left_pad))
    local left=$(printf '%*s' "$left_pad" '' | tr ' ' '=')
    local right=$(printf '%*s' "$right_pad" '' | tr ' ' '=')
    printf "%s %s %s\n" "$left" "$title" "$right"
}

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
header "$title"
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
<<<<<<< HEAD
# Default Shell Setup
# ==============================
if [ ${#shells[@]} -gt 0 ]; then
    first_shell="${shells[0]}"
    case "$first_shell" in
        zsh|oh-my-zsh) shell_path="/bin/zsh" ;;
        fish)          shell_path="/usr/bin/fish" ;;
        ksh)           shell_path="/usr/bin/ksh" ;;
        *)             shell_path="/bin/bash" ;;
    esac

    if [[ "$shell_path" != "/bin/bash" ]]; then
        echo -e "${PINK}Setting default shell to $shell_path...${RESET}"
        if chsh -s "$shell_path" "$USER"; then
            log_status "Default shell ($first_shell)" "OK"
        else
            log_status "Default shell ($first_shell)" "FAIL"
        fi
    else
        echo -e "${PINK}Keeping default shell as bash.${RESET}"
    fi
fi

# ==============================
# Auto-start X in correct profile (skip for fish)
# ==============================
if [[ "$shell_path" != "/usr/bin/fish" ]]; then
    case "$shell_path" in
        /bin/bash)      profile_file="$HOME/.bash_profile" ;;
        /bin/zsh)       profile_file="$HOME/.zprofile" ;;
        /usr/bin/ksh)   profile_file="$HOME/.profile" ;;
        *)              profile_file="$HOME/.bash_profile" ;;  # fallback
    esac

    if ! grep -q "exec startx" "$profile_file" 2>/dev/null; then
        echo -e "${PINK}Adding startx auto-start to $profile_file...${RESET}"
        {
            echo
            echo "# Auto-start X only on tty1"
            echo 'if [[ -z $DISPLAY ]] && [[ $(tty) == /dev/tty1 ]]; then'
            echo '    exec startx'
            echo 'fi'
        } >> "$profile_file"
        log_status "Startx in $profile_file" "OK"
    else
        echo -e "${PINK}Startx already present in $profile_file. Skipping.${RESET}"
    fi
else
    echo -e "${PINK}Skipping startx setup for fish (not supported).${RESET}"
fi

# ==============================
# .xinitrc Setup
=======
# Xinitrc Setup
>>>>>>> parent of a39831d (Updated install.sh)
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
# Kitty Configuration
# ==============================
echo -e "${PINK}Setting up Kitty configuration...${RESET}"
KITTY_CONFIG_DIR="$HOME/.config/kitty"
KITTY_CONFIG_FILE="$KITTY_CONFIG_DIR/kitty.conf"

mkdir -p "$KITTY_CONFIG_DIR"

cat > "$KITTY_CONFIG_FILE" << 'EOF'
# BEGIN_KITTY_THEME
# Black Metal
include current-theme.conf
# END_KITTY_THEME
font_size 17.0
enable_audio_bell yes
scrollback_lines 20000
scrollback_pager less --chop-long-lines --RAW-CONTROL-CHARS +INPUT_LINE_NUMBER
scrollback_pager_history_size 0
scrollback_fill_enlarged_window no
repaint_delay 20
input_delay 2
sync_to_monitor no
enable_wayland no
linux_display_server x11
wayland_enable_csd no
background_opacity 0.85
background_blur 0
dynamic_background_opacity yes
dim_opacity 0.75
dim_inactive yes
selection_foreground #000000
selection_background #fffacd
cursor_shape beam
cursor_blink_interval 1
cursor_stop_blinking_after 0
copy_on_select yes
paste_actions no-op
open_url_with default
url_style curly
url_prefixes file ftp ftps gemini gopher http https irc ircs kitty mailto news sftp ssh
detect_urls yes
mouse_hide_wait 2.0
touch_scroll_multiplier 1.0
mouse_map left click ungrab_mouse
mouse_map shift+left click link
mouse_map ctrl+left click paste
mouse_map middle click paste
mouse_map ctrl+middle click no-op
mouse_map shift+middle click no-op
mouse_map right click paste
mouse_map shift+right click link
mouse_map ctrl+right click no-op
mouse_map doubleclick select_word
mouse_map tripleclick select_line
mouse_map quadrupleclick select_block
focus_follows_mouse yes
pointer_shape_when_grabbed arrow
resize_debounce_time 0.1
resize_draw_strategy scale
resize_in_steps no
remember_window_size no
initial_window_width 80c
initial_window_height 24c
enabled_layouts *
window_border_width 2
draw_minimal_borders yes
placement_strategy center
hide_window_decorations yes
resize_window_margin_width 4
resize_window_margin_height 4
window_padding_width 4
active_border_color #ff69b4
inactive_border_color #555555
bell_border_color #ff0000
inactive_text_alpha 0.75
active_tab_font_style bold-italic
inactive_tab_font_style normal
tab_bar_edge bottom
tab_bar_margin_width 0
tab_bar_margin_height 0
tab_bar_style powerline
tab_bar_min_tabs 2
tab_switch_strategy previous
tab_bar_background #1a1b26
tab_bar_foreground #c0caf5
active_tab_foreground #1a1b26
active_tab_background #7aa2f7
active_tab_font_color #ffffff
inactive_tab_foreground #c0caf5
inactive_tab_background #3b4261
inactive_tab_font_color #aaaaaa
tab_separator " "
tab_activity_symbol none
tab_title_template {index}: {title}
tab_title_max_length 20
close_on_child_death no
quit_after_last_window_closed no
hide_tab_bar_if_only_one_tab no
map ctrl+shift+enter new_window
map ctrl+shift+t new_tab
map ctrl+shift+w close_window
map ctrl+shift+q close_tab
map ctrl+shift+right next_tab
map ctrl+shift+left previous_tab
map ctrl+shift+l next_layout
map ctrl+shift+h previous_layout
map ctrl+shift+up increase_font_size
map ctrl+shift+down decrease_font_size
map ctrl+shift+backspace restore_font_size
map ctrl+shift+n reset_terminal
map ctrl+shift+f search
map ctrl+shift+v paste
map ctrl+shift+c copy_to_clipboard
map ctrl+shift+u input_unicode
map ctrl+shift+s launch --stdin-source=@screen_scrollback --type=overlay less
map ctrl+shift+o pass_selection_to_program
map ctrl+shift+b set_background_opacity
map ctrl+shift+m toggle_maximized
map ctrl+shift+f11 toggle_fullscreen
map ctrl+shift+y toggle_ideographic_space
map ctrl+shift+d detach_window
map ctrl+shift+g toggle_grids
map ctrl+shift+e toggle_tab_bar
map ctrl+shift+k scroll_line_up
map ctrl+shift+j scroll_line_down
map ctrl+shift+page_up scroll_page_up
map ctrl+shift+page_down scroll_page_down
map ctrl+shift+home scroll_home
map ctrl+shift+end scroll_end
map ctrl+shift+z show_scrollback
map ctrl+shift+plus new_split
map ctrl+shift+minus close_split
map ctrl+shift+period next_split
map ctrl+shift+comma previous_split
map ctrl+shift+slash move_window
map ctrl+shift+backslash detach_tab
map ctrl+shift+semicolon move_tab
map ctrl+shift+1 goto_tab 1
map ctrl+shift+2 goto_tab 2
map ctrl+shift+3 goto_tab 3
map ctrl+shift+4 goto_tab 4
map ctrl+shift+5 goto_tab 5
map ctrl+shift+6 goto_tab 6
map ctrl+shift+7 goto_tab 7
map ctrl+shift+8 goto_tab 8
map ctrl+shift+9 goto_tab 9
map ctrl+shift+0 goto_tab 10
map ctrl+alt+1 goto_tab 11
map ctrl+alt+2 goto_tab 12
map ctrl+alt+3 goto_tab 13
map ctrl+alt+4 goto_tab 14
map ctrl+alt+5 goto_tab 15
map ctrl+alt+6 goto_tab 16
map ctrl+alt+7 goto_tab 17
map ctrl+alt+8 goto_tab 18
map ctrl+alt+9 goto_tab 19
map ctrl+alt+0 goto_tab 20
map ctrl+shift+p launch --type=overlay
map ctrl+shift+x launch --type=window
map ctrl+shift+r launch --type=tab
map ctrl+shift+i launch --type=overlay --stdin-source=@screen
map ctrl+shift+o launch --type=overlay --stdin-source=@screen_scrollback
map ctrl+shift+a launch --type=window --stdin-source=@screen
map ctrl+shift+z launch --type=window --stdin-source=@screen_scrollback
map ctrl+shift+b launch --type=tab --stdin-source=@screen
map ctrl+shift+m launch --type=tab --stdin-source=@screen_scrollback
EOF

log_status "Kitty configuration" "OK"
echo -e "${PINK}Kitty config written to:${RESET} $KITTY_CONFIG_FILE"
echo "Kitty config written to: $KITTY_CONFIG_FILE" >> "$LOG_FILE"
# ==============================
# Summary
# ==============================
echo
header "="
echo " Installation Summary"
header "="
echo " Succeeded: $SUCCEEDED_COUNT"
echo " Failed:    $FAILED_COUNT"
if [ "$FAILED_COUNT" -gt 0 ]; then
    for item in "${FAILED_LIST[@]}"; do
        echo "  - $item"
    done
fi
header "="

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
