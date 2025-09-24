#!/usr/bin/bash

# Pink (bright magenta)
echo -e "\e[1;35mThanks for trying guhwm ;3\e[0m"

echo '...'

# Light red (bright red)
echo -e "\e[1;31mYou will be prompted to install software for guhwm, installing them is optional but recommended by guhwm. Documentation on them is available.\e[0m"

# Pink (bright magenta)
echo -e "\e[1;35mYou will also be prompted to choose an AUR helper.\e[0m"

# Pause for the user to read for 5 seconds
sleep 5

# X Window System
# Generic menu for X
# Default terminal for guhwm
# Image viewer and wallpaper manager
# Customizable and lightweight notification-daemon
# Fonts
sudo pacman -S --noconfirm xorg dmenu kitty feh dunst noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-dejavu ttf-fira-code ttf-jetbrains-mono

set -e

# ========== 1. AUR HELPER SETUP ==========
# Pink (bright magenta)
echo -e "\e[35mChoose your preferred AUR helper:\e[0m"
select aur_helper in yay paru pikaur; do
    if [[ "$aur_helper" =~ ^(yay|paru|pikaur)$ ]]; then
        echo "Selected AUR helper: $aur_helper"
        break
    else
        echo "Invalid choice. Try again."
    fi
done

# Install AUR helper if missing
if ! command -v "$aur_helper" &>/dev/null; then
    echo "$aur_helper not found. Installing..."
    sudo pacman -S --needed --noconfirm base-devel git

    tmpdir=$(mktemp -d)
    cd "$tmpdir"
    git clone "https://aur.archlinux.org/$aur_helper.git"
    cd "$aur_helper"
    makepkg -si --noconfirm
    cd ~
    rm -rf "$tmpdir"
fi

# ========== 2. SOFTWARE LISTS ==========
# General software
general_software=(
    firefox
    vesktop-bin
    uwufetch
    krita
    scrot
    vim
    htop
    mpv
    redshift
)
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

# Shells
shells=(
    zsh
    oh-my-zsh
    fish
    ksh
)
shell_descs=(
    "A very advanced and programmable shell"
    "Open source, community-driven framework for managing your zsh configuration"
    "Smart and user friendly shell intended mostly for interactive use"
    "The Original AT&T Korn Shell"
)

# ========== 3. REMOVAL FUNCTION ==========
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
        echo "Enter the numbers to remove (comma-separated), or press Enter to keep all:"
        read -r input

        if [[ -z "$input" ]]; then
            break
        fi

        # Validate input
        IFS=',' read -ra indices <<< "$input"
        valid=true

        for index in "${indices[@]}"; do
            index=$(echo "$index" | xargs)  # trim spaces
            if ! [[ "$index" =~ ^[0-9]+$ ]]; then
                valid=false
                break
            elif (( index < 0 || index >= ${#items[@]} )); then
                valid=false
                break
            fi
        done

        if ! $valid; then
            echo "You stupid, >:3 can you not read? It says enter the number, not names.. =TwT="
            continue
        fi

        # Remove selected items
        for index in "${indices[@]}"; do
            index=$(echo "$index" | xargs)
            echo "Removing: ${items[$index]}"
            unset 'items[index]'
            unset 'descs[index]'
        done

        # Rebuild arrays
        items=("${items[@]}")
        descs=("${descs[@]}")
        break
    done
}

# ========== 4. REMOVE UNWANTED PACKAGES ==========
remove_items general_software general_descs "General Software"
remove_items shells shell_descs "Shells"

# ========== 5. INSTALLATION ==========
echo
echo "Installing general software..."
for pkg in "${general_software[@]}"; do
    echo "Installing: $pkg"
    "$aur_helper" -S --noconfirm "$pkg"
done

echo
echo "Installing shells..."
for pkg in "${shells[@]}"; do
    if [[ "$pkg" == "oh-my-zsh" ]]; then
        echo "Installing Oh My Zsh..."

        if ! command -v zsh &>/dev/null; then
            echo "Zsh not found. Installing it first..."
            "$aur_helper" -S --noconfirm zsh
        fi

        if [ ! -d "$HOME/.oh-my-zsh" ]; then
            echo "Running Oh My Zsh install script..."
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        else
            echo "Oh My Zsh already installed. Skipping."
        fi
    else
        echo "Installing: $pkg"
        "$aur_helper" -S --noconfirm "$pkg"
    fi
done

echo
echo "Setting up .xinitrc..."

XINITRC_PATH="$HOME/.xinitrc"

# Ask if we should overwrite an existing .xinitrc
if [ -f "$XINITRC_PATH" ]; then
    echo ".xinitrc already exists at $XINITRC_PATH"
    echo "Do you want to overwrite it with the new one? (y/n)"
    read -r overwrite_choice
    if [[ "$overwrite_choice" =~ ^[Yy]$ ]]; then
        overwrite=true
    else
        overwrite=false
    fi
else
    overwrite=true
fi

# If overwriting is allowed, proceed
if [ "$overwrite" = true ]; then
    # Set the wallpaper directory
    WALLPAPER_DIR="$HOME/guhwm/Wallpapers"
    
    # Randomly select a wallpaper from the directory
    WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname \*.jpg -o -iname \*.png -o -iname \*.jpeg \) | shuf -n 1)

    # If no wallpaper was found, set a default
    if [ -z "$WALLPAPER" ]; then
        WALLPAPER="$HOME/guhwm/Wallpapers/guhwm-default.png"
    fi

    # Create the .xinitrc file with the random wallpaper logic
    cat > "$XINITRC_PATH" <<EOF
