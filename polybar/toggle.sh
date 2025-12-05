#!/usr/bin/env bash

# Toggle polybar visibility
# Usage: bind this to a key in your window manager

if pgrep -x polybar > /dev/null; then
    # Polybar is running, hide it
    polybar-msg cmd hide
    
    # Check if hide worked (polybar-msg returns 0 on success)
    # If polybar doesn't support IPC, kill it instead
    if [ $? -ne 0 ]; then
        killall -q polybar
    fi
else
    # Polybar is not running or hidden, show/start it
    polybar-msg cmd show 2>/dev/null || ~/.config/polybar/launch.sh
fi
