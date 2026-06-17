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
