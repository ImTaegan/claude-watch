"""Pure session-state aggregation. No async, no IO, no BLE — unit-testable."""

IDLE = 0
RUNNING = 1
DONE = 2
NEEDS_INPUT = 3

EVENT_TO_STATE = {
    "idle": IDLE,
    "running": RUNNING,
    "done": DONE,
    "needs_input": NEEDS_INPUT,
}


class SessionRegistry:
    def __init__(self):
        # session_id -> {"project": str, "state": int, "last_seen": float}
        self._sessions = {}
        # session_id -> {context_pct, context_tokens, context_size, last_seen}
        self._usage = {}
        # account-global rate limits (latest status-line report wins), or None
        self._limits = None
        # (timestamp, session_pct) samples for the current 5h window, for ETA
        self._sess_samples = []
        self._sess_window = None  # resets_at of the window the samples belong to

    def update(self, session_id, project, event, now,
               tool=None, term=None, tty=None, cwd=None):
        if event == "ended":
            self._sessions.pop(session_id, None)
            return
        if event not in EVENT_TO_STATE:
            raise ValueError(f"unknown event: {event}")
        state = EVENT_TO_STATE[event]
        prev = self._sessions.get(session_id)

        # waiting_since marks when the agent first started needing input;
        # it persists while still waiting and clears once it moves on.
        if state == NEEDS_INPUT:
            waiting_since = (prev.get("waiting_since")
                             if prev and prev.get("waiting_since") else now)
        else:
            waiting_since = None

        def keep(field, value):
            return value if value is not None else (prev.get(field) if prev else None)

        self._sessions[session_id] = {
            "project": project,
            "state": state,
            "last_seen": now,
            "tool": keep("tool", tool),
            "term": keep("term", term),
            "tty": keep("tty", tty),
            "cwd": keep("cwd", cwd),
            "waiting_since": waiting_since,
        }

    def aggregate(self, max_sessions=5):
        counts = {IDLE: 0, RUNNING: 0, DONE: 0, NEEDS_INPUT: 0}
        for s in self._sessions.values():
            counts[s["state"]] += 1
        ordered = sorted(
            self._sessions.values(),
            key=lambda s: (s["state"], s["last_seen"]),
            reverse=True,
        )
        top = ordered[0]["project"] if ordered else ""
        return {
            "u": counts[NEEDS_INPUT],
            "r": counts[RUNNING],
            "d": counts[DONE],
            "i": counts[IDLE],
            "top": top,
            "sessions": [
                {"project": s["project"], "state": s["state"]}
                for s in ordered[:max_sessions]
            ],
        }

    def update_usage(self, session_id, now, context_pct=None,
                     context_tokens=None, context_size=None,
                     five_hour=None, seven_day=None):
        # Context trend: compare against the previous reading for this session.
        prev = self._usage.get(session_id, {}).get("context_pct")
        trend = None
        if prev is not None and context_pct is not None:
            trend = "up" if context_pct > prev else "down" if context_pct < prev else "flat"
        self._usage[session_id] = {
            "context_pct": context_pct,
            "context_tokens": context_tokens,
            "context_size": context_size,
            "context_trend": trend,
            "last_seen": now,
        }
        # Rate limits are account-global; the most recent report wins.
        if five_hour or seven_day:
            self._limits = {
                "five_hour": five_hour,
                "seven_day": seven_day,
                "updated_at": now,
            }
        # Track 5h-window % samples for the burn-rate ETA, scoped to the
        # current window (reset when the window rolls over).
        if five_hour and five_hour.get("used_percentage") is not None:
            ra = five_hour.get("resets_at")
            if ra != self._sess_window:
                self._sess_window = ra
                self._sess_samples = []
            self._sess_samples.append((now, five_hour["used_percentage"]))
            cutoff = now - 1800  # keep last 30 min
            self._sess_samples = [(t, p) for t, p in self._sess_samples if t >= cutoff]

    def _session_eta(self, now):
        """Seconds until the 5h window hits 100% at the recent rate, or None."""
        s = self._sess_samples
        if len(s) < 2:
            return None
        (t0, p0), (t1, p1) = s[0], s[-1]
        span = t1 - t0
        if span < 120:           # need a couple minutes of signal
            return None
        rate = (p1 - p0) / span  # %/sec
        if rate <= 0 or p1 >= 100:
            return None
        return round((100 - p1) / rate)

    def status(self, now):
        counts = {IDLE: 0, RUNNING: 0, DONE: 0, NEEDS_INPUT: 0}
        for s in self._sessions.values():
            counts[s["state"]] += 1
        ordered = sorted(
            self._sessions.items(),
            key=lambda kv: (kv[1]["state"], kv[1]["last_seen"]),
            reverse=True,
        )
        limits = self._limits
        if limits and limits.get("five_hour"):
            limits = dict(limits)
            fh = dict(limits["five_hour"])
            fh["eta_seconds"] = self._session_eta(now)
            limits["five_hour"] = fh

        return {
            "counts": {
                "needs_input": counts[NEEDS_INPUT],
                "running": counts[RUNNING],
                "done": counts[DONE],
                "idle": counts[IDLE],
            },
            "limits": limits,
            "agents": [
                {
                    "id": sid,
                    "project": s["project"],
                    "state": s["state"],
                    "age_seconds": round(now - s["last_seen"], 1),
                    "tool": s.get("tool"),
                    "term": s.get("term"),
                    "tty": s.get("tty"),
                    "cwd": s.get("cwd"),
                    "waiting_seconds": (round(now - s["waiting_since"], 1)
                                        if s.get("waiting_since") else None),
                    "context_pct": self._usage.get(sid, {}).get("context_pct"),
                    "context_tokens": self._usage.get(sid, {}).get("context_tokens"),
                    "context_size": self._usage.get(sid, {}).get("context_size"),
                    "context_trend": self._usage.get(sid, {}).get("context_trend"),
                }
                for sid, s in ordered
            ],
        }

    def gc(self, now, idle_timeout):
        stale = [
            sid for sid, s in self._sessions.items()
            if now - s["last_seen"] > idle_timeout
        ]
        for sid in stale:
            del self._sessions[sid]
        stale_usage = [
            sid for sid, u in self._usage.items()
            if now - u["last_seen"] > idle_timeout
        ]
        for sid in stale_usage:
            del self._usage[sid]
        return stale
