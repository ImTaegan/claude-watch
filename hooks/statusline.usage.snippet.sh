# >>> claude-watch usage >>>
# Reports token/quota usage to the Claude Watcher daemon. Best-effort, runs in
# the background, never blocks the prompt. Assumes the status line script
# captured its stdin JSON into $INPUT (Claude Code passes it once on stdin).
if command -v jq >/dev/null 2>&1; then
  _CW_USAGE=$(printf '%s' "$INPUT" | jq -c '{
    session_id, cwd, event:"usage",
    context_pct:(.context_window.used_percentage//null),
    context_tokens:(.context_window.total_input_tokens//null),
    context_size:(.context_window.context_window_size//null),
    five_hour_pct:(.rate_limits.five_hour.used_percentage//null),
    five_hour_resets_at:(.rate_limits.five_hour.resets_at//null),
    seven_day_pct:(.rate_limits.seven_day.used_percentage//null),
    seven_day_resets_at:(.rate_limits.seven_day.resets_at//null)
  }' 2>/dev/null)
  [ -n "$_CW_USAGE" ] && (curl -s -m 1 -X POST http://127.0.0.1:7459/usage -d "$_CW_USAGE" >/dev/null 2>&1 &)
fi
# <<< claude-watch usage <<<
