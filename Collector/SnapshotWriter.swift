import Darwin
import Foundation

enum SnapshotWriter {
    static func loadPrevious(from url: URL) -> UsageSnapshot {
        guard let data = try? Data(contentsOf: url) else { return .unavailable }
        return UsageSnapshot.decode(data) ?? .unavailable
    }

    static func write(_ snapshot: UsageSnapshot, to url: URL) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        if !manager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            try manager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        if directory.standardizedFileURL
            == UsageSnapshot.snapshotURL.deletingLastPathComponent().standardizedFileURL {
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)
        let temporary = directory.appendingPathComponent(
            ".codex-week-snapshot-\(UUID().uuidString).tmp"
        )
        try data.write(to: temporary, options: .withoutOverwriting)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        guard Darwin.rename(temporary.path, url.path) == 0 else {
            let code = errno
            try? manager.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
