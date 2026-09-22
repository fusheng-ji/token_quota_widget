import Foundation
import XCTest

final class RuntimeSupportTests: XCTestCase {
    func testLargeStandardInputAndErrorOutputCannotFillAPipe() throws {
        let payload = Data(repeating: 0x61, count: 256 * 1024)
        let result = try SubprocessRunner.run(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-c", "printf '%131072s' '' >&2; /bin/cat"],
            standardInput: payload,
            timeout: 5
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.standardOutput, payload)
        XCTAssertEqual(result.standardError.count, 131_072)
    }

    func testTimeoutTerminatesAProcessIgnoringSIGTERM() throws {
        let start = ProcessInfo.processInfo.systemUptime
        let result = try SubprocessRunner.run(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-c", "trap '' TERM; while true; do :; done"],
            timeout: 0.1
        )
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 3)
    }

    func testCancellationPreventsLaunch() throws {
        let cancellation = SubprocessCancellation()
        cancellation.cancel()
        let result = try SubprocessRunner.run(
            executable: URL(fileURLWithPath: "/does-not-exist"), arguments: [], cancellation: cancellation
        )
        XCTAssertTrue(result.cancelled)
        XCTAssertFalse(result.timedOut)
    }

    func testAtomicWriteCreatesPrivateFilesAndCleansFailedReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("snapshot.json")
        try AtomicFileWriter.writeJSON(["version": 5], to: destination, protectDirectory: true)
        let permissions = try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        let blocked = directory.appendingPathComponent("blocked")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: false)
        XCTAssertThrowsError(try AtomicFileWriter.write(Data("test".utf8), to: blocked))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), ["snapshot.json", "blocked"])
    }

    func testActivityRefreshQueuesOnlyOneFullRefresh() {
        var schedule = RefreshSchedule()
        XCTAssertEqual(schedule.request(.codex), .codex)
        XCTAssertNil(schedule.request(.codex))
        XCTAssertNil(schedule.request(.all))
        XCTAssertTrue(schedule.showsFullRefresh)
        XCTAssertNil(schedule.request(.all))
        XCTAssertEqual(schedule.finish(), .all)
        XCTAssertEqual(schedule.state, .running(.all))
        XCTAssertNil(schedule.finish())
        XCTAssertEqual(schedule.state, .idle)
    }

    func testFullRefreshDropsRedundantActivityPolls() {
        var schedule = RefreshSchedule()
        XCTAssertEqual(schedule.request(.all), .all)
        XCTAssertNil(schedule.request(.codex))
        XCTAssertNil(schedule.finish())
        XCTAssertFalse(schedule.showsFullRefresh)
    }
}
