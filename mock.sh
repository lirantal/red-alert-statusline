#!/usr/bin/env bash
# mock.sh — demonstrate every visual state of the red-alert statusline
#
# Seeds /tmp/red_alert_state.json with crafted state, calls red-alert.sh,
# and prints the rendered output. No network calls, no real alerts.
#
# Usage:
#   bash mock.sh                    # show all states
#   bash mock.sh missiles           # show only the missiles state
#   bash mock.sh filter "Tel Aviv"  # show filter demo for a specific city

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUSLINE="${SCRIPT_DIR}/red-alert.sh"
STATE_FILE="/tmp/red_alert_state.json"

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Write a state and render the statusline, printing a labelled result
# render <label> <state_json> [city_filter]
render() {
    local label="$1"
    local state_json="$2"
    local city_filter="${3:-}"   # optional: value for RED_ALERT_CITIES

    printf '%s' "$state_json" > "$STATE_FILE"

    local raw
    if [ -n "$city_filter" ]; then
        # Use a subshell with explicit export to handle spaces in city names
        raw=$(bash -c 'export RED_ALERT_CITIES="$1"; bash "$2" <<< "{}"' \
              -- "$city_filter" "$STATUSLINE" 2>/dev/null) || raw=""
    else
        raw=$(bash "$STATUSLINE" <<< '{}' 2>/dev/null) || raw=""
    fi

    # Strip ANSI escape codes for plain display
    local clean
    clean=$(printf '%s' "$raw" | sed $'s/\033\\[[0-9;]*m//g')

    printf '%-42s  %s\n' "[$label]" "${clean:-(silent — nothing shown)}"
}

NOW=$(date +%s)
RECENT=$NOW
AGE_65=$(( NOW - 65 ))   # in fade-out window
AGE_90=$(( NOW - 90 ))   # expired (silent)
AGE_20=$(( NOW - 20 ))   # 20s ago — still fresh

# ─── State templates ──────────────────────────────────────────────────────────

state_missiles_2cities() {
    printf '{"alert_id":"100","cat":"1","title":"ירי רקטות וטילים","cities":["תל אביב - מרכז העיר","רמת גן - מערב"],"last_seen_unix":%d,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":0}' "$RECENT"
}

state_missiles_5cities() {
    printf '{"alert_id":"101","cat":"1","title":"ירי רקטות וטילים","cities":["תל אביב","רמת גן","חולון","בת ים","גבעתיים"],"last_seen_unix":%d,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":0}' "$RECENT"
}

state_prealert() {
    printf '{"alert_id":"","cat":"14","title":"בדקות הקרובות צפויות להתקבל התרעות","cities":["נתניה","חדרה","זכרון יעקב"],"last_seen_unix":%d,"pre_alert_active":true,"pre_alert_time":%d,"cleared_unix":0}' "$RECENT" "$AGE_20"
}

state_aircraft() {
    printf '{"alert_id":"102","cat":"2","title":"חדירת כלי טיס עוין","cities":["הגליל העליון"],"last_seen_unix":%d,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":0}' "$RECENT"
}

state_earthquake() {
    printf '{"alert_id":"103","cat":"3","title":"רעידת אדמה","cities":["ירושלים","בית שמש"],"last_seen_unix":%d,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":0}' "$RECENT"
}

state_tsunami() {
    printf '{"alert_id":"104","cat":"4","title":"צונאמי","cities":["אשדוד","אשקלון - צפון","אשקלון - דרום"],"last_seen_unix":%d,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":0}' "$RECENT"
}

state_hazmat() {
    printf '{"alert_id":"105","cat":"6","title":"חומרים מסוכנים","cities":["חיפה - כרמל"],"last_seen_unix":%d,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":0}' "$RECENT"
}

state_infiltration() {
    printf '{"alert_id":"106","cat":"7","title":"חדירת מחבלים","cities":["שדרות","נתיבות"],"last_seen_unix":%d,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":0}' "$RECENT"
}

state_allclear() {
    printf '{"alert_id":"100","cat":"13","title":"האירוע הסתיים","cities":["תל אביב - מרכז העיר"],"last_seen_unix":%d,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":%d}' "$RECENT" "$RECENT"
}

state_fadeout() {
    printf '{"alert_id":"100","cat":"1","title":"ירי רקטות וטילים","cities":["תל אביב"],"last_seen_unix":%d,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":0}' "$AGE_65"
}

state_silent() {
    printf '{"alert_id":"100","cat":"1","title":"ירי רקטות וטילים","cities":["תל אביב"],"last_seen_unix":%d,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":0}' "$AGE_90"
}

state_drill() {
    printf '{"alert_id":"200","cat":"101","title":"תרגיל - ירי רקטות","cities":["ירושלים","מודיעין"],"last_seen_unix":%d,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":0}' "$RECENT"
}

state_missiles_filter_match() {
    # Alert covers Tel Aviv and Ashkelon; filter is "Tel Aviv" — only Tel Aviv shown
    printf '{"alert_id":"107","cat":"1","title":"ירי רקטות וטילים","cities":["תל אביב - מרכז העיר","אשקלון - צפון","אשקלון - דרום"],"last_seen_unix":%d,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":0}' "$RECENT"
}

