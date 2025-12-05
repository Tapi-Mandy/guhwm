#!/usr/bin/env bash

# ============================================================
#  POLYBAR LAUNCH SCRIPT - guhwm
# ============================================================
#  This script configures and launches polybar with dynamic
#  module detection (battery, salah, etc.)
# ============================================================

# ============================================================
#  SALAH (Prayer Times) CONFIGURATION
# ============================================================
#  Set SALAH_ENABLED to "true" to show prayer times
#  Set to "false" to completely disable the module
# ============================================================

SALAH_ENABLED="true"

# ============================================================
#  LOCATION SETTINGS (Optional - Auto-detected by default)
# ============================================================
#  Leave empty to auto-detect your location via IP geolocation.
#  Or manually set your coordinates for accuracy:
#
#  To find your coordinates:
#    1. Go to https://www.latlong.net/
#    2. Or search your city on Google Maps and check the URL
#
#  Example coordinates:
#    Makkah:     21.4225, 39.8262
#    Madinah:    24.5247, 39.5692
#    Cairo:      30.0444, 31.2357
#    London:     51.5074, -0.1278
#    New York:   40.7128, -74.0060
#    Toronto:    43.6532, -79.3832
# ============================================================

SALAH_LATITUDE=""      # Leave empty for auto-detection
SALAH_LONGITUDE=""     # Leave empty for auto-detection

# ============================================================
#  CALCULATION METHOD
# ============================================================
#  Choose the calculation method that matches your region
#  or preferred school of Islamic jurisprudence.
#
#  ID | Method                                        | Region
#  ---|-----------------------------------------------|------------------
#  1  | University of Islamic Sciences, Karachi      | Pakistan
#  2  | Islamic Society of North America (ISNA)      | North America
#  3  | Muslim World League (MWL)                    | Worldwide [DEFAULT]
#  4  | Umm Al-Qura University, Makkah               | Saudi Arabia
#  5  | Egyptian General Authority of Survey         | Egypt, Africa
#  7  | Institute of Geophysics, Tehran              | Iran
#  8  | Gulf Region                                  | UAE, Bahrain
#  9  | Kuwait                                       | Kuwait
#  10 | Qatar                                        | Qatar
#  11 | Majlis Ugama Islam Singapura                 | Singapore
#  12 | Union Organisations Islamiques de France     | France
#  13 | Diyanet İşleri Başkanlığı                    | Turkey
#  14 | Spiritual Administration of Muslims          | Russia
#  15 | Moonsighting Committee Worldwide             | Worldwide
#
#  Reference: https://aladhan.com/prayer-times-api#methods
# ============================================================

SALAH_METHOD="3"  # 3 = Muslim World League

# Export salah configuration
export SALAH_ENABLED SALAH_LATITUDE SALAH_LONGITUDE SALAH_METHOD

# Terminate already running bar instances
killall -q polybar

# Wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# ============================================================
#  BATTERY AUTO-DETECTION
# ============================================================
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

# ============================================================
#  BUILD MODULES LIST
# ============================================================
#  Modules are added dynamically based on system capabilities
# ============================================================

# Start with base modules (always present)
MODULES_RIGHT="pulseaudio memory cpu"

# Add battery module if on a laptop
if [ -n "$BATTERY_DEV" ]; then
  export POLYBAR_BATTERY="$BATTERY_DEV"
  export POLYBAR_ADAPTER="${ADAPTER_DEV:-AC}"
  MODULES_RIGHT="$MODULES_RIGHT battery"
  echo "Battery detected: $BATTERY_DEV (adapter: $POLYBAR_ADAPTER)"
else
  echo "No battery detected, running in desktop mode"
fi

# Add salah module if enabled
if [ "$SALAH_ENABLED" = "true" ]; then
  MODULES_RIGHT="$MODULES_RIGHT salah"
  echo "Salah module: enabled (method: $SALAH_METHOD)"
else
  echo "Salah module: disabled"
fi

# Add wlan at the end
MODULES_RIGHT="$MODULES_RIGHT wlan"

# Export the final modules list
export POLYBAR_MODULES_RIGHT="$MODULES_RIGHT"

# ============================================================
#  LAUNCH POLYBAR
# ============================================================
if type "xrandr" &>/dev/null; then
  for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
    MONITOR=$m polybar --reload main &
  done
else
  polybar --reload main &
fi

echo "Polybar launched..."
