// Features/Home/View/HomeView.swift

import SwiftUI

struct HomeView: View {

    @State private var viewModel: HomeViewModel
    @State private var favoritesRepo = FavoritesRepository.shared
    @State private var marketRepo = MarketDataRepository.shared

    var onSelectPortfolio: () -> Void = {}
    var onSelectChat: () -> Void = {}
    var onSelectSearch: () -> Void = {}

    init(
        viewModel: HomeViewModel,
        onSelectPortfolio: @escaping () -> Void = {},
        onSelectChat: @escaping () -> Void = {},
        onSelectSearch: @escaping () -> Void = {}
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.onSelectPortfolio = onSelectPortfolio
        self.onSelectChat = onSelectChat
        self.onSelectSearch = onSelectSearch
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                ScrollView {
                    VStack(spacing: 20) {
                        welcomeHeader
                        portfolioSnapshotCard
                        aiAssistantBanner
                        favoriteStocksSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: StockQuote.self) { quote in
                DetailPortfolioView(quote: quote)
                    .toolbar(.hidden, for: .tabBar)
            }
            .onAppear {
                viewModel.refresh()
            }
            .onChange(of: favoritesRepo.favorites) { _, _ in
                viewModel.refresh()
            }
            .onChange(of: marketRepo.lastTick) { _, _ in
                viewModel.refresh()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(hex: "0B0E14"), Color(hex: "101522"), Color(hex: "0B0E14")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var welcomeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Halo, \(viewModel.userName) 👋")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Pasar IDX Live")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var portfolioSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Portofolio Saya")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onSelectPortfolio) {
                    HStack(spacing: 4) {
                        Text("Lihat Detail")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.teal)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.formattedPortfolioValue)
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                let isProfit = viewModel.portfolioPnL >= 0
                let sign = isProfit ? "+" : "-"
                Text("\(sign)\(viewModel.formattedPnL) (\(String(format: "%@%.1f%%", sign, abs(viewModel.portfolioPnLPct))))")
                    .font(.caption.bold())
                    .foregroundStyle(isProfit ? .green : .red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((isProfit ? Color.green : Color.red).opacity(0.15), in: Capsule())
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.teal.opacity(0.2), lineWidth: 1))
        )
    }

    private var aiAssistantBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.white)
                .padding(10)
                .background(
                    LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("FinGent AI Assistant")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("Tanya analisis saham, risiko pasar, atau berita terkini.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onSelectChat) {
                Text("Tanya AI")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.teal, in: Capsule())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.teal.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.teal.opacity(0.3), lineWidth: 1))
        )
    }

    // MARK: - Favorite Stocks Section

    private var favoriteStocksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color(hex: "FFB800"))
                    Text("Saham Favorit")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }

                Spacer()

                if !viewModel.favoriteStocks.isEmpty {
                    Text("\(viewModel.favoriteStocks.count) Saham")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }

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
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 6)

            Text("Belum Ada Saham Favorit")
                .font(.subheadline.bold())
                .foregroundStyle(.white.opacity(0.85))

            Text("Buka detail saham dari pencarian atau portofolio, lalu ketuk ikon bintang di kanan atas untuk memantau di sini.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button(action: onSelectSearch) {
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
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                )
        )
    }

    private func favoriteStockRow(_ stock: StockQuote) -> some View {
        HStack(spacing: 12) {
            // Ticker & Company Name
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(stock.ticker)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    if stock.currency.uppercased() != "IDR" {
                        Text(stock.currency.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    }
                }

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
                    .foregroundStyle(.white)

                let isPositive = stock.change >= 0
                let sign = isPositive ? "+" : "-"
                Text(String(format: "%@%.2f%%", sign, abs(stock.changePercent)))
                    .font(.caption2.bold())
                    .foregroundStyle(isPositive ? Color(hex: "00D084") : Color(hex: "FF3B30"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (isPositive ? Color(hex: "00D084") : Color(hex: "FF3B30")).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
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

// MARK: - Color Extension Helper

private extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
