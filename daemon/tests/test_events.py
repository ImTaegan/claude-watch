import json
from aggregator import SessionRegistry, RUNNING
from events import handle_event_body, project_from_cwd

def test_handle_event_body_passes_optional_fields():
    r = SessionRegistry()
    raw = json.dumps({
        "session_id": "s1", "event": "running", "cwd": "/x/proj",
        "tool": "Edit", "term": "iTerm.app", "tty": "/dev/ttys003",
    })
    handle_event_body(r, raw, now=5.0)
    a = r.status(now=5.0)["agents"][0]
    assert a["tool"] == "Edit"
    assert a["term"] == "iTerm.app"
    assert a["tty"] == "/dev/ttys003"
    assert a["cwd"] == "/x/proj"


def test_project_from_cwd():
    assert project_from_cwd("/Users/me/Websites/claude-watchh") == "claude-watchh"
    assert project_from_cwd("/Users/me/Websites/claude-watchh/") == "claude-watchh"
    assert project_from_cwd("") == "?"

def test_handle_event_body_updates_and_returns_aggregate():
    r = SessionRegistry()
    raw = json.dumps({
        "session_id": "s1",
        "event": "running",
        "cwd": "/Users/me/proj-x",
    }).encode()
    agg = handle_event_body(r, raw, now=10.0)
    assert agg["r"] == 1
    assert agg["top"] == "proj-x"
    assert r._sessions["s1"]["state"] == RUNNING

def test_handle_event_body_explicit_project_wins():
    r = SessionRegistry()
    raw = json.dumps({"session_id": "s1", "event": "done",
                      "cwd": "/a/b", "project": "override"}).encode()
    agg = handle_event_body(r, raw, now=1.0)
    assert agg["top"] == "override"
