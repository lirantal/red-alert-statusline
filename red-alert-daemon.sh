#!/usr/bin/env bash
# red-alert-daemon.sh — Pikud HaOref alert background poller
# Polls the Israeli Home Front Command API every 2 seconds and writes state to disk.
# Launched automatically by red-alert.sh; do not run directly.

STATE_FILE="/tmp/red_alert_state.json"
STATE_TMP="/tmp/red_alert_state.$$.tmp"
PID_FILE="/tmp/red_alert_daemon.pid"
LOG_FILE="/tmp/red_alert_daemon.log"
POLL_INTERVAL="${RED_ALERT_POLL_INTERVAL:-2}"
API_URL="https://www.oref.org.il/warningMessages/alert/alerts.json"

echo $$ > "$PID_FILE"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

cleanup() {
    rm -f "$PID_FILE" "$STATE_TMP"
    log "Daemon stopped (PID $$)"
}
trap cleanup EXIT

# Initialize state if missing
if [ ! -f "$STATE_FILE" ]; then
    printf '{"alert_id":"","cat":"","title":"","cities":[],"last_seen_unix":0,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":0}\n' \
        > "$STATE_FILE"
fi

log "Daemon started (PID $$, poll interval=${POLL_INTERVAL}s)"

while true; do
    NOW=$(date +%s)

    # Fetch — add cache-buster timestamp to URL
    RESPONSE=$(curl -sf \
        --max-time 4 \
        -H "Referer: https://www.oref.org.il/" \
        -H "X-Requested-With: XMLHttpRequest" \
        -H "Cache-Control: max-age=0" \
        -H "Pragma: no-cache" \
        -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
        "${API_URL}?${NOW}" 2>/dev/null) || RESPONSE=""

    # Strip UTF-8 BOM (\xef\xbb\xbf) and NUL bytes
    RESPONSE=$(printf '%s' "$RESPONSE" | LC_ALL=C sed 's/^\xef\xbb\xbf//' | tr -d '\000')

    # Only process non-empty, non-trivial responses with a .data field
    RESPONSE_CLEAN=$(printf '%s' "$RESPONSE" | tr -d '[:space:]')
    if [ -n "$RESPONSE_CLEAN" ] && [ "$RESPONSE_CLEAN" != "[]" ] && [ "$RESPONSE_CLEAN" != "{}" ]; then
        if echo "$RESPONSE" | jq -e '.data' > /dev/null 2>&1; then
            CAT=$(echo "$RESPONSE" | jq -r '.cat // ""')
            ALERT_ID=$(echo "$RESPONSE" | jq -r '.id // ""')
            TITLE=$(echo "$RESPONSE" | jq -r '.title // ""')
            # Clean cities: trim whitespace, drop empty/null entries
            CITIES_JSON=$(echo "$RESPONSE" | jq -c \
                '[.data[] | select(. != null and . != "") | gsub("^\\s+|\\s+$"; "")]' 2>/dev/null) \
                || CITIES_JSON='[]'

            # Read current state (or use safe default)
            CURRENT_STATE=$(cat "$STATE_FILE" 2>/dev/null) \
                || CURRENT_STATE='{"alert_id":"","cat":"","title":"","cities":[],"last_seen_unix":0,"pre_alert_active":false,"pre_alert_time":0,"cleared_unix":0}'

            case "$CAT" in
                13)
                    # All-clear event
                    log "All-clear (cat 13) for: $(echo "$CITIES_JSON" | jq -r 'join(", ")' 2>/dev/null)"
                    NEW_STATE=$(echo "$CURRENT_STATE" | jq \
                        --argjson now "$NOW" \
                        --arg cat "$CAT" \
                        --arg title "$TITLE" \
                        --argjson cities "$CITIES_JSON" \
                        '.cleared_unix=$now | .cat=$cat | .title=$title | .cities=$cities
                         | .pre_alert_active=false') || NEW_STATE="$CURRENT_STATE"
                    ;;
                14)
                    # Pre-alert — preserve original start time if already active
                    CURRENT_PRE=$(echo "$CURRENT_STATE" | jq -r '.pre_alert_active // false' 2>/dev/null) || CURRENT_PRE="false"
                    if [ "$CURRENT_PRE" = "true" ]; then
                        PRE_TIME=$(echo "$CURRENT_STATE" | jq -r '.pre_alert_time // 0' 2>/dev/null) || PRE_TIME="$NOW"
                    else
                        PRE_TIME="$NOW"
                        log "Pre-alert (cat 14) started for: $(echo "$CITIES_JSON" | jq -r 'join(", ")' 2>/dev/null)"
                    fi
                    NEW_STATE=$(echo "$CURRENT_STATE" | jq \
                        --argjson now "$NOW" \
                        --argjson pre_time "$PRE_TIME" \
                        --arg cat "$CAT" \
                        --arg title "$TITLE" \
                        --argjson cities "$CITIES_JSON" \
                        '.pre_alert_active=true | .pre_alert_time=$pre_time | .cat=$cat
                         | .title=$title | .cities=$cities | .last_seen_unix=$now
                         | .cleared_unix=0') || NEW_STATE="$CURRENT_STATE"
                    ;;
                "")
                    # Empty cat — skip
                    ;;
                *)
                    # Active alert: cat 1–12, 101–107
                    log "Alert cat=$CAT id=$ALERT_ID for: $(echo "$CITIES_JSON" | jq -r 'join(", ")' 2>/dev/null)"
                    NEW_STATE=$(echo "$CURRENT_STATE" | jq \
                        --argjson now "$NOW" \
                        --arg cat "$CAT" \
                        --arg alert_id "$ALERT_ID" \
                        --arg title "$TITLE" \
                        --argjson cities "$CITIES_JSON" \
                        '.alert_id=$alert_id | .cat=$cat | .title=$title | .cities=$cities
                         | .last_seen_unix=$now | .pre_alert_active=false | .cleared_unix=0') \
                        || NEW_STATE="$CURRENT_STATE"
                    ;;
            esac

            # Atomic write: write to tmp, then rename
            if [ -n "${NEW_STATE:-}" ]; then
                printf '%s\n' "$NEW_STATE" > "$STATE_TMP" && mv "$STATE_TMP" "$STATE_FILE"
            fi
        fi
    fi

    sleep "$POLL_INTERVAL"
done
