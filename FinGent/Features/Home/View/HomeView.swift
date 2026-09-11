// Features/Home/View/HomeView.swift

import SwiftUI

struct HomeView: View {

    @State private var viewModel: HomeViewModel
    @State private var favoritesRepo = FavoritesRepository.shared
    @State private var marketRepo = MarketDataRepository.shared
    @State private var portfolioRepo = PortfolioRepository.shared
    @State private var showSearch = false
    @State private var showProfile = false
    @State private var showAddStock = false
    @State private var navigateToChat = false

    var onSelectChat: () -> Void = {}
    var onSelectSearch: (() -> Void)? = nil

    init(
        viewModel: HomeViewModel,
        onSelectChat: @escaping () -> Void = {},
        onSelectSearch: (() -> Void)? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.onSelectChat = onSelectChat
        self.onSelectSearch = onSelectSearch
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                backgroundView
                ScrollView {
                    VStack(spacing: 20) {
                        welcomeHeader
                        portfolioSnapshotCard
                        holdingsSection
                        favoriteStocksSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
                .refreshable {
                    await portfolioRepo.syncWithBackend()
                    viewModel.refresh()
                }

                customTabBar
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 0) {
                        Button {
                            showSearch = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }

                        Button {
                            showProfile = true
                        } label: {
                            Image(systemName: "person.circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .sheet(isPresented: $showSearch) {
                SearchView(viewModel: AppContainer.shared.makeSearchViewModel())
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showProfile) {
                ProfileView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showAddStock) {
                AddStockSheetView {
                    viewModel.refresh()
                }
            }
            .navigationDestination(isPresented: $navigateToChat) {
                ChatView()
            }
            .navigationDestination(for: StockQuote.self) { quote in
                DetailPortfolioView(quote: quote)
                    .toolbar(.hidden, for: .tabBar)
            }
            .onAppear {
                viewModel.refresh()
                Task {
                    await portfolioRepo.syncWithBackend()
                }
            }
            .onChange(of: portfolioRepo.userHoldings) { _, _ in
                viewModel.refresh()
            }
            .onChange(of: favoritesRepo.favorites) { _, _ in
                viewModel.refresh()
            }
            .onChange(of: marketRepo.lastTick) { _, _ in
                viewModel.refresh()
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Subviews

    private var backgroundView: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: "DFE4EE"), Color(hex: "D7DDE7")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Circle 1 — biru
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "C9E7FB").opacity(1.0),
                            Color(hex: "C9E7FB").opacity(0.8),
                            Color(hex: "C9E7FB").opacity(0.0),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .blur(radius: 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .offset(x: 100, y: -200)

            // Circle 2 — ungu
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: "CDCAFC").opacity(1.0),
                            Color(hex: "CDCAFC").opacity(0.8),
                            Color(hex: "CDCAFC").opacity(0.0),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .blur(radius: 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: 80, y: -180)
        }
        .ignoresSafeArea()
    }

    private var welcomeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your AI-Powered\nInvestment Assistant!")
                    .font(.custom("Inter", size: 24).weight(.bold))
                    .lineSpacing(8)
                    .foregroundStyle(Color.black)

                Text("Invest Smarter. Stay Informed.")
                    .font(.custom("Inter", size: 16).weight(.semibold))
                    .foregroundStyle(Color(hex: "8E8E8E"))
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var portfolioSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Portofolio Saya")
                .font(.subheadline.bold())
                .foregroundStyle(Color.black.opacity(0.8))

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.formattedPortfolioValue)
                    .font(.title2.bold())
                    .foregroundStyle(Color.black)

