#!/bin/sh

# ============================================
# ----------- .xinitrc for guhwm -------------
# ============================================

# =======================================================
# --- Set a background image ----------------------------
# =======================================================
# Set wallpaper
feh --bg-scale "__WALLPAPER_PATH__" &
 
# =======================================================
# --- Start D-Bus (needed for notification services) ----
# =======================================================
if command -v dbus-launch >/dev/null && [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
fi
 
# =======================================================
# --- Start the notification daemon ---------------------
# =======================================================
command -v dunst >/dev/null && dunst &

# =======================================================
# --- Clipboard Manager (Clipmenu) ----------------------
# =======================================================
command -v clipmenud >/dev/null && clipmenud &

# =======================================================
# --- Redshift for Eye Comfort --------------------------
# =======================================================
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

# =======================================================
# --- Keyboard Layout Switching -------------------------
# =======================================================
# Uncomment and adjust the next line to enable multiple layouts
# Example: US English, Bulgarian phonetic, Arabic phonetic

# setxkbmap -layout "us,bg,ara" -variant ",bas_phonetic,mac-phonetic" -option "grp:ctrl_space_toggle" &
 
# =======================================================
# --- System Bar Settings -------------------------------
# =======================================================
(
  prev_total=0
  prev_idle=0
 
  while true; do
    # -------------------------------
    # CPU usage (from /proc/stat)
    # -------------------------------
    read -r cpu user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
    idle_all=$((idle + iowait))
    total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    diff_total=$((total - prev_total))
    diff_idle=$((idle_all - prev_idle))
    cpu_usage=$((100 * (diff_total - diff_idle) / diff_total))
    prev_total=$total
    prev_idle=$idle_all
 
    # -------------------------------
    # Memory & Disk usage
    # -------------------------------
    mem_usage=$(free -h | awk '/^Mem:/ {print ($2-$7) "/" $2}')
    disk_usage=$(df -h --output=used,size,target | awk '$3=="/"{print $1 "/" $2}')
 
    # -------------------------------
    # Battery Status (if available)
    # -------------------------------
    battery_str=""
    if [ -d /sys/class/power_supply/BAT0 ]; then
        capacity=$(cat /sys/class/power_supply/BAT0/capacity)
        status=$(cat /sys/class/power_supply/BAT0/status)
        if [ "$status" = "Charging" ]; then
            battery_str=" | ⚡${capacity}%"
        else
            battery_str=" | 🔋${capacity}%"
        fi
    fi
 
    # -------------------------------
    # Date & Time
    # -------------------------------
    datetime=$(date +"%A, %b %d, %-I:%M %p")

    # -------------------------------
    # Salah (if enabled)
    # -------------------------------
    salah_str=$(cat /tmp/dwm-salah 2>/dev/null || echo "")

    # -------------------------------
    # Final status string
    # -------------------------------
    xsetroot -name "$cpu_usage% CPU | $mem_usage Mem | $disk_usage Disk${battery_str} | $datetime${salah_str:+ | $salah_str}"

    sleep 2
  done
) &

# =======================================================
# --- Salah Times (optional) ----------------------------
# =======================================================
# Toggle Salah times here: 1 = enabled, 0 = disabled
ENABLE_SALAH=0

if [ "$ENABLE_SALAH" -eq 1 ]; then
(
    # ---------------------------------------------------
    # Location settings (Change these!)
    # ---------------------------------------------------
    CITY="Sofia"             # Your city name (Example: Sofia)
    COUNTRY="Bulgaria"       # Your country name (Example: Bulgaria)
    TIMEZONE="Europe/Sofia"  # Examples: Europe/London, America/New_York
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
        tmp="$(mktemp)"

        # Download only if cache is missing or stale
        if [ ! -f "$cache" ] || [ "$(date -r "$cache" +%Y-%m-%d)" != "$(date +%Y-%m-%d)" ]; then
            if curl -fsS --retry 2 --max-time 15 \
               "https://api.aladhan.com/v1/calendarByCity/$yr/$mo?city=$CITY&country=$COUNTRY&method=$METHOD&timezonestring=$TIMEZONE" \
               -o "$tmp"; then
                mv "$tmp" "$cache"
            else
                rm -f "$tmp"
            fi
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

        if [ -n "$cachefile" ] && [ -s "$cachefile" ]; then
            jq -r --argjson idx $((10#$daynum-1)) '
.data[$idx].timings
| {Fajr, Dhuhr, Asr, Maghrib, Isha}
| to_entries[]
| "\(.key) \(.value)"' "$cachefile" \
            | sed -E 's/ ([0-9]{1,2}:[0-9]{2}).*/ \1/' \
            || return 1
        else
            echo "$OFFLINE_TIMES"; return 0
        fi
    }

    # ====================================================
    # Main Salah loop — writes "☪ NextPrayer HH:MM AM/PM"
    # ====================================================
    while true; do
        now=$(date +%H:%M)
        today=$(date +%Y-%m-%d)

        # Try to fetch today's times, else fallback
        times=$(get_times_for_date "$today" 2>/dev/null)
        [ -z "$times" ] && times="$OFFLINE_TIMES"

        next_prayer=""; next_time=""

        # Compare each prayer to current time
        while read -r prayer time; do
            adj_time=$(adjust_time "$prayer" "$time")
            comp_time=$(date -d "$adj_time" +%H:%M)  # For math comparison
            prayer_minutes=$((10#${comp_time%:*} * 60 + 10#${comp_time#*:}))
            now_minutes=$((10#${now%:*} * 60 + 10#${now#*:}))

            if [ "$prayer_minutes" -gt "$now_minutes" ]; then
                next_prayer=$prayer
                next_time=$adj_time
                break
            fi
        done <<PRAYERDATA
$times
PRAYERDATA

        # If all prayers passed, fall back to tomorrow's Fajr
        if [ -z "$next_prayer" ]; then
            tomorrow=$(date -d tomorrow +%Y-%m-%d)
            ttimes=$(get_times_for_date "$tomorrow" 2>/dev/null)

            if [ -n "$ttimes" ]; then
                next_prayer="Fajr"
                next_time=$(adjust_time "Fajr" "$(printf "%s" "$ttimes" | awk '/^Fajr / {print $2; exit}')")
            else
                next_prayer="Fajr"
                next_time=$(adjust_time "Fajr" "$(echo "$OFFLINE_TIMES" | awk '/^Fajr / {print $2; exit}')")
            fi
        fi

        # Output for dwm bar (example: "☪ Dhuhr 1:23 PM")
        echo "☪ $next_prayer $next_time" > /tmp/dwm-salah

        # Sleep until next prayer
        now_minutes=$((10#${now%:*} * 60 + 10#${now#*:}))
        comp_time=$(date -d "$next_time" +%H:%M)
        next_minutes=$((10#${comp_time%:*} * 60 + 10#${comp_time#*:}))
        sleep_minutes=$((next_minutes - now_minutes))
        [ $sleep_minutes -lt 1 ] && sleep_minutes=1

        sleep $((sleep_minutes * 60))
    done
) &
fi

# --- This must be the last line! ------------------------
exec dbus-run-session dwm
