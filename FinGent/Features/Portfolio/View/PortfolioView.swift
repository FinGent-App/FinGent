// Features/Portfolio/View/PortfolioView.swift

import SwiftUI

struct PortfolioView: View {

    @State private var viewModel = AppContainer.shared.makePortfolioViewModel()
    @State private var portfolioRepo = PortfolioRepository.shared
    @State private var marketRepo = MarketDataRepository.shared

    @State private var showSaved: Bool = false
    @State private var showAddStock: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                scrollContent
            }
            .navigationTitle("Portfolio")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddStock = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .sheet(isPresented: $showAddStock) {
                AddStockSheetView(onSaved: handleSaved)
            }
            .navigationDestination(for: StockQuote.self) { quote in
                DetailPortfolioView(quote: quote)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: onAppear)
        .onChange(of: portfolioRepo.userHoldings) { _, _ in viewModel.refresh() }
    }

    // MARK: - Subviews

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                if !viewModel.userHoldings.isEmpty {
                    HoldingsListView(
                        rows: viewModel.holdingRows,
                        onRemove: { ticker in
                            withAnimation(.spring(response: 0.3)) {
                                viewModel.removeHolding(ticker: ticker)
                            }
                        }
                    )
                } else {
                    EmptyHoldingsView(onAddStock: { showAddStock = true })
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .refreshable {
            await portfolioRepo.syncWithBackend()
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

    // MARK: - Actions

    private func onAppear() {
        Task {
            await portfolioRepo.syncWithBackend()
        }
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
