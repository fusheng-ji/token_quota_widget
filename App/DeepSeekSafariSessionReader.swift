import AppKit
import Foundation

enum DeepSeekSafariSessionResult {
    case token(String)
    case notFound
    case unavailable(String)
}

@MainActor
enum DeepSeekSafariSessionReader {
    static func readToken() -> DeepSeekSafariSessionResult {
        guard !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.Safari"
        ).isEmpty else { return .notFound }

        let source = #"""
        tell application "Safari"
            repeat with browserWindow in windows
                repeat with browserTab in tabs of browserWindow
                    set tabURL to URL of browserTab
                    if tabURL starts with "https://platform.deepseek.com/" then
                        return do JavaScript "localStorage.getItem('userToken') || ''" in browserTab
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """#

        guard let script = NSAppleScript(source: source) else {
            return .unavailable("Could not prepare Safari session import.")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let detail = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Safari blocked automation."
            if detail.localizedCaseInsensitiveContains("JavaScript from Apple Events") {
                return .unavailable(
                    "In Safari Settings, enable Advanced → Show features for web developers, then Developer → Allow JavaScript from Apple Events."
                )
            }
            return .unavailable(
                "Safari session access was blocked. Allow AI Token Quota to control Safari in System Settings → Privacy & Security → Automation, then click Check now."
            )
        }
        guard let rawValue = result.stringValue,
              let token = DeepSeekCredentialStore.token(fromLocalStorageValue: rawValue)
        else { return .notFound }
        return .token(token)
    }
}
