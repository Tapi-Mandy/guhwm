#!/usr/bin/env bash
# Nightlight toggle script for gammastep

if pgrep -x gammastep > /dev/null; then
    # Gammastep is running, kill it
    pkill gammastep
    notify-send -u low "Nightlight" "Disabled" -i weather-clear-night
else
    # Gammastep is not running, start it
    gammastep &
    notify-send -u low "Nightlight" "Enabled" -i weather-clear-night
fi
