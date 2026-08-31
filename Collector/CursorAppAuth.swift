// Portions adapted from CodexBar at commit 5d7c1f29fd11ecbf697b3532340f75b25319f811.
// Copyright (c) 2026 Peter Steinberger. Licensed under the MIT License.

import Foundation

struct CursorAppAuthSession {
    let accessToken: String

    var cookieHeader: String {
        get throws {
            "WorkosCursorSessionToken=\(try userID())%3A%3A\(accessToken)"
        }
    }

    private func userID() throws -> String {
        let payload = try jwtPayload()
        guard let subject = payload["sub"] as? String,
              let userID = subject
                .split(separator: "|", omittingEmptySubsequences: true)
                .last
                .map(String.init),
              !userID.isEmpty else {
            throw CursorDashboardError.invalidSession(
                "Cursor access token is missing its user ID."
            )
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard userID.unicodeScalars.allSatisfy(allowed.contains) else {
            throw CursorDashboardError.invalidSession(
                "Cursor access token contains an invalid user ID."
            )
        }
        return userID
    }

    private func jwtPayload() throws -> [String: Any] {
        let parts = accessToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            throw CursorDashboardError.invalidSession("Cursor access token is not a JWT.")
        }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CursorDashboardError.invalidSession(
                "Cursor access token has an invalid payload."
            )
        }
        return object
    }
}

struct CursorAppAuthStore {
    let databasePath: String

    init(databasePath: String? = nil) {
        self.databasePath = databasePath
            ?? ProcessInfo.processInfo.environment["CURSOR_STATE_DB"]
            ?? NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }

    func loadSession() throws -> CursorAppAuthSession {
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw CursorDashboardError.notInstalled
        }
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            databasePath,
            "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken' LIMIT 1;"
        ]
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw CursorDashboardError.invalidSession(
                "Cursor account database could not be read: \(message)"
            )
        }
        let token = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else { throw CursorDashboardError.notLoggedIn }
        return CursorAppAuthSession(accessToken: token)
    }
}
