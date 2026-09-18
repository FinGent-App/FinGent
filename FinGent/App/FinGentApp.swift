// App/FinGentApp.swift

import SwiftUI
import AppIntents

@main
struct FinGentApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .task {
                    Task.detached(priority: .background) {
                        FinGentShortcuts.updateAppShortcutParameters()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task {
                            await MarketDataRepository.shared.refreshFromBackend()
                            await PortfolioRepository.shared.syncWithBackend()
                            await FavoritesRepository.shared.syncWithBackend()
                        }
                    }
                }
        }
    }
}
