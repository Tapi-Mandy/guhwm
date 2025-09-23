# Set a background image (using feh)
feh --bg-scale /path/to/your/image.jpg &

# This command continuously updates the DWM status bar with the date and time.
while :; do xsetroot -name "$(date +"%a, %b %d %H:%M:%S")"; sleep 1; done &

# Start the notification daemon
dunst &

# Launch Redshift for eye comfort
command -v redshift >/dev/null 2>&1 && redshift -O 3500 &

# Set up keyboard layouts and switch between with Ctrl+Space
(Remove the # if you want to enable layout switching)

# setxkbmap -layout "us,bg,ara" -variant ",bas_phonetic,mac-phonetic" -option "grp:ctrl_space_toggle" &

# This must be the very last line!
exec dwm
