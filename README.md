# red-alert-statusline

A Claude Code statusline that shows real-time [Pikud HaOref](https://www.oref.org.il) (Israel Home Front Command) rocket and missile alerts directly in your Claude session's status bar.

```
🚀 MISSILES · 5 cities · תל אביב - מרכז העיר
⚠️  PRE-ALERT · נתניה · חדרה
✅ ALL CLEAR · רמת גן
```

---

## What it shows

```
🚀 MISSILES · תל אביב - מרכז העיר · רמת גן - מערב
^  ^           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
|  |           Cities affected (≤3 inline; >3 cycles one at a time)
|  Alert category label
Alert icon
```

| Icon | Category | Display duration |
|------|----------|-----------------|
| ⚠️  PRE-ALERT | Category 14 — imminent threat warning | Up to 20 minutes |
| 🚀 MISSILES | Category 1 | 60s after last siren |
| ✈️  HOSTILE AIRCRAFT | Category 2 | 60s after last detection |
| 🌍 EARTHQUAKE | Category 3 | 60s |
| 🌊 TSUNAMI | Category 4 | 60s |
| ☢️  RADIOLOGICAL | Category 5 | 60s |
| ☣️  HAZMAT | Category 6 | 60s |
| 🔫 INFILTRATION | Category 7 | 60s |
| ✅ ALL CLEAR | Category 13 — event concluded | 15s |
| 🔔 DRILL | Categories 101–107 | 60s |
| 🇮🇱 Pikud HaOref: all clear | Fade-out | 10s, then silent |

**City display — no filter set:**

When `RED_ALERT_CITIES` is not set, all cities from the alert are shown using this strategy:

- **3 or fewer cities** — displayed inline, separated by ` · `:
  ```
  🚀 MISSILES · תל אביב - מרכז העיר · רמת גן - מערב
  ```
- **More than 3 cities** — shows the total count and cycles through cities one at a time:
  ```
  🚀 MISSILES · 5 cities · תל אביב          ← one Claude response
  🚀 MISSILES · 5 cities · רמת גן           ← next response, 2s later
  🚀 MISSILES · 5 cities · חולון            ← next response after that
  ```

The cycling is time-based (no background timer needed): the script divides the current
unix timestamp by 2 and takes `% city_count` to pick which city to display. Each time
Claude responds and 2+ seconds have passed, the next city in rotation appears.

**City display — filter set, no match:** the statusline shows nothing, as if there is no alert.

**Pre-alert priority:** Category 14 pre-alerts (early warning before sirens) are shown
first, above any other alert type. If no real alert (cat 1–7) follows within 20 minutes,
the pre-alert expires automatically.

---

## Why it's useful

The official Home Front Command API is a live snapshot — alerts appear on the endpoint
only for the seconds that sirens are sounding, then disappear. This statusline maintains
a 60-second persistence window so you see the alert even after the raw JSON has gone
empty, giving you the full shelter window to act.

---

## Prerequisites

- **bash** 3.2+ (the macOS system bash is fine)
- **curl** (pre-installed on macOS)
- **jq** — install with `brew install jq`

> **Geo-blocking note:** The official `oref.org.il` API may block non-Israeli IP
> addresses (Akamai CDN). If you see no alerts during active events, try running
> the daemon on a server with an Israeli IP (e.g., GCP `me-west1`). The statusline
> script will simply stay silent if the API is unreachable.

---

## Quick start

```bash
# 1. Install jq if you don't have it
brew install jq

# 2. Clone this repo (or it's already your working directory)
git clone https://github.com/lirantal/red-alert-statusline
cd red-alert-statusline

# 3. Install the statusline
jq --arg p "$(pwd)/red-alert.sh" \
   '.statusLine = {"type": "command", "command": $p}' \
   ~/.claude/settings.json > ~/.claude/settings.json.tmp \
   && mv ~/.claude/settings.json.tmp ~/.claude/settings.json

# 4. Restart Claude Code — the daemon starts automatically on first response
```

---

## Manual installation

Add this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/absolute/path/to/red-alert-statusline/red-alert.sh"
  }
}
```

---

## Configuration

All settings are environment variables. Set them in your shell profile or in the
`"env"` block of `~/.claude/settings.json`.

| Variable | Default | Description |
|----------|---------|-------------|
| `RED_ALERT_CITIES` | *(unset)* | Comma-separated city filter (English or Hebrew). If unset, all cities are shown. |
| `RED_ALERT_POLL_INTERVAL` | `2` | Daemon poll frequency in seconds. |

### City filter examples

When `RED_ALERT_CITIES` is set, the statusline is **silent** for alerts that don't
affect your cities, and shows **only the matching cities** from an alert that does.

```bash
# Single city — English name
export RED_ALERT_CITIES="Tel Aviv"

