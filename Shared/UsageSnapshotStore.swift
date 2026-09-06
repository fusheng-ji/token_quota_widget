import Darwin
import Foundation

extension UsageSnapshot {
    static var snapshotURL: URL {
        let home: URL = {
            guard let entry = getpwuid(getuid()) else {
                return FileManager.default.homeDirectoryForCurrentUser
            }
            return URL(fileURLWithPath: String(cString: entry.pointee.pw_dir), isDirectory: true)
        }()
        return home.appendingPathComponent("Library/Application Support/BeaverMeter/beaver-meter-snapshot.json")
    }

    static func load() -> UsageSnapshot {
        load(from: snapshotURL)
    }

    static func load(from url: URL) -> UsageSnapshot {
        guard let data = try? Data(contentsOf: url) else { return .unavailable }
        return decode(data) ?? .unavailable
    }

    static func decode(_ data: Data) -> UsageSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let snapshot = try? decoder.decode(UsageSnapshot.self, from: data),
           snapshot.schemaVersion == Self.currentSchemaVersion {
            return snapshot
        }
        return nil
    }
}
