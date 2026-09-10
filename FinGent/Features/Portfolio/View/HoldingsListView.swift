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
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.rectangle.fill")
                .font(.subheadline)
                .foregroundStyle(.cyan)
            Text("Holdings")
                .font(.subheadline.bold())
                .foregroundStyle(Color.black)
        }
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

    var body: some View {
        NavigationLink(value: holdingQuote) {
            HStack(spacing: 12) {
                tickerBadge
                stockDetails
                Spacer()
                valueAndPnL
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Color.black.opacity(0.3))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.35))
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onRemove) {
                Label("Hapus", systemImage: "trash")
            }
        }
    }

    private var tickerBadge: some View {
        Text(row.ticker)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(row.isProfit ? Color(red: 0.05, green: 0.45, blue: 0.2) : Color(red: 0.65, green: 0.12, blue: 0.15))
            .frame(width: 52, height: 36)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: row.isProfit
                            ? [.green.opacity(0.3), .green.opacity(0.15)]
                            : [.red.opacity(0.3), .red.opacity(0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            }
    }

    private var stockDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.black)
                .lineLimit(1)

            Text("\(row.lotText) · \(row.formattedPrice)")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.55))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: row.currentPrice)
        }
    }

    private var valueAndPnL: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(row.formattedValue)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.25), value: row.currentValue)

            Text(row.formattedPnlPercent)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(row.isProfit ? Color(red: 0.0, green: 0.55, blue: 0.25) : Color(red: 0.85, green: 0.15, blue: 0.15))
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
