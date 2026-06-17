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

    def update(self, session_id, project, event, now):
        if event == "ended":
            self._sessions.pop(session_id, None)
            return
        if event not in EVENT_TO_STATE:
            raise ValueError(f"unknown event: {event}")
        self._sessions[session_id] = {
            "project": project,
            "state": EVENT_TO_STATE[event],
            "last_seen": now,
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

    def gc(self, now, idle_timeout):
        stale = [
            sid for sid, s in self._sessions.items()
            if now - s["last_seen"] > idle_timeout
        ]
        for sid in stale:
            del self._sessions[sid]
        return stale
