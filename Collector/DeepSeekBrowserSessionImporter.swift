import Foundation
import SweetCookieKit

enum DeepSeekBrowserSessionImporter {
    private static let origin = "https://platform.deepseek.com"

    static func candidateTokens() -> [String] {
        var seen = Set<String>()
        var tokens: [String] = []

        for root in ChromiumProfileLocator.roots() {
            guard let profiles = try? FileManager.default.contentsOfDirectory(
                at: root.url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for profile in profiles {
                guard isBrowserProfile(profile) else { continue }
                let levelDB = profile
                    .appendingPathComponent("Local Storage", isDirectory: true)
                    .appendingPathComponent("leveldb", isDirectory: true)
                guard FileManager.default.fileExists(atPath: levelDB.path) else { continue }

                let entries = ChromiumLocalStorageReader.readEntries(for: origin, in: levelDB)
                for entry in entries where entry.key == "userToken" {
                    guard let token = DeepSeekCredentialStore.token(fromLocalStorageValue: entry.value),
                          seen.insert(token).inserted else { continue }
                    tokens.append(token)
                }
            }
        }
        return tokens
    }

    static func importValidatedSession() async throws -> Bool {
        for token in candidateTokens() {
            do {
                try await DeepSeekPlatformClient().validate(token: token)
                try DeepSeekCredentialStore.writeToken(token)
                return true
            } catch DeepSeekPlatformError.sessionExpired {
                continue
            }
        }
        return false
    }

    private static func isBrowserProfile(_ url: URL) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return false
        }
        let name = url.lastPathComponent
        return name == "Default" || name.hasPrefix("Profile ") || name.hasPrefix("user-")
    }
}
