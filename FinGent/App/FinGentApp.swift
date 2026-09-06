// App/FinGentApp.swift

import SwiftUI
import AppIntents

@main
struct FinGentApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .task {
                    Task.detached(priority: .background) {
                        FinGentShortcuts.updateAppShortcutParameters()
                    }
                }
        }
    }
}
