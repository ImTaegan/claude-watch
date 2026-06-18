from aggregator import SessionRegistry, RUNNING, NEEDS_INPUT, DONE

def test_update_sets_state_and_removes_on_ended():
    r = SessionRegistry()
    r.update("s1", "projA", "running", now=100.0)
    assert r._sessions["s1"]["state"] == RUNNING
    assert r._sessions["s1"]["project"] == "projA"
    assert r._sessions["s1"]["last_seen"] == 100.0

    r.update("s1", "projA", "needs_input", now=101.0)
    assert r._sessions["s1"]["state"] == NEEDS_INPUT
    assert r._sessions["s1"]["last_seen"] == 101.0

    r.update("s1", "projA", "ended", now=102.0)
    assert "s1" not in r._sessions

def test_aggregate_counts_top_and_order():
    r = SessionRegistry()
    r.update("a", "projA", "running", now=1.0)
    r.update("b", "projB", "running", now=2.0)
    r.update("c", "projC", "needs_input", now=3.0)
    r.update("d", "projD", "done", now=4.0)

    agg = r.aggregate()
    assert agg["u"] == 1
    assert agg["r"] == 2
    assert agg["d"] == 1
    assert agg["i"] == 0
    # most urgent is needs_input -> projC
    assert agg["top"] == "projC"
    # first session entry is the most urgent
    assert agg["sessions"][0] == {"project": "projC", "state": NEEDS_INPUT}
    # done outranks running
    assert agg["sessions"][1] == {"project": "projD", "state": DONE}

def test_aggregate_empty():
    r = SessionRegistry()
    agg = r.aggregate()
    assert agg == {"u": 0, "r": 0, "d": 0, "i": 0, "top": "", "sessions": []}

def test_aggregate_truncates_to_max():
    r = SessionRegistry()
    for n in range(8):
        r.update(f"s{n}", f"p{n}", "running", now=float(n))
    agg = r.aggregate(max_sessions=5)
    assert len(agg["sessions"]) == 5
    # most recent running first (last_seen desc within same state)
    assert agg["sessions"][0]["project"] == "p7"

def test_status_counts_and_order():
    r = SessionRegistry()
    r.update("s1", "projA", "running", now=100.0)
    r.update("s2", "projB", "needs_input", now=101.0)
    st = r.status(now=105.0)
    assert st["counts"] == {"needs_input": 1, "running": 1, "done": 0, "idle": 0}
    assert [a["project"] for a in st["agents"]] == ["projB", "projA"]
    assert st["agents"][0]["id"] == "s2"
    assert st["agents"][0]["state"] == 3
    assert st["agents"][0]["age_seconds"] == 4.0
    assert st["agents"][1]["age_seconds"] == 5.0


def test_status_empty():
    st = SessionRegistry().status(now=1.0)
    assert st["agents"] == []
    assert st["counts"] == {"needs_input": 0, "running": 0, "done": 0, "idle": 0}


def test_status_includes_tool_term_tty_and_waiting():
    r = SessionRegistry()
    r.update("s1", "projA", "running", now=100.0,
             tool="Edit", term="iTerm.app", tty="/dev/ttys003")
    st = r.status(now=102.0)
    a = st["agents"][0]
    assert a["tool"] == "Edit"
    assert a["term"] == "iTerm.app"
    assert a["tty"] == "/dev/ttys003"
    assert a["waiting_seconds"] is None


def test_waiting_seconds_tracks_start_and_clears():
    r = SessionRegistry()
    r.update("s1", "p", "needs_input", now=10.0)
    r.update("s1", "p", "needs_input", now=15.0)  # still waiting, keep original start
    assert r.status(now=20.0)["agents"][0]["waiting_seconds"] == 10.0
    r.update("s1", "p", "running", now=21.0)       # left needs_input
    assert r.status(now=22.0)["agents"][0]["waiting_seconds"] is None


def test_update_preserves_term_tty_tool_when_not_resent():
    r = SessionRegistry()
    r.update("s1", "p", "running", now=1.0,
             tool="Bash", term="iTerm.app", tty="/dev/ttys1")
    r.update("s1", "p", "needs_input", now=2.0)  # no extras passed
    a = r.status(now=2.0)["agents"][0]
    assert a["term"] == "iTerm.app"
    assert a["tty"] == "/dev/ttys1"
    assert a["tool"] == "Bash"


def test_update_usage_and_status_limits():
    r = SessionRegistry()
    r.update("s1", "projA", "running", now=100.0)
    r.update_usage("s1", now=101.0, context_pct=35,
                   context_tokens=351590, context_size=1000000,
                   five_hour={"used_percentage": 38, "resets_at": 1781798400},
                   seven_day={"used_percentage": 5, "resets_at": 1782378000})
    st = r.status(now=102.0)
    a = st["agents"][0]
    assert a["context_pct"] == 35
    assert a["context_tokens"] == 351590
    assert a["context_size"] == 1000000
    assert st["limits"]["five_hour"] == {"used_percentage": 38, "resets_at": 1781798400}
    assert st["limits"]["seven_day"]["used_percentage"] == 5


def test_status_without_usage_is_null():
    r = SessionRegistry()
    r.update("s1", "p", "running", now=1.0)
    st = r.status(now=1.0)
    assert st["agents"][0]["context_pct"] is None
    assert st["limits"] is None


def test_gc_drops_stale_usage():
    r = SessionRegistry()
    r.update("s1", "p", "running", now=0.0)
    r.update_usage("s1", now=0.0, context_pct=10)
    r.gc(now=2000.0, idle_timeout=100.0)
    assert "s1" not in r._usage


def test_gc_removes_stale_only():
    r = SessionRegistry()
    r.update("old", "p1", "running", now=0.0)
    r.update("fresh", "p2", "running", now=100.0)
    removed = r.gc(now=200.0, idle_timeout=150.0)
    assert removed == ["old"]
    assert "old" not in r._sessions
    assert "fresh" in r._sessions
