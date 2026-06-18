"""HTTP event-body parsing. Pure (mutates the passed registry); no IO/BLE."""
import json
import os


def project_from_cwd(cwd):
    base = os.path.basename((cwd or "").rstrip("/"))
    return base or "?"


def handle_event_body(registry, raw, now):
    data = json.loads(raw)
    session_id = data["session_id"]
    event = data["event"]
    project = data.get("project") or project_from_cwd(data.get("cwd", ""))
    registry.update(
        session_id, project, event, now,
        tool=data.get("tool"),
        term=data.get("term"),
        tty=data.get("tty"),
        cwd=data.get("cwd"),
    )
    return registry.aggregate()


def _window(data, prefix):
    pct = data.get(f"{prefix}_pct")
    if pct is None:
        return None
    return {"used_percentage": pct, "resets_at": data.get(f"{prefix}_resets_at")}


def handle_usage_body(registry, raw, now):
    """Status-line usage report: per-session context + account rate limits."""
    data = json.loads(raw)
    registry.update_usage(
        data["session_id"], now,
        context_pct=data.get("context_pct"),
        context_tokens=data.get("context_tokens"),
        context_size=data.get("context_size"),
        five_hour=_window(data, "five_hour"),
        seven_day=_window(data, "seven_day"),
    )
