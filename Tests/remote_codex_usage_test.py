"""Run the bundled remote protocol against isolated JSONL trees."""

import importlib.util
import json
import os
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "remote_codex_usage.py"
SPEC = importlib.util.spec_from_file_location("remote_codex_usage", SCRIPT)
SCANNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SCANNER)


class RemoteCodexUsageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.now = datetime(2026, 9, 23, 12, 0, tzinfo=timezone.utc).timestamp()
        self.start = datetime(2026, 9, 23, 0, 0, tzinfo=timezone.utc).timestamp()
        self.end = self.start + 86400

    def rollout(self, relative, records):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("wb") as handle:
            for record in records:
                handle.write(record if isinstance(record, bytes) else (json.dumps(record) + "\n").encode())
        os.utime(path, (self.now, self.now))
        return path

    def record(self, response="one", timestamp="2026-09-23T10:00:00Z", input_tokens=100):
        return {
            "type": "token_usage_record", "timestamp": timestamp,
            "payload": {
                "response_id": response, "session_id": "session",
                "usage": {"input_tokens": input_tokens, "cached_input_tokens": 30,
                          "output_tokens": 10, "reasoning_output_tokens": 2},
                "prompt": "never-send-me",
            },
        }

    def scan(self, files=None, cutoff=None):
        return SCANNER.scan(str(self.root), self.start, self.end, cutoff or self.now, {"files": files or {}})

    def test_old_directory_and_archive_are_scanned_without_private_text(self):
        self.rollout("sessions/2020/01/01/old.jsonl", [self.record("old")])
        self.rollout("archived_sessions/archive.jsonl", [self.record("archive", input_tokens=40)])
        result = self.scan()
        self.assertTrue(result["complete"])
        self.assertEqual(len(result["activeFiles"]), 2)
        self.assertEqual(len(result["files"]), 2)
        self.assertEqual(sum(len(item["records"]) for item in result["files"].values()), 2)
        self.assertNotIn("never-send-me", json.dumps(result))
        self.assertNotIn(str(self.root), json.dumps(result))

    def test_incremental_append_and_incomplete_line(self):
        path = self.rollout("sessions/2026/09/23/active.jsonl", [self.record()])
        first = self.scan()
        identity, delta = next(iter(first["files"].items()))
        with path.open("ab") as handle:
            handle.write(json.dumps(self.record("two")).encode())
        os.utime(path, (self.now, self.now))
        partial = self.scan({identity: delta["offset"]})
        self.assertEqual(partial["files"], {})
        with path.open("ab") as handle:
            handle.write(b"\n")
        os.utime(path, (self.now, self.now))
        completed = self.scan({identity: delta["offset"]})
        self.assertEqual(len(completed["files"][identity]["records"]), 1)
        self.assertGreater(completed["files"][identity]["offset"], delta["offset"])

    def test_truncated_file_restarts_at_zero(self):
        path = self.rollout("sessions/2026/09/23/active.jsonl", [self.record("one"), self.record("two")])
        first = self.scan()
        identity, delta = next(iter(first["files"].items()))
        path.write_text(json.dumps(self.record("replacement", input_tokens=4)) + "\n")
        os.utime(path, (self.now, self.now))
        second = self.scan({identity: delta["offset"]})
        self.assertTrue(second["files"][identity]["reset"])
        self.assertEqual(second["files"][identity]["records"][0]["inputTokens"], 4)

    def test_future_and_other_day_records_are_not_consumed_as_today(self):
        path = self.rollout("sessions/2026/09/23/active.jsonl", [
            self.record("past", "2026-09-22T23:59:59Z"),
            self.record("now", "2026-09-23T10:00:00Z"),
            self.record("future", "2026-09-23T18:00:00Z"),
        ])
        first = self.scan()
        identity, delta = next(iter(first["files"].items()))
        self.assertEqual(len(delta["records"]), 1)
        self.assertLess(delta["offset"], path.stat().st_size)
        second = self.scan({identity: delta["offset"]}, cutoff=self.start + 20 * 3600)
        self.assertEqual(len(second["files"][identity]["records"]), 1)

    def test_missing_root_and_partial_stat_failure_report_incomplete(self):
        missing = SCANNER.scan(str(self.root / "missing"), self.start, self.end, self.now, {"files": {}})
        self.assertFalse(missing["complete"])
        self.assertEqual(missing["failedFiles"], [SCANNER.digest(str(self.root / "missing"))])
        self.rollout("sessions/2026/09/23/good.jsonl", [self.record()])
        bad = self.rollout("sessions/2026/09/23/bad.jsonl", [self.record("bad")])
        original_stat = SCANNER.os.stat

        def fail_one(path, *args, **kwargs):
            if str(path) == str(bad):
                raise PermissionError("fixture unreadable")
            return original_stat(path, *args, **kwargs)

        with patch.object(SCANNER.os, "stat", side_effect=fail_one):
            partial = self.scan()
        self.assertFalse(partial["complete"])
        self.assertIn(SCANNER.digest(str(bad)), partial["failedFiles"])
        self.assertEqual(len(partial["files"]), 1)


if __name__ == "__main__":
    unittest.main()