state_missiles_filter_nomatch() {
    # Alert covers Ashkelon only; filter is "Tel Aviv" — silent
    printf '{"alert_id":"108","cat":"1","title":"ירי רקטות וטילים","cities":["אשקלון - צפון","אשקלון - דרום"],"last_seen_unix":%d,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":0}' "$RECENT"
}

# ─── Run selected demo or all ─────────────────────────────────────────────────

run_all() {
    echo ""
    echo "red-alert-statusline — visual state demo"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "── Alert types ─────────────────────────────────────────────────"
    render "pre-alert (cat 14)"          "$(state_prealert)"
    render "missiles (cat 1, 2 cities)"  "$(state_missiles_2cities)"
    render "missiles (cat 1, 5 cities)"  "$(state_missiles_5cities)"
    render "hostile aircraft (cat 2)"    "$(state_aircraft)"
    render "earthquake (cat 3)"          "$(state_earthquake)"
    render "tsunami (cat 4)"             "$(state_tsunami)"
    render "hazmat (cat 6)"              "$(state_hazmat)"
    render "infiltration (cat 7)"        "$(state_infiltration)"
    render "drill (cat 101)"             "$(state_drill)"
    echo ""
    echo "── Alert lifecycle ─────────────────────────────────────────────"
    render "alert active (0-60s)"        "$(state_missiles_2cities)"
    render "all clear (cat 13, <15s)"    "$(state_allclear)"
    render "fade-out (60-70s elapsed)"   "$(state_fadeout)"
    render "silent (>70s elapsed)"       "$(state_silent)"
    echo ""
    echo "── City filtering (RED_ALERT_CITIES) ───────────────────────────"
    render "no filter → all cities"                     "$(state_missiles_filter_match)"
    render "filter='Tel Aviv' → match"                  "$(state_missiles_filter_match)"   "Tel Aviv"
    render "filter='Tel Aviv' → no match (silent)"      "$(state_missiles_filter_nomatch)" "Tel Aviv"
    render "filter='תל אביב' → Hebrew match"            "$(state_missiles_filter_match)"   "תל אביב"
    render "filter='Tel Aviv,Ashkelon' → both cities"   "$(state_missiles_filter_match)"   "Tel Aviv,Ashkelon"
    render "filter='Eilat' → silent (not in alert)"     "$(state_missiles_filter_match)"   "Eilat"
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "Note: colors not shown above — run the statusline inside Claude"
    echo "Code to see ANSI colors (red bg for missiles, yellow for others)."
    echo ""
}

run_single() {
    local name="$1"
    case "$name" in
        missiles|missile)       render "missiles (2 cities)" "$(state_missiles_2cities)" ;;
        missiles5|many)         render "missiles (5 cities)" "$(state_missiles_5cities)" ;;
        prealert|pre|pre-alert) render "pre-alert"           "$(state_prealert)" ;;
        aircraft)               render "hostile aircraft"     "$(state_aircraft)" ;;
        earthquake)             render "earthquake"           "$(state_earthquake)" ;;
        tsunami)                render "tsunami"              "$(state_tsunami)" ;;
        hazmat)                 render "hazmat"               "$(state_hazmat)" ;;
        infiltration)           render "infiltration"         "$(state_infiltration)" ;;
        allclear|clear)         render "all clear"            "$(state_allclear)" ;;
        fadeout|fade)           render "fade-out"             "$(state_fadeout)" ;;
        silent)                 render "silent"               "$(state_silent)" ;;
        drill)                  render "drill"                "$(state_drill)" ;;
        *)
            printf 'Unknown state: %s\n' "$name"
            printf 'Valid states: missiles missiles5 prealert aircraft earthquake tsunami hazmat infiltration allclear fadeout silent drill\n'
            exit 1
            ;;
    esac
}

run_filter_demo() {
    local city="${1:-Tel Aviv}"
    echo ""
    printf 'Filter demo: RED_ALERT_CITIES="%s"\n' "$city"
    echo "────────────────────────────────────────────────────────────────"
    printf '%s' "$(state_missiles_filter_match)" > "$STATE_FILE"
    printf '  Alert cities in state: תל אביב - מרכז העיר, אשקלון - צפון, אשקלון - דרום\n'
    local raw
    raw=$(bash -c 'export RED_ALERT_CITIES="$1"; bash "$2" <<< "{}"' \
          -- "$city" "$STATUSLINE" 2>/dev/null) || raw=""
    local clean
    clean=$(printf '%s' "$raw" | sed $'s/\033\\[[0-9;]*m//g')
    printf '  Statusline output: %s\n\n' "${clean:-(silent — no match)}"
}

# ─── Entrypoint ───────────────────────────────────────────────────────────────

case "${1:-all}" in
    all)    run_all ;;
    filter) run_filter_demo "${2:-Tel Aviv}" ;;
    *)      run_single "$1" ;;
esac
