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
        self.root = Path(os.path.realpath(self.temp.name))
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

    def test_discovers_only_own_codex_app_server_home_without_returning_environment(self):
        proc = self.root / "proc" / "123"
        proc.mkdir(parents=True)
        (proc / "cmdline").write_bytes(b"/bin/codex\0app-server\0")
        (proc / "environ").write_bytes(
            f"CODEX_HOME={self.root / 'active'}\0SECRET=never-send-me\0".encode()
        )
        homes, complete = SCANNER.active_codex_homes(str(proc.parent))
        self.assertTrue(complete)
        self.assertEqual(homes, {os.path.realpath(self.root / "active")})
        result = SCANNER.scan_sources(
            str(self.root), self.start, self.end, self.now, {"roots": {}},
            discover=lambda: (homes, complete),
        )
        self.assertEqual(len(result["roots"]), 2)
        self.assertNotIn("CODEX_HOME", json.dumps(result))
        self.assertNotIn("never-send-me", json.dumps(result))
        self.assertNotIn(str(self.root), json.dumps(result))

    def test_discovery_failure_is_distinct_from_no_active_process(self):
        homes, complete = SCANNER.active_codex_homes(str(self.root / "missing-proc"))
        self.assertEqual(homes, set())
        self.assertFalse(complete)
        result = SCANNER.scan_sources(
            str(self.root), self.start, self.end, self.now, {"roots": {}},
            discover=lambda: (homes, complete),
        )
        self.assertFalse(result["discoveryComplete"])
        self.assertEqual(result["activeRootHashes"], [])

    def test_migrated_home_scans_both_roots_and_reports_ambiguity(self):
        configured = self.root / "configured"
        active = self.root / "migrated"
        old = configured / "sessions" / "old.jsonl"
        old.parent.mkdir(parents=True)
        old.write_text(json.dumps(self.record("old")) + "\n")
        os.utime(old, (self.now, self.now))
        path = active / "sessions" / "new.jsonl"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(self.record("new", input_tokens=300)) + "\n")
        os.utime(path, (self.now, self.now))
        first = SCANNER.scan_sources(
            str(configured), self.start, self.end, self.now, {"roots": {}},
            discover=lambda: ({str(active)}, True),
        )
        hashes = {SCANNER.digest(str(configured)), SCANNER.digest(os.path.realpath(active))}
        self.assertEqual(set(first["roots"]), hashes)
        self.assertEqual(sum(len(delta["records"]) for root in first["roots"].values()
                             for delta in root["files"].values()), 2)
        self.assertEqual(first["activeRootHashes"], [SCANNER.digest(os.path.realpath(active))])
        second = SCANNER.scan_sources(
            str(configured), self.start, self.end, self.now,
            {"roots": {key: {"files": {identity: delta["offset"]
                         for identity, delta in root["files"].items()}}
                       for key, root in first["roots"].items()}},
            discover=lambda: ({str(active), str(configured)}, True),
        )
        self.assertEqual(len(second["activeRootHashes"]), 2)
        self.assertTrue(all(not root["files"] for root in second["roots"].values()))


if __name__ == "__main__":
    unittest.main()
