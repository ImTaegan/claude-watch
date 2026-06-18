# Token Usage in the Menu Bar — Design

**Date:** 2026-06-18
**Status:** Approved design

## Summary

Surface Claude Code token/quota usage in the menu bar app: a top **summary
bar** with the account-level session (5-hour) and weekly limit gauges, and a
per-agent **context-fill** indicator so you can see at a glance how close you are
to your session limit and which chat is getting heavy.

## Data source (confirmed live)

Claude Code passes a JSON blob on **stdin to the status line script** every
refresh — computed locally from the last API response, no network call. Verified
fields:

```jsonc
{
  "session_id": "...", "cwd": "...",
  "context_window": {
    "total_input_tokens": 351590,
    "context_window_size": 1000000,
    "used_percentage": 35
  },
  "rate_limits": {
    "five_hour": { "used_percentage": 38, "resets_at": 1781798400 },
    "seven_day": { "used_percentage": 5,  "resets_at": 1782378000 }
  },
  "cost": { "total_cost_usd": 39.28 }   // captured but NOT displayed (subscription, not real billing)
}
```

`rate_limits` are account-global (identical across sessions); `context_window`
is per-session. There is no CLI/file for this — the status line is the only
local source, so the capture lives there.

## Non-goals

- No dollar/cost display (it's an API-equivalent estimate, not actual billing on
  a subscription with extra-usage off — would mislead).
- No calls to the undocumented `oauth/usage` API (rate-limited, unreliable).
- No historical graphs; current state only.

## Architecture

```
statusline.sh ──POST /usage──► daemon ── stores global limits + per-session context
hooks         ──POST /event──► daemon ── agent state (unchanged)
                                 └── GET /status ──► menu bar app
```

## Components

### 1. Status line capture (`~/.claude/statusline.sh`)

Add an **additive, backgrounded, best-effort** block (after the existing
`INPUT=$(cat)`), preserving all current behavior (gameboy names, context event,
printed status line). It extracts the usage subset with `jq` and POSTs to the
daemon:

```bash
# claude-watch: report usage (best-effort, never blocks the prompt)
USAGE=$(echo "$INPUT" | jq -c '{
  session_id, cwd, event:"usage",
  context_pct:(.context_window.used_percentage//null),
  context_tokens:(.context_window.total_input_tokens//null),
  context_size:(.context_window.context_window_size//null),
  five_hour_pct:(.rate_limits.five_hour.used_percentage//null),
  five_hour_resets_at:(.rate_limits.five_hour.resets_at//null),
  seven_day_pct:(.rate_limits.seven_day.used_percentage//null),
  seven_day_resets_at:(.rate_limits.seven_day.resets_at//null)
}' 2>/dev/null)
[ -n "$USAGE" ] && (curl -s -m 1 -X POST http://127.0.0.1:7459/usage -d "$USAGE" >/dev/null 2>&1 &)
```

A canonical copy lives at `hooks/statusline.usage.snippet.sh`, and the installer
appends it to `~/.claude/statusline.sh` idempotently (guarded by a marker
comment). README documents it.

### 2. Daemon

- **`SessionRegistry`**: add `_usage` (session_id → `{context_pct,
  context_tokens, context_size, last_seen}`) and `_limits`
  (`{five_hour:{used_percentage,resets_at}, seven_day:{...}, updated_at}`).
  - `update_usage(session_id, now, context_pct, context_tokens, context_size,
    five_hour, seven_day)`: upsert `_usage[session_id]`; set `_limits` when the
    rate-limit fields are present (latest wins).
  - `status(now)`: attach `context_pct`/`context_tokens`/`context_size` to each
    agent from `_usage`; add a top-level `limits` block.
  - `gc(now, idle_timeout)`: also drop stale `_usage` entries.
- **`events.handle_usage_body(registry, raw, now)`**: parse and call
  `update_usage`. Pure (mutates registry), like `handle_event_body`.
- **HTTP**: `do_POST` routes on path — `/usage` → `handle_usage_body`, anything
  else → `handle_event_body` (today's behavior). `/event` stays the event path.
- BLE `aggregate()` is untouched (watch unaffected).

### 3. App

- **DTO** (`ClaudeWatchKit`):
  - `Agent` gains `contextPct: Int?`, `contextTokens: Int?`, `contextSize: Int?`.
  - `StatusPayload` gains `limits: Limits?` where
    `Limits { fiveHour: LimitWindow?, sevenDay: LimitWindow? }`,
    `LimitWindow { usedPercentage: Int, resetsAt: Double }`.
- **UsageSummaryView** (top of panel, above the agent list): two slim gauges.
  - Session (5h): `"Session  38%"` + bar + `"resets in 2h 40m"`.
  - Week: `"Week  5%"` + bar + `"resets in 6d"`.
  - Color by fill: `<70` secondary/green, `70–89` orange, `≥90` red.
  - Hidden entirely when `limits == nil` (no status line data yet).
- **AgentRow**: a compact trailing context pill (e.g. `35%`) when `contextPct`
  is present, tinted by the same thresholds, with a tooltip showing
  `tokens / size`. Sits next to the existing time text.
- Reset countdown formatted from `resetsAt` (unix seconds) → `"resets in Xh Ym"`
  / `"Xd"`; recomputed each poll (already 1 Hz).

## Error handling

- Status line POST: backgrounded, 1s timeout, all errors swallowed; missing
  fields become `null` and are ignored downstream.
- Daemon `/usage`: malformed body → 400 (like `/event`); never affects `/status`.
- App: `limits`/`contextPct` are optional — summary and pill simply don't render
  when absent. No crashes on partial data.

## Testing

- **Daemon (pytest)**: `update_usage` stores context + global limits; `status`
  emits per-agent context + top-level limits; `gc` drops stale usage; `/usage`
  endpoint round-trip; malformed body → 400; BLE `aggregate()` unchanged.
- **Swift**: decode a `/status` payload with `limits` + per-agent context;
  reset-countdown formatter (e.g. 9600s → "2h 40m"); threshold→color mapping.
- **Manual**: drive synthetic `/usage` posts, confirm the bars + pills render and
  color-grade; regenerate the README screenshot via `--snapshot`.

## Files

```
hooks/statusline.usage.snippet.sh      (new; installer appends to ~/.claude/statusline.sh)
hooks/install.sh                        (append snippet idempotently)
daemon/aggregator.py                    (_usage, _limits, update_usage, status, gc)
daemon/events.py                        (handle_usage_body)
daemon/claude_watch_daemon.py           (route POST /usage)
daemon/tests/...                        (new cases)
macapp/Sources/ClaudeWatchKit/StatusDTO.swift   (limits + context fields)
macapp/Sources/ClaudeWatchBar/UsageSummaryView.swift   (new)
macapp/Sources/ClaudeWatchBar/PanelView.swift   (summary + per-row pill)
macapp/Sources/ClaudeWatchBar/Theme.swift       (threshold colors, reset/countdown fmt)
```
