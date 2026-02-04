#!/usr/bin/env bash
# Nightlight toggle script for wlsunset in SwayNC

FLAG_FILE="$HOME/.cache/nightlight_enabled"

if pgrep -x "wlsunset" > /dev/null; then
    pkill -x "wlsunset"
    rm -f "$FLAG_FILE"
else
    wlsunset -s 00:00 -S 23:59 -t 3400 -T 3401 &
    touch "$FLAG_FILE"
fi