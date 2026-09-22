import Darwin
import Foundation

/// Private files are created with their final permissions before any bytes are written.
enum AtomicFileWriter {
    static func writeJSON<Value: Encodable>(
        _ value: Value,
        to url: URL,
        prettyPrinted: Bool = false,
        protectDirectory: Bool = false
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if prettyPrinted { encoder.outputFormatting.insert(.prettyPrinted) }
        try write(encoder.encode(value), to: url, protectDirectory: protectDirectory)
    }

    static func write(_ data: Data, to url: URL, protectDirectory: Bool = false) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if protectDirectory {
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        let temporary = directory.appendingPathComponent(".beavermeter-\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? handle.close()
            try? manager.removeItem(at: temporary)
        }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        guard Darwin.rename(temporary.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
