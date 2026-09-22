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

        try AtomicFileWriter.write(Data(clean.utf8), to: tokenURL, protectDirectory: true)
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
