#!/usr/bin/env bash

# Terminate already running bar instances
killall -q polybar

# Wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# ============================================
# Battery Auto-Detection
# ============================================
POWER_SUPPLY_PATH="/sys/class/power_supply"

# Find battery device (BAT0, BAT1, etc.)
BATTERY_DEV=""
for bat in "$POWER_SUPPLY_PATH"/BAT*; do
  if [ -d "$bat" ]; then
    BATTERY_DEV=$(basename "$bat")
    break
  fi
done

# Find AC adapter device (AC, ADP0, ADP1, ACAD, etc.)
ADAPTER_DEV=""
for adapter in "$POWER_SUPPLY_PATH"/{AC,ADP*,ACAD}; do
  if [ -d "$adapter" ]; then
    ADAPTER_DEV=$(basename "$adapter")
    break
  fi
done

# Set modules based on battery presence
if [ -n "$BATTERY_DEV" ]; then
  export POLYBAR_BATTERY="$BATTERY_DEV"
  export POLYBAR_ADAPTER="${ADAPTER_DEV:-AC}"
  export POLYBAR_MODULES_RIGHT="pulseaudio memory cpu battery wlan"
  echo "Battery detected: $BATTERY_DEV (adapter: $POLYBAR_ADAPTER)"
else
  export POLYBAR_MODULES_RIGHT="pulseaudio memory cpu wlan"
  echo "No battery detected, running in desktop mode"
fi

# ============================================
# Launch Polybar
# ============================================
if type "xrandr" &>/dev/null; then
  for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
    MONITOR=$m polybar --reload main &
  done
else
  polybar --reload main &
fi

echo "Polybar launched..."
