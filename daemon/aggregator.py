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
