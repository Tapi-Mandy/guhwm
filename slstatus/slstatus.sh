#!/bin/sh

############################################
#                SETTINGS                  #
############################################
# Switch ON/OFF Salah times
ENABLE_SALAH=0

# Icons (Nerd Fonts)
ICON_CPU=""
ICON_RAM=""
ICON_DISK=""
ICON_VOL=""
ICON_VOL_MUTE=""
ICON_WIFI=""
ICON_BAT=""
ICON_BAT_CHG=""
ICON_CLOCK=""
ICON_SALAH="☪"

############################################
#         BASIC STATUS MODULES             #
############################################

cpu() {
    # Accuracy fix: Calculate current usage over a 0.1s split.
    read -r cpu a b c previdle rest < /proc/stat
    prevtotal=$((a+b+c+previdle))
    sleep 0.1
    read -r cpu a b c idle rest < /proc/stat
    total=$((a+b+c+idle))
    diff=$((total-prevtotal))
    [ "$diff" -eq 0 ] && diff=1 
    cpu_usage=$((100*( (total-prevtotal) - (idle-previdle) ) / diff ))
    printf "%s %d%%" "$ICON_CPU" "$cpu_usage"
}

ram() {
    free -m | awk -v icon="$ICON_RAM" '/Mem:/ {printf "%s %dMB/%dMB", icon, $3, $2}'
}

disk() {
    df -h / | awk -v icon="$ICON_DISK" 'NR==2 {print icon" "$4}'
}

vol() {
    # Using alsa-utils (amixer)
    amixer_out=$(amixer sget Master 2>/dev/null | tail -n1)
    # Check if muted
    if echo "$amixer_out" | grep -q "\[off\]"; then
        echo "$ICON_VOL_MUTE Muted"
    else
        # Extract percentage
        vol=$(echo "$amixer_out" | grep -o "\[[0-9]*%\]" | tr -d '[]%')
        echo "$ICON_VOL ${vol}%"
    fi
}

wifi() {
    ssid=$(iwgetid -r 2>/dev/null)
    [ -n "$ssid" ] && echo "$ICON_WIFI $ssid" || echo "$ICON_WIFI NoWiFi"
}

battery() {
    found=0
    for bat in /sys/class/power_supply/BAT*; do
        [ -e "$bat" ] || continue
        # Read files using shell built-in (much faster)
        read -r cap < "$bat/capacity" 2>/dev/null
        read -r stat < "$bat/status" 2>/dev/null
        [ -n "$cap" ] || continue
        
        icon="$ICON_BAT"
        [ "$stat" = "Charging" ] && icon="$ICON_BAT_CHG"

        printf "%s %s%%" "$icon" "$cap"
        found=1
        return 
    done
    [ "$found" -eq 0 ] && echo ""
}

date_time() {
    date "+$ICON_CLOCK %a %b %d %-I:%M %p"
}

