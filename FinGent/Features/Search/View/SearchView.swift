// Features/Search/View/SearchView.swift

import SwiftUI

struct SearchView: View {

    @State private var viewModel: SearchViewModel

    init(viewModel: SearchViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                VStack(spacing: 12) {
                    searchBarHeader
                    stocksList
                }
                .padding(.top, 8)
            }
            .navigationTitle("Cari Saham")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(for: StockQuote.self) { quote in
                DetailPortfolioView(quote: quote)
                    .toolbar(.hidden, for: .tabBar)
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

    private var searchBarHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Cari emiten atau ticker (misal: Micron, Apple, BBCA)...", text: $viewModel.query)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if viewModel.isSearching {
                ProgressView()
                    .tint(.teal)
                    .scaleEffect(0.8)
            } else if !viewModel.query.isEmpty {
                Button(action: { viewModel.query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private var stocksList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if viewModel.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    emptyPromptState
                } else if viewModel.isSearching && viewModel.filteredQuotes.isEmpty {
                    searchingState
                } else if viewModel.filteredQuotes.isEmpty {
                    emptyNotFoundState
                } else {
                    ForEach(viewModel.filteredQuotes, id: \.ticker) { quote in
                        stockRow(quote: quote)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    private func stockRow(quote: StockQuote) -> some View {
        NavigationLink(value: quote) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(quote.ticker)
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                        if let sector = viewModel.sector(for: quote.ticker) {
                            Text(sector)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.teal)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.teal.opacity(0.15), in: Capsule())
                        }
                    }
                    Text(quote.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(quote.formattedPrice)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    let isPositive = quote.changePercent >= 0
                    Text(String(format: "%+.2f%%", quote.changePercent))
                        .font(.caption2.bold())
                        .foregroundStyle(isPositive ? .green : .red)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(14)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyPromptState: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.6))
                .padding(.top, 60)

            Text("Cari Saham")
                .font(.headline.bold())
                .foregroundStyle(.white)

            Text("Ketik nama perusahaan atau simbol ticker (misal: Micron, Apple, BBCA, MU) untuk melihat data harga real-time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }

    private var searchingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.teal)
                .scaleEffect(1.2)
                .padding(.top, 50)

            Text("Mengambil data harga real-time...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyNotFoundState: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.6))
                .padding(.top, 50)

            Text("Saham Tidak Ditemukan")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Tidak ditemukan hasil untuk '\(viewModel.query)'. Coba periksa kembali nama perusahaan atau simbol ticker.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
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
