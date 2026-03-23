#!/usr/bin/env bash
# red-alert.sh — Claude Code statusline for Pikud HaOref (Israel Home Front Command) alerts
#
# Displays real-time rocket/missile alerts in your Claude Code status bar.
# Reads from a state file written by red-alert-daemon.sh (auto-started).
#
# Configuration (set in shell profile or ~/.claude/settings.json "env" block):
#   RED_ALERT_CITIES="Tel Aviv,Ramat Gan"   # comma-separated; English or Hebrew
#   RED_ALERT_POLL_INTERVAL=2               # daemon poll frequency in seconds

# ─── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON_SCRIPT="${SCRIPT_DIR}/red-alert-daemon.sh"
STATE_FILE="/tmp/red_alert_state.json"
PID_FILE="/tmp/red_alert_daemon.pid"

# ─── Colors ───────────────────────────────────────────────────────────────────
if [ -n "${TERM:-}" ] && [ "${TERM}" != "dumb" ]; then
    C_RED=$'\033[41;1;37m'        # red bg, bold white  — missiles, pre-alert, infiltration
    C_ORANGE=$'\033[48;2;180;80;0m'$'\033[1;37m'  # dark-orange bg — hostile aircraft
    C_YELLOW=$'\033[43;1;30m'     # yellow bg, bold black — other threats / drills
    C_GREEN=$'\033[32;1m'         # bold green — all clear
    C_RESET=$'\033[0m'
else
    C_RED=""; C_ORANGE=""; C_YELLOW=""; C_GREEN=""; C_RESET=""
fi

# ─── Dependency check ─────────────────────────────────────────────────────────
if ! command -v jq > /dev/null 2>&1; then
    printf '⚠️  red-alert: jq not found (brew install jq)\n'
    exit 0
fi

# ─── Daemon management ────────────────────────────────────────────────────────
is_daemon_running() {
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null) || return 1
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

ensure_daemon_running() {
    is_daemon_running && return 0
    if [ ! -f "$DAEMON_SCRIPT" ]; then
        printf '⚠️  red-alert: daemon script not found: %s\n' "$DAEMON_SCRIPT"
        exit 0
    fi
    nohup bash "$DAEMON_SCRIPT" >> /tmp/red_alert_daemon.log 2>&1 &
    disown
}

# ─── English → Hebrew city lookup ─────────────────────────────────────────────
# Format: "english_normalized|hebrew_value"
# hebrew_value matches the substring that appears in the alert's data[] array.
CITY_LOOKUP=(
    "tel aviv|תל אביב"
    "jerusalem|ירושלים"
    "haifa|חיפה"
    "beer sheva|באר שבע"    "beersheba|באר שבע"    "beersheva|באר שבע"
    "ramat gan|רמת גן"
    "petah tikva|פתח תקווה" "petach tikva|פתח תקווה" "petah tiqva|פתח תקווה"
    "ashdod|אשדוד"
    "ashkelon|אשקלון"
    "netanya|נתניה"          "natanya|נתניה"
    "rishon lezion|ראשון לציון" "rishon le-zion|ראשון לציון" "rishon leziyyon|ראשון לציון"
    "holon|חולון"
    "bat yam|בת ים"
    "bnei brak|בני ברק"     "bene berak|בני ברק"    "bnei berak|בני ברק"
    "herzliya|הרצליה"        "herzlia|הרצליה"
    "kfar saba|כפר סבא"     "kfar-saba|כפר סבא"
    "raanana|רעננה"          "ra'anana|רעננה"        "ra anana|רעננה"
    "modiin|מודיעין"          "modi'in|מודיעין"
    "rehovot|רחובות"          "rehovoth|רחובות"
    "lod|לוד"
    "ramla|רמלה"             "ramle|רמלה"
    "nahariya|נהריה"          "nahariyya|נהריה"
    "tiberias|טבריה"          "tveria|טבריה"
    "nazareth|נצרת"
    "eilat|אילת"             "elat|אילת"
    "kiryat gat|קריית גת"
    "sderot|שדרות"
    "kiryat shmona|קריית שמונה" "kiryat shemona|קריית שמונה"
    "afula|עפולה"
    "acre|עכו"               "akko|עכו"              "akka|עכו"
    "givatayim|גבעתיים"
    "ramat hasharon|רמת השרון"
    "yavne|יבנה"             "yavneh|יבנה"
    "beit shemesh|בית שמש"  "bet shemesh|בית שמש"
    "safed|צפת"              "zfat|צפת"              "tzfat|צפת"
    "hadera|חדרה"
    "kfar yona|כפר יונה"
    "or yehuda|אור יהודה"
    "or akiva|אור עקיבא"
    "nesher|נשר"
    "yokneam|יקנעם"
    "karmiel|כרמיאל"         "carmiel|כרמיאל"
    "dimona|דימונה"
    "arad|ערד"
    "mitzpe ramon|מצפה רמון" "mitzpeh ramon|מצפה רמון"
    "kiryat ata|קריית אתא"
    "kiryat bialik|קריית ביאליק"
    "kiryat motzkin|קריית מוצקין"
    "kiryat yam|קריית ים"
    "tirat carmel|טירת כרמל" "tirat hacarmel|טירת כרמל"
    "pardes hana|פרדס חנה"
    "caesarea|קיסריה"
    "zichron yaakov|זכרון יעקב"
    "givat shmuel|גבעת שמואל"
    "rishon letzion|ראשון לציון"
)

