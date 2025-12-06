#!/bin/sh
# =======================================================
# --- guhwm .xinitrc ------------------------------------
# =======================================================

# === Compositor ========================================
picom -b &

# === Polybar ===========================================
# Configuration: ~/.config/polybar/
# To toggle visibility: Alt+B (or your mod key + B)
~/.config/polybar/launch.sh &

# === Notification Daemon ===============================
pino &

# === Hotkey Daemon =====================================
sxhkd &

# === Redshift ==========================================
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

# === guhwall ===========================================
# Restore the Wallust Color Scheme
# Wallust stores color sequences in ~/.cache/wallust/sequences
# This applies the last generated color scheme to terminals
cat ~/.cache/wallust/sequences 2>/dev/null &

# Restore the Wallpaper Image
# guhwall uses 'feh' to set wallpapers, which saves a restore script at ~/.fehbg
# This restores the last wallpaper on each login
[ -f ~/.fehbg ] && sh ~/.fehbg &

# --- First Run ---------------------------------
# Launches guhwall only on the very first startup
if [ ! -f ~/.cache/guhwall_first_run ]; then
    mkdir -p ~/.cache
    touch ~/.cache/guhwall_first_run
    # Run guhwall in the background
    guhwall &
fi

# === Keyboard Layouts ==================================
# Uncomment and adjust the next line to enable multiple layouts
# Example: US English, Bulgarian Traditional phonetic, Arabic Macintosh phonetic

# setxkbmap -layout "us,bg,ara" -variant ",phonetic,mac-phonetic" -option "grp:ctrl_space_toggle" &

exec dbus-run-session dwm