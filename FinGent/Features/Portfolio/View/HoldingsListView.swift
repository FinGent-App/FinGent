// Features/Portfolio/View/HoldingsListView.swift

import SwiftUI

// MARK: - Holdings List

struct HoldingsListView: View {
    let rows: [HoldingRowState]
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    HoldingRowView(row: row, onRemove: { onRemove(row.ticker) })
                }
            }
        }
    }

    private var header: some View {
        Text("Holdings")
            .font(.subheadline.bold())
            .foregroundStyle(Color.black)
    }
}

// MARK: - Single Holding Row

struct HoldingRowView: View {
    let row: HoldingRowState
    let onRemove: () -> Void

    private var holdingQuote: StockQuote {
        MarketDataRepository.shared.getQuote(for: row.ticker) ?? StockQuote(
            ticker: row.ticker,
            name: row.name,
            price: row.currentPrice,
            previousClose: row.currentPrice,
            open: row.currentPrice,
            high: row.currentPrice,
            low: row.currentPrice,
            volume: 0,
            currency: row.currency
        )
    }

    private var isDailyPositive: Bool {
        if let quote = MarketDataRepository.shared.getQuote(for: row.ticker) {
            return quote.change >= 0
        }
        return row.isDailyPositive
    }

    private var dailyChangePercent: Double {
        if let quote = MarketDataRepository.shared.getQuote(for: row.ticker) {
            return quote.changePercent
        }
        return row.dailyChangePercent
    }

    var body: some View {
        NavigationLink(value: holdingQuote) {
            HStack(spacing: 12) {
                // Ticker & Company Name
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.ticker)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)

                    Text(row.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Price & Change (1D like Watchlist)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(row.formattedPrice)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.25), value: row.currentPrice)

                    let isPositive = isDailyPositive
                    let sign = isPositive ? "+" : "-"
                    Text(String(format: "%@%.2f%%", sign, abs(dailyChangePercent)))
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
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onRemove) {
                Label("Hapus", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("Hapus dari Portofolio", systemImage: "trash")
            }
        }
    }
}

// MARK: - Empty Holdings

struct EmptyHoldingsView: View {
    let onAddStock: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 44))
                .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))

            VStack(spacing: 6) {
                Text("Mulai Tambahkan Saham")
                    .font(.headline)
                    .foregroundStyle(Color.black)
                Text("Tambahkan saham yang kamu miliki (misal: GOTO Rp 1.000.000, BBRI Rp 500.000) untuk memantau performa & portofolio secara otomatis.")
                    .font(.footnote)
                    .foregroundStyle(Color.black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Button(action: onAddStock) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Tambah Saham Pertama")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background {
                    Capsule()
                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1) }
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
