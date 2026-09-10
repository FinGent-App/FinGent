// Features/MainTab/View/MainTabView.swift

import SwiftUI

enum TabItem: Int, CaseIterable, Identifiable {
    case home = 0
    case portfolio = 1
    case chat = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .portfolio: return "Portfolio"
        case .chat: return "AI Chat"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .portfolio: return "chart.pie.fill"
        case .chat: return "sparkles"
        }
    }
}

struct MainTabView: View {

    @State private var selectedTab: TabItem = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                viewModel: AppContainer.shared.makeHomeViewModel(),
                onSelectPortfolio: { selectedTab = .portfolio },
                onSelectChat: { selectedTab = .chat }
            )
            .tabItem {
                Label(TabItem.home.title, systemImage: TabItem.home.icon)
            }
            .tag(TabItem.home)

            PortfolioView()
                .tabItem {
                    Label(TabItem.portfolio.title, systemImage: TabItem.portfolio.icon)
                }
                .tag(TabItem.portfolio)

            ChatView()
                .tabItem {
                    Label(TabItem.chat.title, systemImage: TabItem.chat.icon)
                }
                .tag(TabItem.chat)
        }
        .tint(Color(red: 0.0, green: 0.82, blue: 0.61))
        .preferredColorScheme(.dark)
    }
}

#Preview {
    MainTabView()
}
