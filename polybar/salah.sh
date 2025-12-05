#!/usr/bin/env bash
# ============================================================
#  SALAH (Prayer Times) Module for Polybar
# ============================================================
#
#  This script fetches and displays Islamic prayer times.
#  It uses the Aladhan API: https://aladhan.com/prayer-times-api
#
#  FEATURES:
#    - Auto-detects your location using IP geolocation
#    - Caches prayer times to reduce API calls
#    - Shows the next upcoming prayer
#    - Highly configurable via environment variables
#
#  DEPENDENCIES:
#    - curl (for API requests)
#    - jq (for JSON parsing)
#
#  CONFIGURATION:
#    Set these environment variables in launch.sh:
#      SALAH_ENABLED    - true/false to enable/disable
#      SALAH_LATITUDE   - Your latitude (auto-detected if empty)
#      SALAH_LONGITUDE  - Your longitude (auto-detected if empty)
#      SALAH_METHOD     - Calculation method ID (see below)
#
# ============================================================
#  CALCULATION METHODS (SALAH_METHOD)
# ============================================================
#
#  ID | Method Name                                      | Region/Use
#  ---|--------------------------------------------------|------------------
#  1  | University of Islamic Sciences, Karachi          | Pakistan
#  2  | Islamic Society of North America (ISNA)          | North America
#  3  | Muslim World League (MWL)                        | Worldwide (DEFAULT)
#  4  | Umm Al-Qura University, Makkah                   | Saudi Arabia
#  5  | Egyptian General Authority of Survey             | Egypt, Africa
#  7  | Institute of Geophysics, University of Tehran    | Iran
#  8  | Gulf Region                                      | UAE, Qatar, etc.
#  9  | Kuwait                                           | Kuwait
#  10 | Qatar                                            | Qatar
#  11 | Majlis Ugama Islam Singapura                     | Singapore
#  12 | Union des Organisations Islamiques de France     | France
#  13 | Diyanet İşleri Başkanlığı                        | Turkey
#  14 | Spiritual Administration of Muslims, Russia      | Russia
#  15 | Moonsighting Committee Worldwide                 | Worldwide
#
#  Reference: https://aladhan.com/prayer-times-api#methods
#
# ============================================================

# Exit if module is disabled
if [[ "${SALAH_ENABLED:-true}" != "true" ]]; then
    exit 0
fi

# ============================================================
# CONFIGURATION
# ============================================================

# Default calculation method: Muslim World League (3)
# Change this or set SALAH_METHOD in launch.sh
METHOD="${SALAH_METHOD:-3}"

# Cache settings
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/polybar"
CACHE_FILE="$CACHE_DIR/salah_times.json"
LOCATION_CACHE="$CACHE_DIR/salah_location.json"
CACHE_MAX_AGE=3600  # Refresh prayer times every hour (in seconds)

# API endpoints
ALADHAN_API="https://api.aladhan.com/v1/timings"
IPINFO_API="https://ipinfo.io/json"

# Prayer names for display
declare -A PRAYER_NAMES=(
    ["Fajr"]="Fajr"
    ["Sunrise"]="Sunrise"
    ["Dhuhr"]="Dhuhr"
    ["Asr"]="Asr"
    ["Maghrib"]="Maghrib"
    ["Isha"]="Isha"
)

# ============================================================
# HELPER FUNCTIONS
# ============================================================

# Create cache directory if it doesn't exist
mkdir -p "$CACHE_DIR"

