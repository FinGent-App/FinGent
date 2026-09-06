// Features/Portfolio/View/PortfolioView.swift

import SwiftUI

struct PortfolioView: View {

    @State private var viewModel = AppContainer.shared.makePortfolioViewModel()
    @State private var portfolioRepo = PortfolioRepository.shared
    @State private var marketRepo = MarketDataRepository.shared

    @State private var nameText: String = ""
    @State private var showSaved: Bool = false
    @State private var showAddStock: Bool = false
    @State private var showAIChat: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                scrollContent
            }
            .navigationTitle("FinGent")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { aiChatToolbarButton }
            .sheet(isPresented: $showAddStock) {
                AddStockSheetView(onSaved: handleSaved)
            }
            .sheet(isPresented: $showAIChat) {
                FinGentChatSheetView()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: onAppear)
        .onChange(of: portfolioRepo.userHoldings) { _, _ in viewModel.refresh() }
        .onChange(of: marketRepo.lastTick) { _, _ in viewModel.refresh() }
    }

    // MARK: - Subviews

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                PortfolioCardView(
                    summary: viewModel.summary,
                    showSaved: showSaved,
                    onAddStock: { showAddStock = true }
                )

                if viewModel.userHoldings.isEmpty {
                    EmptyHoldingsView(onAddStock: { showAddStock = true })
                } else {
                    HoldingsListView(
                        rows: viewModel.holdingRows,
                        onRemove: { ticker in
                            withAnimation(.spring(response: 0.3)) {
                                viewModel.removeHolding(ticker: ticker)
                            }
                        }
                    )
                }

                NameSectionView(
                    nameText: $nameText,
                    onNameChanged: { viewModel.updateUserName($0) }
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.06, blue: 0.15),
                Color(red: 0.10, green: 0.08, blue: 0.22),
                Color(red: 0.05, green: 0.05, blue: 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    @ToolbarContentBuilder
    private var aiChatToolbarButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showAIChat = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                    Text("Tanya AI")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                        .shadow(color: .cyan.opacity(0.35), radius: 6, x: 0, y: 2)
                }
            }
        }
    }

    // MARK: - Actions

    private func onAppear() {
        nameText = viewModel.userName
        viewModel.startMarketSimulation()
    }

    private func handleSaved() {
        viewModel.refresh()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { showSaved = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { showSaved = false }
        }
    }
}

typealias ContentView = PortfolioView