# Multiple cities — comma-separated, no spaces around commas required
export RED_ALERT_CITIES="Tel Aviv,Ramat Gan,Netanya"
export RED_ALERT_CITIES="Tel Aviv, Ramat Gan, Netanya"   # spaces OK, they're trimmed

# Hebrew names — direct substring match against the API's data[] array
export RED_ALERT_CITIES="תל אביב,רמת גן"

# Mixed English and Hebrew
export RED_ALERT_CITIES="Tel Aviv,חיפה,Beer Sheva"

# Zone/area name — matches all cities in that zone if they appear in the alert
export RED_ALERT_CITIES="Gush Dan"   # won't work; use individual city names

# Spelling variants — all of these resolve to the same Hebrew city (באר שבע)
export RED_ALERT_CITIES="Beer Sheva"
export RED_ALERT_CITIES="Beersheba"
export RED_ALERT_CITIES="Beersheva"

# Via ~/.claude/settings.json env block (persists across sessions):
```
```json
{
  "env": {
    "RED_ALERT_CITIES": "Tel Aviv,Ramat Gan,Netanya"
  },
  "statusLine": {
    "type": "command",
    "command": "/path/to/red-alert.sh"
  }
}
```

**Important:** Alert city names from the API include district suffixes in Hebrew, e.g.:
- `"תל אביב - מרכז העיר"` (Tel Aviv - City Center)
- `"תל אביב - דרום העיר"` (Tel Aviv - South)
- `"אשקלון - צפון"` (Ashkelon - North)

Filtering by `"Tel Aviv"` or `"תל אביב"` matches **all Tel Aviv districts** because the
match is substring-based.

**Matching logic (applied in order, first match wins):**
1. **Direct substring** — the filter term appears anywhere in the Hebrew city name
2. **English → Hebrew lookup** — ~70 major cities with common spelling variants are
   pre-mapped; the Hebrew value is then substring-matched
3. **Word-level fuzzy** — each word in your filter (≥3 chars) is individually checked
   against the city name, enabling partial matches

If your city is not in the lookup table, use the Hebrew name directly (copy the `value`
field from `cities.json` in [eladnava/pikud-haoref-api](https://github.com/eladnava/pikud-haoref-api)).

---

## How it works

There are two scripts with distinct jobs:

### `red-alert-daemon.sh` — the poller

Runs permanently in the background. You never interact with it directly — `red-alert.sh`
starts it automatically the first time Claude Code calls the statusline.

What it does every 2 seconds:
1. `curl` the official Pikud HaOref endpoint (`alerts.json`)
2. Strip the UTF-8 BOM and NUL bytes that the API sometimes injects
3. If the response contains a valid JSON alert, parse `cat` (category), `id`, `title`,
   and `data` (the cities array)
4. Update `/tmp/red_alert_state.json` **atomically** (write to a temp file, then `mv`)
   so `red-alert.sh` never reads a half-written file

Key behaviour: when the API returns **empty** (no active siren), the daemon does
**nothing** — it leaves the last state untouched. The display script handles expiry.
This is intentional: the live endpoint is a narrow snapshot that goes empty within
seconds of a siren ending, but the threat window is 60+ seconds.

State file written to `/tmp/red_alert_state.json`:
```json
{
  "alert_id":         "134168709720000000",
  "cat":              "1",
  "title":            "ירי רקטות וטילים",
  "cities":           ["תל אביב - מרכז העיר", "רמת גן - מערב"],
  "last_seen_unix":   1711234567,
  "pre_alert_active": false,
  "pre_alert_time":   0,
  "cleared_unix":     0
}
```

Daemon log: `/tmp/red_alert_daemon.log`

### `red-alert.sh` — the statusline renderer

Called by Claude Code after **every response**. Must return instantly (no network I/O).

What it does:
1. Checks if the daemon is running (by PID file); starts it in the background if not
2. Reads `/tmp/red_alert_state.json` with a single `jq` call
3. Computes how many seconds have passed since each event (`last_seen_unix`,
   `pre_alert_time`, `cleared_unix`)
4. Applies city filtering if `RED_ALERT_CITIES` is set
5. Runs the state machine (pre-alert → all-clear → active → fade-out → silent)
6. Prints the formatted string to stdout; Claude Code displays it in the status bar

```
red-alert.sh (called each response)      red-alert-daemon.sh (always running)
        │                                          │
        │── is daemon running? ──────────────────>│
        │   no → start it in background           │  every 2s:
        │                                         │  curl alerts.json
        │                                         │  parse response
        │<── read /tmp/red_alert_state.json ──────│  write state (atomic mv)
        │
        │   compute event ages
        │   filter cities by RED_ALERT_CITIES
        │   pick state: pre-alert / alert / clear / fade-out / silent
        │   format city list (inline ≤3, cycling >3)
        ▼
  stdout → Claude Code status bar