# Convert time string (HH:MM) to minutes since midnight
time_to_minutes() {
    local time="$1"
    local hours="${time%%:*}"
    local mins="${time##*:}"
    # Remove leading zeros to avoid octal interpretation
    hours=$((10#$hours))
    mins=$((10#$mins))
    echo $((hours * 60 + mins))
}

# Get current time in minutes since midnight
get_current_minutes() {
    local hours=$(date +%H)
    local mins=$(date +%M)
    hours=$((10#$hours))
    mins=$((10#$mins))
    echo $((hours * 60 + mins))
}

# Format minutes difference as "Xh Ym"
format_time_diff() {
    local diff="$1"
    if [[ $diff -lt 0 ]]; then
        diff=$((diff + 1440))  # Add 24 hours if negative (next day)
    fi
    local hours=$((diff / 60))
    local mins=$((diff % 60))
    if [[ $hours -gt 0 ]]; then
        echo "${hours}h ${mins}m"
    else
        echo "${mins}m"
    fi
}

# ============================================================
# LOCATION AUTO-DETECTION
# ============================================================

get_location() {
    # If user provided coordinates, use them
    if [[ -n "$SALAH_LATITUDE" && -n "$SALAH_LONGITUDE" ]]; then
        echo "$SALAH_LATITUDE,$SALAH_LONGITUDE"
        return 0
    fi

    # Check if we have a cached location (cache for 24 hours)
    if [[ -f "$LOCATION_CACHE" ]]; then
        local cache_age=$(($(date +%s) - $(stat -c %Y "$LOCATION_CACHE" 2>/dev/null || echo 0)))
        if [[ $cache_age -lt 86400 ]]; then
            local cached_loc=$(jq -r '.loc // empty' "$LOCATION_CACHE" 2>/dev/null)
            if [[ -n "$cached_loc" ]]; then
                echo "$cached_loc"
                return 0
            fi
        fi
    fi

    # Auto-detect location using IP geolocation
    local location_data
    location_data=$(curl -sf --max-time 5 "$IPINFO_API" 2>/dev/null)
    
    if [[ -n "$location_data" ]]; then
        echo "$location_data" > "$LOCATION_CACHE"
        local loc=$(echo "$location_data" | jq -r '.loc // empty')
        if [[ -n "$loc" ]]; then
            echo "$loc"
            return 0
        fi
    fi

    # Fallback: Makkah coordinates
    echo "21.4225,39.8262"
}

# ============================================================
# PRAYER TIMES FETCHING
# ============================================================

fetch_prayer_times() {
    local location="$1"
    local lat="${location%%,*}"
    local lon="${location##*,}"
    local date=$(date +%d-%m-%Y)
    
    local url="${ALADHAN_API}/${date}?latitude=${lat}&longitude=${lon}&method=${METHOD}"
    
    local response
    response=$(curl -sf --max-time 10 "$url" 2>/dev/null)
    
    if [[ -n "$response" ]]; then
        echo "$response" > "$CACHE_FILE"
        echo "$response"
        return 0
    fi
    
    return 1
}

get_prayer_times() {
    # Check cache first
    if [[ -f "$CACHE_FILE" ]]; then
        local cache_age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
        local cached_date=$(jq -r '.data.date.gregorian.date // empty' "$CACHE_FILE" 2>/dev/null)
        local today=$(date +%d-%m-%Y)
        
        # Use cache if it's from today and not too old
        if [[ "$cached_date" == "$today" && $cache_age -lt $CACHE_MAX_AGE ]]; then
            cat "$CACHE_FILE"
            return 0
        fi
    fi
    
    # Fetch fresh data
    local location
    location=$(get_location)
    fetch_prayer_times "$location"
}

# ============================================================
# MAIN LOGIC
# ============================================================

main() {
    local times_data
    times_data=$(get_prayer_times)
    
    if [[ -z "$times_data" ]]; then
        echo "--:--"
        exit 0
    fi
    
    # Extract prayer times from JSON
    local fajr=$(echo "$times_data" | jq -r '.data.timings.Fajr // empty' | cut -d' ' -f1)
    local sunrise=$(echo "$times_data" | jq -r '.data.timings.Sunrise // empty' | cut -d' ' -f1)
    local dhuhr=$(echo "$times_data" | jq -r '.data.timings.Dhuhr // empty' | cut -d' ' -f1)
    local asr=$(echo "$times_data" | jq -r '.data.timings.Asr // empty' | cut -d' ' -f1)
    local maghrib=$(echo "$times_data" | jq -r '.data.timings.Maghrib // empty' | cut -d' ' -f1)
    local isha=$(echo "$times_data" | jq -r '.data.timings.Isha // empty' | cut -d' ' -f1)
    
    if [[ -z "$fajr" || -z "$isha" ]]; then
        echo "--:--"
        exit 0
    fi
    
    # Convert all times to minutes
    local fajr_m=$(time_to_minutes "$fajr")
    local sunrise_m=$(time_to_minutes "$sunrise")
    local dhuhr_m=$(time_to_minutes "$dhuhr")
    local asr_m=$(time_to_minutes "$asr")
    local maghrib_m=$(time_to_minutes "$maghrib")
    local isha_m=$(time_to_minutes "$isha")
    local now_m=$(get_current_minutes)
    
    # Determine next prayer
    local next_prayer=""
    local next_time=""
    local time_diff=0
    
    if [[ $now_m -lt $fajr_m ]]; then
        next_prayer="Fajr"
        next_time="$fajr"
        time_diff=$((fajr_m - now_m))
    elif [[ $now_m -lt $sunrise_m ]]; then
        next_prayer="Sunrise"
        next_time="$sunrise"
        time_diff=$((sunrise_m - now_m))
    elif [[ $now_m -lt $dhuhr_m ]]; then
        next_prayer="Dhuhr"
        next_time="$dhuhr"
        time_diff=$((dhuhr_m - now_m))
    elif [[ $now_m -lt $asr_m ]]; then
        next_prayer="Asr"
        next_time="$asr"
        time_diff=$((asr_m - now_m))
    elif [[ $now_m -lt $maghrib_m ]]; then
        next_prayer="Maghrib"
        next_time="$maghrib"
        time_diff=$((maghrib_m - now_m))
    elif [[ $now_m -lt $isha_m ]]; then
        next_prayer="Isha"
        next_time="$isha"
        time_diff=$((isha_m - now_m))
    else
        # After Isha, next prayer is Fajr (tomorrow)
        next_prayer="Fajr"
        next_time="$fajr"
        time_diff=$((1440 - now_m + fajr_m))
    fi
    
    # Format output
    local time_remaining=$(format_time_diff "$time_diff")
    
    if [[ $time_diff -le 5 ]]; then
        # Prayer time is now (within 5 minutes)
        echo "${next_prayer} now"
    else
        echo "${next_prayer} in ${time_remaining}"
    fi
}

main