############################################
#           SALAH TIMES DAEMON             #
############################################
# We define the Salah logic as a function so we can spawn it 
# without blocking the main script.
run_salah_daemon() {
    (
        # ---------------------------------------------------
        # Location settings (Change these!)
        # ---------------------------------------------------
        CITY="Sofia"             # Your city name (Example: Sofia)
        COUNTRY="Bulgaria"       # Your country name (Example: Bulgaria)
        TIMEZONE="Europe/Sofia"  # Examples: Europe/Sofia, America/New_York
                                 # !! Must match your system timezone
                                 # --> Run `timedatectl` or check /usr/share/zoneinfo

        METHOD=3   # Muslim World League (MWL) — Very popular globally.
                   #
                   # Other popular methods:
                   #   2 = Islamic Society of North America (ISNA)
                   #   4 = Umm al-Qura, Makkah
                   #   5 = Egyptian General Authority of Survey
                   #   14 = Spiritual Administration of Muslims of Russia
                   # API reference: https://api.aladhan.com/v1/methods
                   # Choose the one matching your mosque/local practice.

        # ---------------------------------------------------
        # Cache settings (API calls are cached daily/monthly)
        # ---------------------------------------------------
        CACHE_DIR="$HOME/.cache/salah"
        mkdir -p "$CACHE_DIR"

        # ----------------------------------------------------------
        # Salah offsets (minutes) — tweak for mosque adjustments
        # ----------------------------------------------------------
        # Example:
        #   If your local mosque does Fajr 5 min later, set OFFSET_Fajr=5
        #   If Isha is called 10 min earlier, set OFFSET_Isha=-10
        #   Leave as 0 if no adjustment is needed.
        OFFSET_Fajr=0
        OFFSET_Dhuhr=0
        OFFSET_Asr=0
        OFFSET_Maghrib=0
        OFFSET_Isha=0

        # ---------------------------------------------------
        # Offline fallback times (used if API unreachable)
        # ---------------------------------------------------
        # Always in 24h HH:MM format. These are only used as a backup.
        OFFLINE_TIMES="Fajr 05:10
Dhuhr 12:30
Asr 15:45
Maghrib 18:20
Isha 19:45"

        # ====================================================
        # Adjust a given HH:MM by prayer offset and format
        # ====================================================
        adjust_time() {
            prayer="$1"; time="$2"
            hour=${time%:*}
            min=${time#*:}
            total=$((10#$hour * 60 + 10#$min))

            case "$prayer" in
                Fajr)     total=$((total + OFFSET_Fajr)) ;;
                Dhuhr)    total=$((total + OFFSET_Dhuhr)) ;;
                Asr)      total=$((total + OFFSET_Asr)) ;;
                Maghrib)  total=$((total + OFFSET_Maghrib)) ;;
                Isha)     total=$((total + OFFSET_Isha)) ;;
            esac

            # Wrap around if time goes before 00:00 or after 23:59
            if [ $total -lt 0 ]; then total=$((total + 1440)); fi
            if [ $total -ge 1440 ]; then total=$((total - 1440)); fi

            hh=$((total / 60))
            mm=$((total % 60))
            printf -v raw "%02d:%02d" "$hh" "$mm"

            # Always return in 12h with AM/PM (e.g. 5:49 AM, 7:15 PM)
            date -d "$raw" +"%-I:%M %p"
        }

        # ---------------------------------------------------
        # Fetch & cache prayer times from API
        # ---------------------------------------------------
        fetch_month_file() {
            yr="$1"; mo="$2"
            cache="$CACHE_DIR/$yr-$mo.json"
            
            # Download only if cache is missing or stale
            if [ ! -f "$cache" ]; then
                url="https://api.aladhan.com/v1/calendarByCity/$yr/$mo?city=$CITY&country=$COUNTRY&method=$METHOD&timezonestring=$TIMEZONE"
                curl -fsS --retry 2 --max-time 15 "$url" -o "$cache" || rm -f "$cache"
            fi
            [ -f "$cache" ] && echo "$cache"
        }

        # ---------------------------------------------------
        # Extract times for a specific date (from cache or fallback)
        # ---------------------------------------------------
        get_times_for_date() {
            target_date="$1"
            year=$(date -d "$target_date" +%Y)
            month=$(date -d "$target_date" +%m)
            daynum=$(date -d "$target_date" +%d)
            cachefile="$(fetch_month_file "$year" "$month")" || cachefile=""

            if [ -n "$cachefile" ] && [ -s "$cachefile" ] && command -v jq >/dev/null; then
                jq -r --argjson idx $((10#$daynum-1)) '
.data[$idx].timings
| {Fajr, Dhuhr, Asr, Maghrib, Isha}
| to_entries[]
| "\(.key) \(.value)"' "$cachefile" \
                | sed -E 's/ ([0-9]{1,2}:[0-9]{2}).*/ \1/' \
                || echo "$OFFLINE_TIMES"
            else
                echo "$OFFLINE_TIMES"
            fi
        }

        # ====================================================
        # Main Salah loop
        # ====================================================
        while true; do
            now=$(date +%H:%M)
            today=$(date +%Y-%m-%d)

            times=$(get_times_for_date "$today")
            [ -z "$times" ] && times="$OFFLINE_TIMES"

            next_prayer=""; next_time=""
            now_minutes=$((10#${now%:*} * 60 + 10#${now#*:}))

            while read -r prayer time; do
                [ -z "$prayer" ] && continue
                adj_time=$(adjust_time "$prayer" "$time")
                comp_time=$(date -d "$adj_time" +%H:%M)
                prayer_minutes=$((10#${comp_time%:*} * 60 + 10#${comp_time#*:}))
                
                if [ "$prayer_minutes" -gt "$now_minutes" ]; then
                    next_prayer=$prayer
                    next_time=$adj_time
                    break
                fi
            done <<PRAYERDATA
$times
PRAYERDATA

            if [ -z "$next_prayer" ]; then
                tomorrow=$(date -d tomorrow +%Y-%m-%d)
                ttimes=$(get_times_for_date "$tomorrow")
                raw_fajr=$(echo "$ttimes" | head -n1 | awk '{print $2}')
                [ -z "$raw_fajr" ] && raw_fajr="05:00"
                next_prayer="Fajr"
                next_time=$(adjust_time "Fajr" "$raw_fajr")
            fi

            echo "$ICON_SALAH $next_prayer $next_time" > /tmp/dwm-salah
            sleep 60
        done
    ) &
}

# ---------------------------------------------------
# DAEMON CONTROLLER (SINGLETON CHECK)
# ---------------------------------------------------
# This ensures we don't spawn a new Salah loop every second.
# We check if the process ID in the lockfile is still running.
if [ "$ENABLE_SALAH" -eq 1 ]; then
    PIDFILE="/tmp/slstatus-salah.pid"
    if [ ! -f "$PIDFILE" ] || ! kill -0 $(cat "$PIDFILE") 2>/dev/null; then
        # Not running, start it
        run_salah_daemon
        # Save the PID of the background job ($!)
        echo $! > "$PIDFILE"
    fi
fi

############################################
#           MAIN STATUS OUTPUT             #
############################################
# REMOVED 'while true' loop here. 
# slstatus calls this script repeatedly, so we run once and exit.

salah=""
[ "$ENABLE_SALAH" -eq 1 ] && salah="$(cat /tmp/dwm-salah 2>/dev/null)"

# Run CPU first (contains sleep delay)
cpu_info=$(cpu)
bat="$(battery)"

# Prepare common string
STATUS="$cpu_info | $(ram) | $(disk) | $(vol) | $(wifi)"

if [ -n "$bat" ]; then
    STATUS="$STATUS | $bat"
fi

STATUS="$STATUS | $(date_time)"

if [ -n "$salah" ]; then
    printf "%s\n | %s" "$STATUS" "$salah"
else
    printf "%s" "$STATUS"
fi
