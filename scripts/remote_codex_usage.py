#!/usr/bin/env python3
"""Read Codex token records without returning prompts or response content."""

import hashlib
import json
import math
import os
import stat as stat_module
import sys
from datetime import datetime


def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def parse_timestamp(value):
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed.timestamp() if parsed.tzinfo is not None else None
    except (ValueError, OverflowError):
        return None


def candidate_files(root, day_start, failed_files):
    seen = set()
    for directory_name in ("sessions", "archived_sessions"):
        directory = os.path.join(root, directory_name)
        if not os.path.isdir(directory):
            continue
        def on_error(error):
            failed_files.add(digest(error.filename or directory))

        for current, directories, names in os.walk(directory, onerror=on_error):
            directories.sort()
            names.sort()
            for name in names:
                if not name.lower().endswith(".jsonl"):
                    continue
                path = os.path.join(current, name)
                try:
                    stat = os.stat(path, follow_symlinks=False)
                except OSError:
                    failed_files.add(digest(path))
                    continue
                if not stat_module.S_ISREG(stat.st_mode) or stat.st_mtime < day_start:
                    continue
                identity = digest(f"{stat.st_dev}:{stat.st_ino}")
                if identity in seen:
                    continue
                seen.add(identity)
                yield path, identity, stat.st_size


def scan(root, day_start, day_end, cutoff, request):
    prior_files = request.get("files", {}) if isinstance(request, dict) else {}
    if not isinstance(prior_files, dict):
        prior_files = {}
    response_files = {}
    active_files = []
    failed_files = set()
    if not os.path.isdir(root):
        failed_files.add(digest(root))

    for path, identity, size in candidate_files(root, day_start, failed_files):
        active_files.append(identity)
        prior_offset = prior_files.get(identity, 0)
        if type(prior_offset) is not int or prior_offset < 0:
            prior_offset = 0
        reset = size < prior_offset
        offset = 0 if reset else prior_offset
        if size <= offset and not reset:
            continue
        try:
            with open(path, "rb") as handle:
                handle.seek(offset)
                appended = handle.read()
        except OSError:
            failed_files.add(identity)
            continue
        final_newline = appended.rfind(b"\n")
        if final_newline < 0 and not reset:
            continue
        complete = appended[: final_newline + 1]
        consumed = len(complete)
        records = []
        relative_offset = 0
        for raw_line in complete.splitlines(keepends=True):
            line = raw_line.rstrip(b"\r\n")
            if b'"token_usage_record"' not in line:
                relative_offset += len(raw_line)
                continue
            try:
                record = json.loads(line)
            except (UnicodeDecodeError, json.JSONDecodeError):
                relative_offset += len(raw_line)
                continue
            if not isinstance(record, dict) or record.get("type") != "token_usage_record":
                relative_offset += len(raw_line)
                continue
            timestamp = parse_timestamp(record.get("timestamp"))
            payload = record.get("payload", {})
            if not isinstance(payload, dict):
                relative_offset += len(raw_line)
                continue
            usage = payload.get("usage", {})
            if not isinstance(usage, dict):
                relative_offset += len(raw_line)
                continue
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
                or any(type(value) is not int or not 0 <= value <= (2**63 - 1) for value in values)
            ):
                relative_offset += len(raw_line)
                continue
            if timestamp > cutoff:
                consumed = min(consumed, relative_offset)
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
            "offset": offset + consumed,
            "reset": reset,
            "records": records,
        }

    return {
        "complete": not failed_files,
        "failedFiles": sorted(failed_files),
        "activeFiles": sorted(active_files),
        "files": response_files,
    }


def main():
    if len(sys.argv) != 5:
        raise SystemExit("usage: remote_codex_usage.py ROOT DAY_START DAY_END CUTOFF")
    day_start, day_end, cutoff = map(float, sys.argv[2:])
    if not all(map(math.isfinite, (day_start, day_end, cutoff))) or not day_start <= cutoff < day_end:
        raise SystemExit("invalid scan window")
    json.dump(
        scan(sys.argv[1], day_start, day_end, cutoff, json.load(sys.stdin)),
        sys.stdout,
        separators=(",", ":"),
        sort_keys=True,
    )


if __name__ == "__main__":
    main()
