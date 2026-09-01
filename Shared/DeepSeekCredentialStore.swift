import Darwin
import Foundation

enum DeepSeekCredentialStore {
    private static let maximumTokenLength = 64 * 1024

    static var tokenURL: URL {
        UsageSnapshot.snapshotURL
            .deletingLastPathComponent()
            .appendingPathComponent("deepseek-platform-token")
    }

    static func readToken() -> String? {
        guard let data = try? Data(contentsOf: tokenURL),
              let token = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { return nil }
        return token
    }

    static func writeToken(_ token: String) throws {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              clean.utf8.count <= maximumTokenLength,
              clean.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { throw CocoaError(.validationMissingMandatoryProperty) }

        let manager = FileManager.default
        let directory = tokenURL.deletingLastPathComponent()
        try manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let temporary = directory.appendingPathComponent(".deepseek-token-\(UUID().uuidString).tmp")
        try Data(clean.utf8).write(to: temporary, options: .withoutOverwriting)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        guard Darwin.rename(temporary.path, tokenURL.path) == 0 else {
            let code = errno
            try? manager.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
    }

    static func token(fromLocalStorageValue rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maximumTokenLength else { return nil }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
            if let token = object as? String {
                return validated(token)
            }
            if let dictionary = object as? [String: Any] {
                for key in ["value", "token", "access_token"] {
                    if let token = dictionary[key] as? String,
                       let clean = validated(token) {
                        return clean
                    }
                }
            }
        }
        return validated(trimmed)
    }

    private static func validated(_ token: String) -> String? {
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              clean.utf8.count <= maximumTokenLength,
              clean.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return clean
    }
}
