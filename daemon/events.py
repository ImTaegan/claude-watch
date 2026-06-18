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
    )
    return registry.aggregate()