```

### Alert timing state machine

```
Event detected by daemon
        │
        ▼
  ┌─────────────────────────────────────────────────────────┐
  │ cat=14 (pre-alert)  → show ⚠️  PRE-ALERT for 20 min     │  highest priority
  │                        expires if no cat 1-7 follows    │
  └─────────────────────────────────────────────────────────┘
        │ superseded by real alert or 20 min elapsed
        ▼
  ┌─────────────────────────────────────────────────────────┐
  │ cat=1-7 (active)    → show alert for 60s                │
  │                        even after API goes empty        │
  └─────────────────────────────────────────────────────────┘
        │ cat=13 received
        ▼
  ┌─────────────────────────────────────────────────────────┐
  │ cat=13 (all clear)  → show ✅ ALL CLEAR for 15s         │
  └─────────────────────────────────────────────────────────┘
        │ 15s elapsed (or 60s with no cat=13)
        ▼
  ┌─────────────────────────────────────────────────────────┐
  │ fade-out window     → show 🇮🇱 Pikud HaOref: all clear   │
  └─────────────────────────────────────────────────────────┘
        │ 10s elapsed
        ▼
     silent (statusline shows nothing)
```

---

## Uninstall

```bash
# Remove from settings.json
jq 'del(.statusLine)' ~/.claude/settings.json > ~/.claude/settings.json.tmp \
  && mv ~/.claude/settings.json.tmp ~/.claude/settings.json

# Stop the daemon
kill $(cat /tmp/red_alert_daemon.pid 2>/dev/null) 2>/dev/null || true

# Clean up state files
rm -f /tmp/red_alert_state.json /tmp/red_alert_daemon.pid /tmp/red_alert_daemon.log
```

---

## Troubleshooting

**Statusline shows nothing during an active alert**

- Check if the daemon is running: `cat /tmp/red_alert_daemon.pid && kill -0 $(cat /tmp/red_alert_daemon.pid)`
- Check daemon logs: `tail -20 /tmp/red_alert_daemon.log`
- Test the API directly: `curl -s "https://www.oref.org.il/warningMessages/alert/alerts.json" -H "Referer: https://www.oref.org.il/"`
- If the API returns a 403 or empty response from your IP, you're geo-blocked — the API
  primarily serves Israeli IPs.

**Statusline shows `⚠️  red-alert: jq not found`**

Install jq: `brew install jq`

**Daemon keeps restarting**

Check `/tmp/red_alert_daemon.log` for errors. Common cause: `curl` not in PATH when
launched from a non-interactive shell. Verify: `which curl`.

**City filter not matching**

- Use the Hebrew city name directly for reliable matching.
- Check `cities.json` in [eladnava/pikud-haoref-api](https://github.com/eladnava/pikud-haoref-api)
  to find the exact `value` string used in alerts for your city.
- Alert city names include district suffixes (e.g., `"תל אביב - מרכז העיר"`).
  Filtering by `"תל אביב"` will match all Tel Aviv districts.

**Force a state reset**

```bash
rm -f /tmp/red_alert_state.json /tmp/red_alert_daemon.pid
kill $(cat /tmp/red_alert_daemon.pid 2>/dev/null) 2>/dev/null || true
```
The daemon will restart and re-initialize on the next Claude response.
