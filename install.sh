#!/usr/bin/bash

# Pink (bright magenta)
echo -e "\e[1;35mThank you for trying guhwm! ;3\e[0m"

echo

# Pink (bright magenta)
echo -e "\e[1;35mYou'll be prompted to install optional software, which is highly recommended. Documentation is available.\e[0m"

# Pink (bright magenta)
echo -e "\e[1;35mNext, you will be prompted to select your preferred AUR helper.\e[0m"

# Pause for the user to read for 6 seconds
sleep 6

set -e

# ========== RETRY FUNCTION ==========
retry_pacman() {
    local retries=5
    local count=0

    until sudo pacman -S --noconfirm "$@"; do
        count=$((count+1))
        echo "pacman failed (attempt $count/$retries)"

        if [ $count -ge $retries ]; then
            echo "Giving up after $retries tries."
            return 1
        fi

        echo "Updating mirrors with reflector and retrying..."
        sudo pacman -S --needed --noconfirm reflector
        sudo reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
        sleep 2
    done
}

# ========== RETRY FUNCTION FOR AUR HELPER ==========
retry_aur() {
    local retries=5
    local count=0

    until "$aur_helper" -S --noconfirm "$@"; do
        count=$((count+1))
        echo "$aur_helper failed (attempt $count/$retries)"

        if [ $count -ge $retries ]; then
            echo "Giving up after $retries tries."
            return 1
        fi

        echo "Updating mirrors with reflector and retrying..."
        sudo pacman -S --needed --noconfirm reflector
        sudo reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist
        sleep 2
    done
}

# ========== 1. BASE PACKAGES ==========
# Xorg, dmenu, terminal, fonts, etc.
retry_pacman xorg dmenu kitty feh dunst clipmenu reflector nano noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-dejavu ttf-fira-code ttf-jetbrains-mono

# ========== 2. AUR HELPER SETUP ==========
echo -e "\e[35mChoose your preferred AUR helper:\e[0m"
select aur_helper in yay paru; do
    if [[ "$aur_helper" =~ ^(yay|paru)$ ]]; then
        echo -e "\e[36mSelected AUR helper: $aur_helper\e[0m"
        break
    else
        echo -e "\e[31mInvalid choice. Try again.\e[0m"
    fi
done

# Install AUR helper if missing
if ! command -v "$aur_helper" &>/dev/null; then
    echo -e "\e[36m$aur_helper not found. Installing...\e[0m"
    retry_pacman base-devel git

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
    "community-driven framework for managing your zsh configuration"
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
        echo -e "\e[35mEnter the numbers to remove (comma-separated), or press Enter to keep all:\e[0m"
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
            echo -e "\e[31mYou stupid, >:3 can you not read? It says enter the number, not names.. =TwT=\e[0m"
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
echo -e "\e[1;35mInstalling general software...\e[0m"
for pkg in "${general_software[@]}"; do
    echo -e "\e[34mInstalling: $pkg\e[0m"
    retry_aur "$pkg"
done

echo
echo -e "\e[1;35mInstalling shells...\e[0m"
for pkg in "${shells[@]}"; do
    if [[ "$pkg" == "oh-my-zsh" ]]; then
        echo -e "\e[36mInstalling Oh My Zsh...\e[0m"

        if ! command -v zsh &>/dev/null; then
            echo -e "\e[36mZsh not found. Installing it first...\e[0m"
            retry_aur zsh
        fi

        if [ ! -d "$HOME/.oh-my-zsh" ]; then
            echo -e "\e[36mRunning Oh My Zsh install script...\e[0m"
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        else
            echo -e "\e[36mOh My Zsh already installed. Skipping.\e[0m"
        fi
    else
        echo -e "\e[35mInstalling: $pkg\e[0m"
        retry_aur "$pkg"
    fi
done

echo
echo -e "\e[36mSetting up .xinitrc...\e[0m"

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

# A simple system status script for dwm
while true; do
  # Get CPU usage
  cpu_usage=\$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - \$1}')

  # Get memory usage
  mem_usage=\$(free -h | awk '/^Mem:/ {print \$3 "/" \$2}')

  # Get disk usage
  disk_usage=\$(df -h | awk '\$NF=="/"{printf "%s", \$5}')

  # Get date and time
  datetime=\$(date +"%a, %b %d, %R")

  # Use xsetroot to display the information
  xsetroot -name "\$cpu_usage% CPU | \$mem_usage Mem | \$disk_usage Disk | \$datetime"

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
    echo -e "\e[36m.xinitrc written to $XINITRC_PATH\e[0m"
else
    echo -e "\e[36mSkipped overwriting .xinitrc\e[0m"
fi

echo -e "\e[35mCloning and installing guhwm from Tapi-Mandy/guhwm...\e[0m"

# Clone repo (if it doesn't exist already)
if [ ! -d "$HOME/guhwm" ]; then
    git clone https://github.com/Tapi-Mandy/guhwm.git "$HOME/guhwm"
else
    echo -e "\e[35mRepo already cloned, pulling latest changes...\e[0m"
    git -C "$HOME/guhwm" pull
fi

# Build and install guhwm
cd "$HOME/guhwm" || { echo -e "\e[35mguhwm directory not found!\e[0m"; exit 1; }
echo -e "\e[35mBuilding and installing guhwm-1.0...\e[0m"
make clean
sudo make install

echo -e "\e[35mAll done!\e[0m"
echo -e "\e[35mguhwm-1.0 installed successfully!\e[0m"
echo
printf "\e[35mDo you want to start guhwm now? (y/n): \e[0m"
read -r launch_now
if [[ "$launch_now" =~ ^[Yy]$ ]]; then
    echo -e "\e[35mLaunching guhwm...\e[0m"
    sleep 1
    exec startx
else
    echo -e "\e[35mguhwm will automatically start when you reboot!\e[0m"
fi

cat >> "$HOME/.bash_profile" << 'EOF'

# Auto-start X on tty1
if [[ -z $DISPLAY ]] && [[ $(tty) == /dev/tty1 ]]; then
    exec startx
fi
EOF
