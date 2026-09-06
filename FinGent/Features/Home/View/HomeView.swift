// Features/Home/View/HomeView.swift

import SwiftUI

struct HomeView: View {

    @State private var viewModel: HomeViewModel
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
