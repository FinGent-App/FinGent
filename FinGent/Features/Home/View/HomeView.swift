// Features/Home/View/HomeView.swift

import SwiftUI

struct HomeView: View {

    @State private var viewModel: HomeViewModel
    @State private var selectedMoverTab: Int = 0
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
                        ihsgIndexCard
                        portfolioSnapshotCard
                        aiAssistantBanner
                        marketMoversSection
                        breakingNewsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                            .foregroundStyle(.teal)
                            .font(.title3)
                        Text("FinGent")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onSelectChat) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.teal)
                            .font(.subheadline.bold())
                            .padding(8)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }
                }
            }
            .onAppear {
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

    private var ihsgIndexCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Indeks Harga Saham Gabungan (IHSG)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(NumberFormatters.stockPrice(viewModel.ihsgPrice))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                    Text("+\(String(format: "%.2f", viewModel.ihsgChange)) (+\(String(format: "%.2f", viewModel.ihsgChangePercent))%)")
                }
                .font(.caption.bold())
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.15), in: Capsule())
            }

            // Simulated Mini Sparkline chart
            HStack(alignment: .bottom, spacing: 5) {
                ForEach([35, 42, 38, 55, 62, 58, 70, 68, 75, 82, 80, 92], id: \.self) { val in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [.teal, .green], startPoint: .bottom, endPoint: .top))
                        .frame(height: CGFloat(val) * 0.45)
                }
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
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

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NumberFormatters.rupiah(viewModel.portfolioValue))
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("\(viewModel.userHoldingsCount) Saham Aktif")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                let pnl = viewModel.portfolioPnL
                let isProfit = pnl >= 0
                HStack(spacing: 4) {
                    Image(systemName: isProfit ? "arrow.up.right" : "arrow.down.right")
                    Text("\(isProfit ? "+" : "")\(NumberFormatters.compact(abs(pnl))) (\(String(format: "%+.1f", viewModel.portfolioPnLPct))%)")
                }
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

    private var marketMoversSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Penggerak Pasar (Movers)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                Picker("Movers", selection: $selectedMoverTab) {
                    Text("Top Gainers").tag(0)
                    Text("Top Losers").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            let movers = selectedMoverTab == 0 ? viewModel.topGainers : viewModel.topLosers
            ForEach(movers.prefix(4), id: \.ticker) { mover in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mover.ticker)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(mover.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Rp \(NumberFormatters.stockPrice(mover.price))")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        let isPositive = mover.changePercent >= 0
                        Text(String(format: "%+.2f%%", mover.changePercent))
                            .font(.caption2.bold())
                            .foregroundStyle(isPositive ? .green : .red)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var breakingNewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Berita Pasar Terkini")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onSelectSearch) {
                    Text("Cari Lainnya")
                        .font(.caption.bold())
                        .foregroundStyle(.teal)
                }
            }

            ForEach(viewModel.latestNews) { article in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(article.sentiment.emoji)
                        Text(article.source)
                            .font(.caption2.bold())
                            .foregroundStyle(.teal)
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(article.date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    Text(article.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(article.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                )
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
