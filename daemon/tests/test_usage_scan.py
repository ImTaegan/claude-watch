import json
import os
import time

from usage_scan import scan_today_output_tokens


def _write(path, entries):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for e in entries:
            f.write(json.dumps(e) + "\n")


def test_sums_today_assistant_output_tokens(tmp_path):
    now = time.time()
    today = __import__("datetime").datetime.fromtimestamp(now).date().isoformat()
    proj = str(tmp_path / "projects" / "-some-cwd")
    _write(os.path.join(proj, "sess.jsonl"), [
        {"type": "assistant", "timestamp": f"{today}T10:00:00Z",
         "message": {"usage": {"output_tokens": 100}}},
        {"type": "assistant", "timestamp": f"{today}T11:00:00Z",
         "message": {"usage": {"output_tokens": 250}}},
        {"type": "user", "timestamp": f"{today}T11:00:01Z"},  # ignored
        {"type": "assistant", "timestamp": "2020-01-01T00:00:00Z",
         "message": {"usage": {"output_tokens": 9999}}},      # not today
    ])
    total = scan_today_output_tokens(str(tmp_path / "projects"), now)
    assert total == 350


def test_skips_files_not_modified_today(tmp_path):
    now = time.time()
    today = __import__("datetime").datetime.fromtimestamp(now).date().isoformat()
    proj = str(tmp_path / "projects" / "-old")
    p = os.path.join(proj, "old.jsonl")
    _write(p, [{"type": "assistant", "timestamp": f"{today}T10:00:00Z",
                "message": {"usage": {"output_tokens": 500}}}])
    old = now - 3 * 86400
    os.utime(p, (old, old))  # mtime 3 days ago -> skipped
    assert scan_today_output_tokens(str(tmp_path / "projects"), now) == 0


def test_empty_dir_is_zero(tmp_path):
    assert scan_today_output_tokens(str(tmp_path / "nope"), time.time()) == 0
