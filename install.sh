#!/usr/bin/bash

# Pink (bright magenta)
echo -e "\e[1;35mThanks for trying guhwm ;3\e[0m"

echo '...'

# Light red (bright red)
echo -e "\e[1;31mYou will be prompted to install software for guhwm, the first ones are absolutely necessary. The following software is optional. Documentation on them is available.\e[0m"

# Pink (bright magenta)
echo -e "\e[1;35mYou will also be prompted to choose an AUR helper.\e[0m"

# xorg
# default guhwm terminal
# feh for image viewing and wallpapers
sudo pacman -S --noconfirm xorg kitty feh dunst

set -e

# ========== 1. AUR HELPER SETUP ==========
echo "\e[1;31mChoose your preferred AUR helper:\e[0m"
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
    mpv
    krita
    vim
    uwufetch
    htop
    redshift
    vesktop-bin
)
general_descs=(
    "Fast, Private & Safe Web Browser"
    "Free, open source, and cross-platform media player"
    "Edit and paint images"
    "Vi Improved, a highly configurable, improved version of the vi text editor"
    "A meme system info tool for Linux, based on nyan/uwu trend on r/linuxmasterrace"
    "Interactive process viewer"
    "Adjusts the color temperature of your screen according to your surroundings"
    "A cross platform electron-based desktop app aiming to give you a snappier Discord experience with Vencord pre-installed"
)

# Shells
shells=(
    zsh
    oh-my-zsh
    fish
    ksh
)
shell_descs=(
    "Z Shell"
    "Open source, community-driven framework for managing your zsh configuration"
    "Smart and user friendly shell intended mostly for interactive use"
    "Korn shell (classic)"
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

echo "Cloning and installing dwm from Tapi-Mandy/guhwm..."

# Clone repo (if it doesn't exist already)
if [ ! -d "$HOME/guhwm" ]; then
    git clone https://github.com/Tapi-Mandy/guhwm.git "$HOME/guhwm"
else
    echo "Repo already cloned, pulling latest changes..."
    git -C "$HOME/guhwm" pull
fi

# Build and install dwm
cd "$HOME/guhwm/dwm" || { echo "dwm directory not found!"; exit 1; }
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
