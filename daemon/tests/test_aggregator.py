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

def test_gc_removes_stale_only():
    r = SessionRegistry()
    r.update("old", "p1", "running", now=0.0)
    r.update("fresh", "p2", "running", now=100.0)
    removed = r.gc(now=200.0, idle_timeout=150.0)
    assert removed == ["old"]
    assert "old" not in r._sessions
    assert "fresh" in r._sessions
