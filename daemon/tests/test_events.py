import json
from aggregator import SessionRegistry, RUNNING
from events import handle_event_body, handle_usage_body, project_from_cwd

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


def test_handle_usage_body_stores_context_and_limits():
    r = SessionRegistry()
    r.update("s1", "projA", "running", now=1.0)
    raw = json.dumps({
        "session_id": "s1", "cwd": "/x/projA",
        "context_pct": 35, "context_tokens": 351590, "context_size": 1000000,
        "five_hour_pct": 38, "five_hour_resets_at": 1781798400,
        "seven_day_pct": 5, "seven_day_resets_at": 1782378000,
    })
    handle_usage_body(r, raw, now=2.0)
    st = r.status(now=2.0)
    assert st["agents"][0]["context_pct"] == 35
    assert st["limits"]["five_hour"]["used_percentage"] == 38
    assert st["limits"]["five_hour"]["resets_at"] == 1781798400
    assert st["limits"]["seven_day"]["used_percentage"] == 5


def test_handle_usage_body_rounds_fractional_percentages():
    r = SessionRegistry()
    r.update("s1", "p", "running", now=1.0)
    raw = json.dumps({
        "session_id": "s1", "context_pct": 54.0,
        "five_hour_pct": 7.000000000000001, "five_hour_resets_at": 100,
        "seven_day_pct": 6, "seven_day_resets_at": 200,
    })
    handle_usage_body(r, raw, now=2.0)
    st = r.status(now=2.0)
    assert st["agents"][0]["context_pct"] == 54
    assert st["limits"]["five_hour"]["used_percentage"] == 7  # int, not 7.0000…
    assert isinstance(st["limits"]["five_hour"]["used_percentage"], int)


def test_handle_usage_body_without_limits_leaves_them_none():
    r = SessionRegistry()
    r.update("s1", "p", "running", now=1.0)
    handle_usage_body(r, json.dumps({"session_id": "s1", "context_pct": 12}), now=2.0)
    st = r.status(now=2.0)
    assert st["agents"][0]["context_pct"] == 12
    assert st["limits"] is None


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
