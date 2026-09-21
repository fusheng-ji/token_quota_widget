#!/usr/bin/env python3
"""Read Codex token records without returning prompts or response content."""

import hashlib
import json
import os
import sys
from datetime import datetime


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def parse_timestamp(value):
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def candidate_files(root, day_start):
    seen = set()
    for directory_name in ("sessions", "archived_sessions"):
        directory = os.path.join(root, directory_name)
        if not os.path.isdir(directory):
            continue
        for current, _, names in os.walk(directory):
            for name in names:
                if not name.lower().endswith(".jsonl"):
                    continue
                path = os.path.join(current, name)
                try:
                    stat = os.stat(path, follow_symlinks=False)
                except OSError:
                    continue
                if not os.path.isfile(path) or stat.st_mtime < day_start:
                    continue
                identity = digest(f"{stat.st_dev}:{stat.st_ino}")
                if identity in seen:
                    continue
                seen.add(identity)
                yield path, identity, stat.st_size


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: remote_codex_usage.py ROOT DAY_START DAY_END")
    root = sys.argv[1]
    day_start = float(sys.argv[2])
    day_end = float(sys.argv[3])
    request = json.load(sys.stdin)
    prior_files = request.get("files", {}) if isinstance(request, dict) else {}
    response_files = {}
    active_files = []

    for path, identity, size in candidate_files(root, day_start):
        active_files.append(identity)
        prior_offset = prior_files.get(identity, 0)
        if not isinstance(prior_offset, int) or prior_offset < 0:
            prior_offset = 0
        reset = size < prior_offset
        offset = 0 if reset else prior_offset
        if size <= offset:
            continue
        try:
            with open(path, "rb") as handle:
                handle.seek(offset)
                appended = handle.read()
        except OSError:
            continue
        final_newline = appended.rfind(b"\n")
        if final_newline < 0:
            continue
        complete = appended[: final_newline + 1]
        records = []
        relative_offset = 0
        for raw_line in complete.splitlines(keepends=True):
            line = raw_line.rstrip(b"\r\n")
            try:
                record = json.loads(line)
            except (UnicodeDecodeError, json.JSONDecodeError):
                relative_offset += len(raw_line)
                continue
            if record.get("type") != "token_usage_record":
                relative_offset += len(raw_line)
                continue
            timestamp = parse_timestamp(record.get("timestamp"))
            payload = record.get("payload", {})
            usage = payload.get("usage", {})
            values = (
                usage.get("input_tokens"),
                usage.get("cached_input_tokens", 0),
                usage.get("output_tokens"),
                usage.get("reasoning_output_tokens", 0),
            )
            if (
                timestamp is None
                or timestamp < day_start
                or timestamp >= day_end
                or any(not isinstance(value, int) or value < 0 for value in values)
            ):
                relative_offset += len(raw_line)
                continue
            response_id = payload.get("response_id")
            if not isinstance(response_id, str) or not response_id:
                response_id = f"{identity}:{offset + relative_offset}:{record.get('timestamp', '')}"
            session_id = payload.get("session_id")
            if not isinstance(session_id, str) or not session_id:
                session_id = identity
            records.append(
                {
                    "responseHash": digest(response_id),
                    "sessionHash": digest(session_id),
                    "timestamp": timestamp,
                    "inputTokens": values[0],
                    "cachedInputTokens": values[1],
                    "outputTokens": values[2],
                    "reasoningTokens": values[3],
                }
            )
            relative_offset += len(raw_line)
        response_files[identity] = {
            "offset": offset + len(complete),
            "reset": reset,
            "records": records,
        }

    json.dump(
        {"activeFiles": sorted(active_files), "files": response_files},
        sys.stdout,
        separators=(",", ":"),
        sort_keys=True,
    )


if __name__ == "__main__":
    main()
