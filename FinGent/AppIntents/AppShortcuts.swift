// AppIntents/AppShortcuts.swift

import AppIntents

struct FinGentShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CekSahamIntent(),
            phrases: [
                "How about my \(\.$stock) in \(.applicationName)",
                "How about my \(\.$stock) today in \(.applicationName)",
                "How is my \(\.$stock) in \(.applicationName)",
                "How's my \(\.$stock) in \(.applicationName)",
                "Check my \(\.$stock) in \(.applicationName)",
                "Check my \(\.$stock) stock in \(.applicationName)",
                "What about my \(\.$stock) in \(.applicationName)",
                "Ask \(.applicationName) about my \(\.$stock)",
                "Ask \(.applicationName) how is my \(\.$stock)"
            ],
            shortTitle: "Check Stock",
            systemImageName: "magnifyingglass"
        )

        AppShortcut(
            intent: AskFinGentIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Talk to \(.applicationName)",
                "Chat with \(.applicationName)",
                "Query \(.applicationName)"
            ],
            shortTitle: "Ask FinGent AI",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: CekPortfolioIntent(),
            phrases: [
                "Check my portfolio in \(.applicationName)",
                "Check my \(.applicationName) portfolio",
                "How is my portfolio in \(.applicationName)",
                "Show my portfolio in \(.applicationName)",
                "\(.applicationName) portfolio",
                "My \(.applicationName) portfolio"
            ],
            shortTitle: "Check Portfolio",
            systemImageName: "chart.line.uptrend.xyaxis"
        )

        AppShortcut(
            intent: CekBeritaIntent(),
            phrases: [
                "Is there any news about my \(\.$stock) in \(.applicationName)",
                "Is there any news about my \(\.$stock) today in \(.applicationName)",
                "Is there any news about my \(\.$stock) today's in \(.applicationName)",
                "Any news about \(\.$stock) in \(.applicationName)",
                "Any news about \(\.$stock) today in \(.applicationName)",
                "News about \(\.$stock) in \(.applicationName)",
                "Latest news about \(\.$stock) in \(.applicationName)",
                "Check news for \(\.$stock) in \(.applicationName)",
                "Check my \(\.$stock) news in \(.applicationName)",
                "What's the news on \(\.$stock) in \(.applicationName)"
            ],
            shortTitle: "Stock News",
            systemImageName: "newspaper"
        )
    }
}
