// Features/MainTab/View/MainTabView.swift

import SwiftUI

enum TabItem: Int, CaseIterable, Identifiable {
    case home = 0
    case portfolio = 1
    case search = 2
    case chat = 3
    case profile = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .portfolio: return "Portfolio"
        case .search: return "Search"
        case .chat: return "AI Chat"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .portfolio: return "chart.pie.fill"
        case .search: return "magnifyingglass"
        case .chat: return "sparkles"
        case .profile: return "person.crop.circle.fill"
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
                onSelectChat: { selectedTab = .chat },
                onSelectSearch: { selectedTab = .search }
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

            SearchView(viewModel: AppContainer.shared.makeSearchViewModel())
                .tabItem {
                    Label(TabItem.search.title, systemImage: TabItem.search.icon)
                }
                .tag(TabItem.search)

            ChatView()
                .tabItem {
                    Label(TabItem.chat.title, systemImage: TabItem.chat.icon)
                }
                .tag(TabItem.chat)

            ProfileView()
                .tabItem {
                    Label(TabItem.profile.title, systemImage: TabItem.profile.icon)
                }
                .tag(TabItem.profile)
        }
        .tint(Color(red: 0.0, green: 0.82, blue: 0.61))
        .preferredColorScheme(.dark)
    }
}

#Preview {
    MainTabView()
}
