import Foundation
import XCTest

final class CodexCollectionTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var now: Date {
        ISO8601DateFormatter().date(from: "2026-09-23T12:00:00Z")!
    }

    private func workspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("beavermeter-collector-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func writeJSON(_ object: Any, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    private func appendRecord(
        to file: URL,
        responseID: String,
        input: Int,
        newline: Bool = true,
        timestamp: String = "2026-09-23T10:00:00Z"
    ) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let object: [String: Any] = [
            "type": "token_usage_record", "timestamp": timestamp,
            "payload": [
                "response_id": responseID, "session_id": "local-session",
                "usage": ["input_tokens": input, "cached_input_tokens": 5,
                          "output_tokens": 0, "reasoning_output_tokens": 0]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data + (newline ? Data([0x0A]) : Data()))
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
    }

    private func remoteFixture(to url: URL, responseID: String = "remote", input: Int = 300,
                               complete: Bool = true, failedFiles: [String] = []) throws {
        let file = CodexUsageSupport.hash("remote-file")
        let response: [String: Any] = [
            "complete": complete, "failedFiles": failedFiles, "activeFiles": [file],
            "files": [file: [
                "offset": 1, "reset": false,
                "records": [[
                    "responseHash": CodexUsageSupport.hash(responseID),
                    "sessionHash": CodexUsageSupport.hash("remote-session"),
                    "timestamp": now.timeIntervalSince1970 - 120,
                    "inputTokens": input, "cachedInputTokens": 2,
                    "outputTokens": 0, "reasoningTokens": 0
                ]]
            ]]
        ]
        try writeJSON(response, to: url)
    }

    private func legacyFixture(to url: URL, total: Int) throws {
        let value = CodexTokenTotals(totalTokens: total, inputTokens: total,
                                     cachedInputTokens: 0, outputTokens: 0,
                                     reasoningTokens: 0, sessionCount: total > 0 ? 1 : 0)
        try JSONEncoder().encode(value).write(to: url)
    }

    func testOldLocalDirectoryIncrementalHalfLineArchiveAndTruncation() throws {
        let root = try workspace()
        let home = root.appendingPathComponent("home")
        let file = home.appendingPathComponent("sessions/2020/01/01/old.jsonl")
        let cache = root.appendingPathComponent("local-cache.json")
        try appendRecord(to: file, responseID: "first", input: 100)
        var result = try CodexUsageRecordScanner.collect(codexHomePath: home.path, now: now,
                                                          calendar: calendar, cacheURL: cache)
        XCTAssertEqual(result.totals?.totalTokens, 100)
        XCTAssertTrue(result.complete)

        try appendRecord(to: file, responseID: "second", input: 80, newline: false)
        result = try CodexUsageRecordScanner.collect(codexHomePath: home.path, now: now,
                                                      calendar: calendar, cacheURL: cache)
        XCTAssertEqual(result.totals?.totalTokens, 100)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0x0A]))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        result = try CodexUsageRecordScanner.collect(codexHomePath: home.path, now: now,
                                                      calendar: calendar, cacheURL: cache)
        XCTAssertEqual(result.totals?.totalTokens, 180)

        let archived = home.appendingPathComponent("archived_sessions/copy.jsonl")
        try appendRecord(to: archived, responseID: "first", input: 100)
        result = try CodexUsageRecordScanner.collect(codexHomePath: home.path, now: now,
                                                      calendar: calendar, cacheURL: cache)
        XCTAssertEqual(result.totals?.totalTokens, 180)
        try Data().write(to: file)
        try appendRecord(to: file, responseID: "replacement", input: 10)
        result = try CodexUsageRecordScanner.collect(codexHomePath: home.path, now: now,
                                                      calendar: calendar, cacheURL: cache)
        XCTAssertEqual(result.totals?.totalTokens, 110)
    }

    func testLegacyLocalIsSelectedBeforeUniqueRemoteAndFailuresRetainSameDayCache() async throws {
        let root = try workspace()
        let home = root.appendingPathComponent("home")
        let file = home.appendingPathComponent("sessions/2026/09/23/live.jsonl")
        try appendRecord(to: file, responseID: "local", input: 100)
        let legacy = root.appendingPathComponent("legacy.json")
        try legacyFixture(to: legacy, total: 200)
        let remote = root.appendingPathComponent("remote.json")
        try remoteFixture(to: remote)
        let localCache = root.appendingPathComponent("beaver-meter-codex-scan-v2.json")
        var environment: [String: String] = [
            "CODEX_HOME": home.path,
            "CODEX_LEGACY_TOKEN_FIXTURE": legacy.path,
            "CODEX_REMOTE_SSH_HOST": "fixture-host",
            "CODEX_REMOTE_ROOT": "/fixture/codex",
            "CODEX_REMOTE_PYTHON": "/usr/bin/python3",
            "CODEX_REMOTE_RESPONSE_FIXTURE": remote.path
        ]
        let first = await CodexTokenCollector.collect(previous: .unavailable("fixture"), now: now,
                                                       scanCacheURL: localCache, environment: environment,
                                                       calendar: calendar)
        XCTAssertEqual(first.status, .ready)
        XCTAssertEqual(first.value?.totalTokens, 500)
        let measurementURL = root.appendingPathComponent("beaver-meter-codex-measurement-v1.json")
        let measurementData = try Data(contentsOf: measurementURL)
        let second = await CodexTokenCollector.collect(previous: first, now: now.addingTimeInterval(30),
                                                        scanCacheURL: localCache, environment: environment,
                                                        calendar: calendar)
        XCTAssertEqual(second.value, first.value)
        XCTAssertEqual(second.measuredAt, first.measuredAt)
        XCTAssertEqual(try Data(contentsOf: measurementURL), measurementData)

        environment["CODEX_REMOTE_RESPONSE_FIXTURE"] = root.appendingPathComponent("offline.json").path
        let offline = await CodexTokenCollector.collect(previous: second, now: now.addingTimeInterval(60),
                                                         scanCacheURL: localCache, environment: environment,
                                                         calendar: calendar)
        XCTAssertEqual(offline.status, .stale)
        XCTAssertEqual(offline.value?.totalTokens, 500)
        XCTAssertEqual(offline.measuredAt, second.measuredAt)

        environment["CODEX_REMOTE_SSH_HOST"] = "different-host"
        let changedSource = await CodexTokenCollector.collect(previous: offline, now: now.addingTimeInterval(90),
                                                               scanCacheURL: localCache, environment: environment,
                                                               calendar: calendar)
        XCTAssertEqual(changedSource.value?.totalTokens, 200)
        XCTAssertEqual(changedSource.status, .stale)
    }

    func testRemoteOverlapIsDeduplicatedAndCurrentDayFailureDoesNotClearRecords() throws {
        let root = try workspace()
        let home = root.appendingPathComponent("home")
        try appendRecord(to: home.appendingPathComponent("sessions/2026/09/23/live.jsonl"),
                         responseID: "shared", input: 100)
        let remote = root.appendingPathComponent("remote.json")
        try remoteFixture(to: remote, responseID: "shared", input: 100)
        let environment = ["CODEX_HOME": home.path, "CODEX_REMOTE_SSH_HOST": "fixture-host",
                           "CODEX_REMOTE_ROOT": "/fixture/codex", "CODEX_REMOTE_PYTHON": "/usr/bin/python3",
                           "CODEX_REMOTE_RESPONSE_FIXTURE": remote.path]
        let cache = root.appendingPathComponent("beaver-meter-codex-scan-v2.json")
        var result = try CodexTokenAggregation.collect(now: now, environment: environment,
                                                        localCacheURL: cache, calendar: calendar)
        XCTAssertEqual(result.totals?.totalTokens, 100)
        XCTAssertNil(result.remoteUniqueTotals)

        try remoteFixture(to: remote, responseID: "unique", input: 300, complete: false,
                          failedFiles: [CodexUsageSupport.hash("unreadable")])
        result = try CodexTokenAggregation.collect(now: now.addingTimeInterval(30), environment: environment,
                                                    localCacheURL: cache, calendar: calendar)
        XCTAssertFalse(result.remote.complete)
        XCTAssertEqual(result.totals?.totalTokens, 400)
        try writeJSON(["complete": false, "failedFiles": [CodexUsageSupport.hash("unreadable")],
                       "activeFiles": [], "files": [:]] as [String: Any], to: remote)
        result = try CodexTokenAggregation.collect(now: now.addingTimeInterval(60), environment: environment,
                                                    localCacheURL: cache, calendar: calendar)
        XCTAssertEqual(result.totals?.totalTokens, 400)
        XCTAssertFalse(result.remote.complete)
    }

    func testRemoteCacheDoesNotCrossDay() throws {
        let root = try workspace()
        let remote = root.appendingPathComponent("remote.json")
        try remoteFixture(to: remote)
        let cache = root.appendingPathComponent("remote-cache.json")
        var environment = ["CODEX_REMOTE_SSH_HOST": "fixture-host", "CODEX_REMOTE_ROOT": "/fixture/codex",
                           "CODEX_REMOTE_PYTHON": "/usr/bin/python3", "CODEX_REMOTE_RESPONSE_FIXTURE": remote.path]
        XCTAssertEqual(CodexRemoteUsageCollector.collect(environment: environment, now: now,
                                                          calendar: calendar, cacheURL: cache)
            .usageByResponseHash.count, 1)
        environment["CODEX_REMOTE_RESPONSE_FIXTURE"] = root.appendingPathComponent("offline").path
        let tomorrow = CodexRemoteUsageCollector.collect(environment: environment,
                                                          now: now.addingTimeInterval(86400), calendar: calendar,
                                                          cacheURL: cache)
        XCTAssertFalse(tomorrow.complete)
        XCTAssertTrue(tomorrow.usageByResponseHash.isEmpty)
    }

    func testFirstSSHFailureKeepsLocalReadingWithoutRealNetwork() async throws {
        let root = try workspace()
        let home = root.appendingPathComponent("home")
        try appendRecord(to: home.appendingPathComponent("sessions/old/task.jsonl"),
                         responseID: "local-first", input: 100)
        let ssh = root.appendingPathComponent("fake-ssh")
        try Data("#!/bin/sh\nexit 255\n".utf8).write(to: ssh)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: ssh.path)
        let legacy = root.appendingPathComponent("legacy.json")
        try legacyFixture(to: legacy, total: 0)
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/remote_codex_usage.py")
        let environment = [
            "CODEX_HOME": home.path,
            "CODEX_LEGACY_TOKEN_FIXTURE": legacy.path,
            "CODEX_REMOTE_SSH_HOST": "fixture-host",
            "CODEX_REMOTE_ROOT": "/fixture/codex",
            "CODEX_REMOTE_PYTHON": "/usr/bin/python3",
            "BEAVERMETER_REMOTE_SCRIPT": script.path,
            "BEAVERMETER_SSH": ssh.path
        ]
        let result = await CodexTokenCollector.collect(previous: .unavailable("new"), now: now,
                                                       scanCacheURL: root.appendingPathComponent("local.json"),
                                                       environment: environment, calendar: calendar)
        XCTAssertEqual(result.status, .stale)
        XCTAssertEqual(result.value?.totalTokens, 100)
        XCTAssertTrue(result.message?.contains("Remote Codex") == true)
    }
}
