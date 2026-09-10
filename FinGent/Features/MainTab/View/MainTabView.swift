// Features/MainTab/View/MainTabView.swift

import SwiftUI

enum TabItem: Int, CaseIterable, Identifiable {
    case home = 0
    case chat = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .chat: return "AI Chat"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .chat: return "sparkles"
        }
    }
}

struct MainTabView: View {
    var body: some View {
        HomeView(
            viewModel: AppContainer.shared.makeHomeViewModel()
        )
        .preferredColorScheme(.light)
    }
}

#Preview {
    MainTabView()
}