# ─── City matching ────────────────────────────────────────────────────────────
# Returns 0 (match) if alert_city satisfies any term in RED_ALERT_CITIES
city_matches_filter() {
    local alert_city="$1"

    IFS=',' read -ra filter_list <<< "${RED_ALERT_CITIES:-}"

    local filter_entry filter filter_lower
    for filter_entry in "${filter_list[@]}"; do
        # Trim surrounding whitespace
        filter=$(printf '%s' "$filter_entry" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$filter" ] && continue

        filter_lower=$(printf '%s' "$filter" | tr '[:upper:]' '[:lower:]')

        # 1. Direct substring: works for Hebrew input and some English
        if printf '%s' "$alert_city" | grep -qiF "$filter"; then
            return 0
        fi

        # 2. English → Hebrew lookup
        local entry eng heb
        for entry in "${CITY_LOOKUP[@]}"; do
            eng="${entry%%|*}"
            heb="${entry##*|}"
            if [ "$eng" = "$filter_lower" ]; then
                if printf '%s' "$alert_city" | grep -qF "$heb"; then
                    return 0
                fi
            fi
        done

        # 3. Word-level fuzzy: each word in filter checked against city
        local word alert_lower
        alert_lower=$(printf '%s' "$alert_city" | tr '[:upper:]' '[:lower:]')
        for word in $filter_lower; do
            [ "${#word}" -lt 3 ] && continue
            if printf '%s' "$alert_lower" | grep -qiF "$word"; then
                return 0
            fi
        done
    done

    return 1
}

# Emit matching cities from a JSON array, one per line
emit_filtered_cities() {
    local cities_json="$1"
    local has_filter="$2"  # "true" or "false"
    local city

    while IFS= read -r city; do
        [ -z "$city" ] && continue
        if [ "$has_filter" = "true" ]; then
            city_matches_filter "$city" && printf '%s\n' "$city"
        else
            printf '%s\n' "$city"
        fi
    done < <(printf '%s' "$cities_json" | jq -r '.[]' 2>/dev/null)
}

# ─── Category metadata ────────────────────────────────────────────────────────
get_cat_label() {
    case "$1" in
        1)   printf '🚀 MISSILES' ;;
        2)   printf '✈️  HOSTILE AIRCRAFT' ;;
        3)   printf '🌍 EARTHQUAKE' ;;
        4)   printf '🌊 TSUNAMI' ;;
        5)   printf '☢️  RADIOLOGICAL' ;;
        6)   printf '☣️  HAZMAT' ;;
        7)   printf '🔫 INFILTRATION' ;;
        13)  printf '✅ ALL CLEAR' ;;
        14)  printf '⚠️  PRE-ALERT' ;;
        101) printf '🔔 DRILL: MISSILES' ;;
        102) printf '🔔 DRILL: AIRCRAFT' ;;
        103) printf '🔔 DRILL: EARTHQUAKE' ;;
        104) printf '🔔 DRILL: TSUNAMI' ;;
        105) printf '🔔 DRILL: RADIOLOGICAL' ;;
        106) printf '🔔 DRILL: HAZMAT' ;;
        107) printf '🔔 DRILL: INFILTRATION' ;;
        *)   printf '⚠️  ALERT' ;;
    esac
}

get_cat_color() {
    case "$1" in
        1|14)                          printf '%s' "$C_RED" ;;
        2)                             printf '%s' "$C_ORANGE" ;;
        3|4|5|6)                       printf '%s' "$C_YELLOW" ;;
        7)                             printf '%s' "$C_RED" ;;
        13)                            printf '%s' "$C_GREEN" ;;
        101|102|103|104|105|106|107)   printf '%s' "$C_YELLOW" ;;
        *)                             printf '%s' "$C_YELLOW" ;;
    esac
}