                let isProfit = viewModel.portfolioPnL >= 0
                let sign = isProfit ? "+" : "-"
                Text("\(sign)\(viewModel.formattedPnL) (\(String(format: "%@%.1f%%", sign, abs(viewModel.portfolioPnLPct))))")
                    .font(.caption.bold())
                    .foregroundStyle(isProfit ? Color(hex: "00B89F") : Color(hex: "FF3B30"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((isProfit ? Color(hex: "00B89F") : Color(hex: "FF3B30")).opacity(0.15), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.teal.opacity(0.2), lineWidth: 1))
        )
    }

    private var holdingsSection: some View {
        Group {
            if !viewModel.holdingRows.isEmpty {
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
    }

    // MARK: - Custom Tab Bar

    private let circleDiameter: CGFloat = 44

    private var customTabBar: some View {
        ZStack(alignment: .bottom) {
            // Layer 1: Tab bar custom background (z-index 0)
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: circleDiameter / 2)

                customTabBarBackground
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .background(
                customTabBarBackground
                    .padding(.top, circleDiameter / 2)
                    .ignoresSafeArea(edges: .bottom)
            )
            .zIndex(0)

            // Layer 2: Lingkaran gradient ungu besar di bawah (z-index 1, di atas tab bar custom)
            bottomPurpleGlowCircle
                .zIndex(1)

            // Layer 3: Circle bawah tengah (z-index 2, di atas lingkaran ungu)
            VStack(spacing: 0) {
                bottomChatButton
                Spacer()
            }
            .frame(height: circleDiameter / 2 + 52)
            .zIndex(2)
        }
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .bottom)
    }

    private var bottomPurpleGlowCircle: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hex: "B285FF").opacity(1.0),
                        Color(hex: "B285FF").opacity(1.0),
                        Color(hex: "B285FF").opacity(0.0),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 150
                )
            )
            .frame(width: 300, height: 300)
            .blur(radius: 80)
            .offset(y: 250)
            .allowsHitTesting(false)
    }

    private var customTabBarBackground: some View {
        ZStack {
            // Progressive Material Blur (tebal di bawah, pudar semakin ke atas)
            Rectangle()
                .fill(.regularMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black.opacity(0.85), location: 0.35),
                            .init(color: .black.opacity(0.4), location: 0.7),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )

            // Progressive White Tint (putih pekat di bawah, semakin pudar ke atas)
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.96), location: 0.0),
                    .init(color: Color.white.opacity(0.88), location: 0.35),
                    .init(color: Color.white.opacity(0.50), location: 0.70),
                    .init(color: Color.white.opacity(0.0), location: 1.0)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
        }
        .allowsHitTesting(false)
    }

    private var bottomChatButton: some View {
        Button {
            navigateToChat = true
        } label: {
            Circle()
                .fill(Color.white)
                .frame(width: circleDiameter, height: circleDiameter)
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }


    // MARK: - Favorite Stocks Section

    private var favoriteStocksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favorites")
                .font(.subheadline.bold())
                .foregroundStyle(Color.black)

            if viewModel.favoriteStocks.isEmpty {
                emptyFavoritesCard
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.favoriteStocks) { stock in
                        NavigationLink(value: stock) {
                            favoriteStockRow(stock)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyFavoritesCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.slash")
                .font(.system(size: 30))
                .foregroundStyle(Color.black.opacity(0.3))
                .padding(.top, 6)

            Text("Belum Ada Saham Favorit")
                .font(.subheadline.bold())
                .foregroundStyle(Color.black)

            Text("Buka detail saham dari pencarian atau portofolio, lalu ketuk ikon bintang di kanan atas untuk memantau di sini.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button {
                if let onSelectSearch {
                    onSelectSearch()
                } else {
                    showSearch = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Cari Saham")
                }
                .font(.caption.bold())
                .foregroundStyle(.cyan)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.cyan.opacity(0.15), in: Capsule())
            }
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.black.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                )
        )
    }

    private func favoriteStockRow(_ stock: StockQuote) -> some View {
        HStack(spacing: 12) {
            // Ticker & Company Name
            VStack(alignment: .leading, spacing: 3) {
                Text(stock.ticker)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.black)

                Text(stock.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Price & Change
            VStack(alignment: .trailing, spacing: 3) {
                Text(stock.formattedPrice)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black)

                let isPositive = stock.change >= 0
                let sign = isPositive ? "+" : "-"
                Text(String(format: "%@%.2f%%", sign, abs(stock.changePercent)))
                    .font(.caption2.bold())
                    .foregroundStyle(isPositive ? Color(hex: "00B89F") : Color(hex: "FF3B30"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (isPositive ? Color(hex: "00B89F") : Color(hex: "FF3B30")).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
        )
        .contextMenu {
            Button(role: .destructive) {
                withAnimation {
                    viewModel.removeFavorite(ticker: stock.ticker)
                }
            } label: {
                Label("Hapus dari Favorit", systemImage: "star.slash")
            }
        }
    }
}

// Helper extension untuk hex color
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
