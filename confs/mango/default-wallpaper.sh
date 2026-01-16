#!/bin/bash
# Self-destructing wallpaper initialization script
# Sets the default guhwm wallpaper with a transition animation
# Cleans up itself, guhwizard, and related config lines after execution

WALLPAPER="$HOME/Wallpapers/guhwm - Default.jpg"
SCRIPT_PATH="$(realpath "$0")"
MANGO_CONFIG="$HOME/.config/mango/config.conf"
GUHWIZARD_DIR="$HOME/guhwizard"

# Ensure swww daemon is running
if ! pgrep -x swww-daemon >/dev/null; then
    swww-daemon &
    sleep 1
fi

# Wait 2.5 seconds so user can appreciate the transition
sleep 2.5

# Set wallpaper with a smooth transition
swww img "$WALLPAPER" \
    --transition-type grow \
    --transition-pos center \
    --transition-duration 2 \
    --transition-fps 60

# If successful, clean up everything
if [ $? -eq 0 ]; then
    # 1. Remove the first-run lines from mango config and simplify to just swww restore
    if [ -f "$MANGO_CONFIG" ]; then
        # Remove the first-run script lines and replace with simple swww restore
        sed -i '/First-run wallpaper setup/d' "$MANGO_CONFIG"
        sed -i '/default-wallpaper\.sh/d' "$MANGO_CONFIG"
        sed -i '/Restore the last wallpaper.*first-run/d' "$MANGO_CONFIG"
        # Add clean swww restore line if not already present
        if ! grep -q "swww restore" "$MANGO_CONFIG"; then
            sed -i '/swww-daemon/a exec-once = sleep 0.5 \&\& swww restore \&' "$MANGO_CONFIG"
        fi
    fi

    # 2. Delete guhwizard directory if it exists
    [ -d "$GUHWIZARD_DIR" ] && rm -rf "$GUHWIZARD_DIR"

    # 3. Delete this script
    rm -f "$SCRIPT_PATH"
fi
