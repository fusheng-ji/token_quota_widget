import SwiftUI

@main
struct CodexWeekApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            UsageMenuView(store: store)
        } label: {
            Label(store.menuBarText, systemImage: "bolt.horizontal.circle.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
