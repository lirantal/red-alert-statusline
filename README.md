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
| 🔕 No active alerts | Fade-out | 10s, then silent |

**City cycling:** When more than 3 cities are affected, the statusline shows the count
and cycles through the city names every 2 seconds as Claude responds.

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

```bash
# English names (fuzzy-matched against Hebrew city database)
export RED_ALERT_CITIES="Tel Aviv,Ramat Gan"

# Hebrew names (direct substring match)
export RED_ALERT_CITIES="תל אביב,רמת גן"

# Mixed
export RED_ALERT_CITIES="Tel Aviv,חיפה"

# Via settings.json env block:
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

**Matching logic:**
1. Direct substring match (Hebrew input, or English that happens to appear in the city name)
2. English → Hebrew lookup via a bundled table of ~70 major cities
3. Word-level fuzzy: each word in your filter is checked against the city name

If your city is not in the lookup table, use the Hebrew name directly (copy it from
`cities.json` in [eladnava/pikud-haoref-api](https://github.com/eladnava/pikud-haoref-api)).

---

## How it works

```
red-alert.sh          red-alert-daemon.sh
     │                        │
     │  ensure running ──────>│  loop every 2s:
     │                        │    curl oref.org.il/alerts.json
     │                        │    parse cat/id/cities
     │  read state ◄──────────│    write /tmp/red_alert_state.json (atomic)
     │                        │
     │  apply timing rules
     │  filter cities
     │  format output
     ▼
  statusline string → Claude Code status bar
```

- `red-alert-daemon.sh` runs in the background (auto-started), polls every 2 seconds,
  and writes state atomically to `/tmp/red_alert_state.json`.
- `red-alert.sh` is called by Claude Code after every response. It reads the state
  file and renders the appropriate display string instantly (no network call).
- Daemon logs go to `/tmp/red_alert_daemon.log`.

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