#!/bin/sh

# Set a random background image (using feh)
feh --bg-scale "$WALLPAPER" &

# Continuously update the DWM status bar with date and time
while :; do
    xsetroot -name "\$(date +"%a, %b %d %H:%M:%S")"
    sleep 1
done &

# A simple system status script for dwm
while true; do
  # Get CPU usage (e.g., from `top` or a more lightweight tool)
  cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

  # Get memory usage
  mem_usage=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')

  # Get disk usage
  disk_usage=$(df -h | awk '$NF=="/"{printf "%s", $5}')

  # Get date and time
  datetime=$(date +"%a %b %d %R")

  # Use xsetroot to display the information
  xsetroot -name "$cpu_usage% CPU | $mem_usage Mem | $disk_usage Disk | $datetime"

  # Wait for 1 second before updating again
  sleep 1
done &

# Start the notification daemon
dunst &

# Launch Redshift for eye comfort
command -v redshift >/dev/null 2>&1 && redshift -O 3500 &

# Set up keyboard layouts and switch between with Ctrl+Space
# Uncomment the next line if you want keyboard layouts:
# setxkbmap -layout "us,bg,ara" -variant ",bas_phonetic,mac-phonetic" -option "grp:ctrl_space_toggle" &

# This must be the very last line!
exec dwm
EOF

    chmod +x "$XINITRC_PATH"
    echo ".xinitrc written to $XINITRC_PATH"
else
    echo "Skipped overwriting .xinitrc"
fi

echo "Cloning and installing dwm from Tapi-Mandy/guhwm..."

# Clone repo (if it doesn't exist already)
if [ ! -d "$HOME/guhwm" ]; then
    git clone https://github.com/Tapi-Mandy/guhwm.git "$HOME/guhwm"
else
    echo "Repo already cloned, pulling latest changes..."
    git -C "$HOME/guhwm" pull
fi

# Build and install dwm
cd "$HOME/guhwm" || { echo "dwm directory not found!"; exit 1; }
echo "Building and installing dwm..."
make clean
sudo make install

echo "guhwm installed successfully!"
echo "All done!"
read -rp ":clapper: Do you want to start dwm now? (y/n): " launch_now
if [[ "$launch_now" =~ ^[Yy]$ ]]; then
    echo "Launching dwm..."
    sleep 1
    exec startx
else
    echo "dwm will automatically start when you reboot!"
fi