# ─── City display ─────────────────────────────────────────────────────────────
# format_cities [city1] [city2] ...
# ≤3 cities → "City A · City B · City C"
# >3 cities → "N cities · <cycling city>"
format_cities() {
    local count=$#
    [ "$count" -eq 0 ] && return

    if [ "$count" -le 3 ]; then
        local out="" city
        for city in "$@"; do
            [ -n "$out" ] && out="${out} · "
            out="${out}${city}"
        done
        printf '%s' "$out"
    else
        # Cycle through cities: one per 2-second window based on wall clock
        local now idx
        now=$(date +%s)
        idx=$(( (now / 2) % count ))
        # Shift to the city at $idx (bash arrays start at 1 for "$@")
        local i=0 cycling_city=""
        for city in "$@"; do
            if [ "$i" -eq "$idx" ]; then
                cycling_city="$city"
                break
            fi
            i=$(( i + 1 ))
        done
        printf '%d cities · %s' "$count" "$cycling_city"
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

# Consume stdin (statusline protocol — Claude passes session JSON on stdin)
SESSION=$(cat)

# Start daemon if not running
ensure_daemon_running

# No state yet (daemon just launched for the first time)
[ ! -f "$STATE_FILE" ] && exit 0

STATE=$(cat "$STATE_FILE" 2>/dev/null)
[ -z "$STATE" ] && exit 0

NOW=$(date +%s)

# Parse all fields in a single jq call for efficiency
eval "$(printf '%s' "$STATE" | jq -r '
    "CAT="           + (.cat          // "" | @sh),
    "CITIES_JSON="   + (.cities       // [] | tojson | @sh),
    "LAST_SEEN="     + (.last_seen_unix    // 0 | tostring),
    "PRE_ALERT_ACTIVE=" + (.pre_alert_active // false | tostring),
    "PRE_ALERT_TIME="+ (.pre_alert_time    // 0 | tostring),
    "CLEARED_UNIX="  + (.cleared_unix      // 0 | tostring)
' 2>/dev/null)" || exit 0

LAST_SEEN_AGE=$(( NOW - LAST_SEEN ))
CLEARED_AGE=$(( NOW - CLEARED_UNIX ))
PRE_ALERT_AGE=$(( NOW - PRE_ALERT_TIME ))

# Determine if city filtering is active
HAS_FILTER="false"
[ -n "${RED_ALERT_CITIES:-}" ] && HAS_FILTER="true"

# Collect filtered cities into an array
FILTERED_CITIES=()
while IFS= read -r city; do
    FILTERED_CITIES+=("$city")
done < <(emit_filtered_cities "$CITIES_JSON" "$HAS_FILTER")

CITY_COUNT=${#FILTERED_CITIES[@]}

# Filter active but zero matches → stay silent
[ "$HAS_FILTER" = "true" ] && [ "$CITY_COUNT" -eq 0 ] && exit 0

# ─── State machine ────────────────────────────────────────────────────────────

# Priority 1: Pre-alert (up to 20 minutes = 1200s)
if [ "$PRE_ALERT_ACTIVE" = "true" ] && [ "$PRE_ALERT_AGE" -lt 1200 ]; then
    COLOR=$(get_cat_color 14)
    CITIES_STR=$(format_cities "${FILTERED_CITIES[@]}")
    if [ -n "$CITIES_STR" ]; then
        printf '%s⚠️  PRE-ALERT · %s%s' "$COLOR" "$CITIES_STR" "$C_RESET"
    else
        printf '%s⚠️  PRE-ALERT%s' "$COLOR" "$C_RESET"
    fi
    exit 0
fi

# Priority 2: All-clear (show for 15 seconds)
if [ "$CAT" = "13" ] && [ "$CLEARED_AGE" -lt 15 ]; then
    CITIES_STR=$(format_cities "${FILTERED_CITIES[@]}")
    if [ -n "$CITIES_STR" ]; then
        printf '%s✅ ALL CLEAR · %s%s' "$C_GREEN" "$CITIES_STR" "$C_RESET"
    else
        printf '%s✅ ALL CLEAR%s' "$C_GREEN" "$C_RESET"
    fi
    exit 0
fi

# Priority 3: Active alert within 60-second persistence window
case "$CAT" in
    1|2|3|4|5|6|7|101|102|103|104|105|106|107)
        if [ "$LAST_SEEN_AGE" -lt 60 ]; then
            COLOR=$(get_cat_color "$CAT")
            LABEL=$(get_cat_label "$CAT")
            CITIES_STR=$(format_cities "${FILTERED_CITIES[@]}")
            if [ -n "$CITIES_STR" ]; then
                printf '%s%s · %s%s' "$COLOR" "$LABEL" "$CITIES_STR" "$C_RESET"
            else
                printf '%s%s%s' "$COLOR" "$LABEL" "$C_RESET"
            fi
            exit 0
        fi
        ;;
esac

# Priority 4: Fade-out window (60–70s after last alert)
case "$CAT" in
    1|2|3|4|5|6|7)
        if [ "$LAST_SEEN_AGE" -ge 60 ] && [ "$LAST_SEEN_AGE" -lt 70 ]; then
            printf '🔕 No active alerts'
            exit 0
        fi
        ;;
esac

# Priority 5: Silent (nothing to show)
exit 0
