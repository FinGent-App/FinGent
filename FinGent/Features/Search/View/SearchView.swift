// Features/Search/View/SearchView.swift

import SwiftUI

struct SearchView: View {

    @State private var viewModel: SearchViewModel
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(viewModel: SearchViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                VStack(spacing: 0) {
                    searchBarHeader
                    Divider()
                    stocksList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: StockQuote.self) { quote in
                DetailPortfolioView(quote: quote)
                    .toolbar(.hidden, for: .tabBar)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Keyboard langsung muncul saat sheet terbuka
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
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
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Cari sesuatu...", text: $viewModel.query)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(.white)

                if viewModel.isSearching {
                    ProgressView()
                        .tint(.teal)
                        .scaleEffect(0.8)
                } else if !viewModel.query.isEmpty {
                    Button {
                        viewModel.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            Button("Batal") {
                dismiss()
            }
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
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
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Ketik untuk mencari")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
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
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Tidak ada hasil untuk \"\(viewModel.query)\"")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
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
