#!/bin/bash
# Self-destructing wallpaper initialization script
# Sets the default guhwm wallpaper with a transition animation
# Cleans up itself, guhwizard, and related config lines after execution

set -euo pipefail

# --- Configuration ---
WALLPAPER="$HOME/Wallpapers/guhwm - Default.png"
SCRIPT_PATH="$(realpath "$0")"
MANGO_CONFIG="$HOME/.config/mango/config.conf"
SCRIPT_CONF="$HOME/.config/mango/scripts/default-wallpaper.sh"
GUHWIZARD_DIR="$HOME/guhwizard"

MAX_DAEMON_WAIT=10  # Maximum seconds to wait for swww-daemon

# --- Ensure wallpaper exists ---
if [ ! -f "$WALLPAPER" ]; then
    echo "[default-wallpaper.sh] ERROR: Wallpaper not found: $WALLPAPER" >&2
    exit 1
fi

# --- Ensure swww daemon is running and ready ---
if ! pgrep -x swww-daemon > /dev/null; then
    swww-daemon &
    DAEMON_PID=$!
    
    # Wait for daemon to be ready (poll for up to MAX_DAEMON_WAIT seconds)
    for i in $(seq 1 $MAX_DAEMON_WAIT); do
        if swww query &> /dev/null; then
            echo "Daemon ready after ${i}s"
            break
        fi
        sleep 1
    done
    
    # Final check
    if ! swww query &> /dev/null; then
        echo "[default-wallpaper.sh] ERROR: swww-daemon failed to initialize" >&2
        exit 1
    fi
else
    echo "--> swww-daemon already running"
fi

# Wait for compositor to fully initialize
sleep 2

# --- Set wallpaper with transition animation ---
echo "--> Setting wallpaper: $WALLPAPER"
if swww img "$WALLPAPER" \
    --transition-type grow \
    --transition-pos center \
    --transition-duration 2 \
    --transition-fps 60; then
    echo "--> Wallpaper set successfully"
else
    echo "[default-wallpaper.sh] ERROR: Failed to set wallpaper" >&2
    exit 1
fi

# --- Cleanup: Remove first-run config lines ---
if [ -f "$MANGO_CONFIG" ]; then

    # Create backup
    cp "$MANGO_CONFIG" "$MANGO_CONFIG.bak"
    
    # Remove any lines containing default-wallpaper.sh
    sed -i '/default-wallpaper\.sh/d' "$MANGO_CONFIG"
    
    # Remove any existing swww restore lines to avoid duplicates
    sed -i '/swww restore/d' "$MANGO_CONFIG"
    
    # Add simple swww restore after swww-daemon
    sed -i '/swww-daemon/a exec-once = sleep 1 \&\& swww restore \&' "$MANGO_CONFIG"
    echo "--> Added swww restore to config.conf"
    
    # Remove backup if successful
    rm -f "$MANGO_CONFIG.bak"
fi

# --- Cleanup: Remove guhwizard directory ---
if [ -d "$GUHWIZARD_DIR" ]; then
    rm -rf "$GUHWIZARD_DIR"
fi

# --- Self-destruct ---
sleep 3

# Delete from both possible locations
rm -f "$SCRIPT_PATH" "$SCRIPT_CONF"
