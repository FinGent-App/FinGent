// Features/Portfolio/View/PortfolioCardView.swift

import SwiftUI

struct PortfolioCardView: View {
    let summary: PortfolioSummaryState
    let showSaved: Bool
    let onAddStock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow
            valueRow
            if summary.hasValue && summary.holdingCount > 0 {
                divider
                returnsRow
            }
        }
        .padding(24)
        .background { cardBackground }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title3)
                .foregroundStyle(.cyan)
            Text("Portfolio Hari Ini")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            liveBadge
            Spacer()
            if showSaved {
                Label("Tersimpan", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var valueRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(summary.displayValue)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(
                    summary.hasValue
                        ? AnyShapeStyle(LinearGradient(colors: [.white, .cyan.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(.white.opacity(0.4))
                )
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: summary.totalMarketValue)

            Spacer()
            addButton
        }
    }

    private var returnsRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Modal Investasi")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                Text(summary.totalInvestedText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Total Return")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                Text(summary.totalPnLText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(summary.isPnLProfit ? .green : .red)
                    .contentTransition(.numericText())
            }
        }
    }

    private var divider: some View {
        Divider()
            .background(.white.opacity(0.12))
            .padding(.vertical, 2)
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
                .shadow(color: .green.opacity(0.8), radius: 3)
            Text("LIVE IDX")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background {
            Capsule().fill(.green.opacity(0.15))
                .overlay { Capsule().stroke(.green.opacity(0.3), lineWidth: 0.5) }
        }
    }

    private var addButton: some View {
        Button(action: onAddStock) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: .cyan.opacity(0.4), radius: 8, x: 0, y: 3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tambah saham")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [.cyan.opacity(0.4), .purple.opacity(0.2), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
    }
}
