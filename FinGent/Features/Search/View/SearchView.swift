// Features/Search/View/SearchView.swift

import SwiftUI

struct SearchView: View {

    @State private var viewModel: SearchViewModel
    @State private var showDetailSheet: Bool = false
    @State private var showAddSuccessAlert: Bool = false
    @State private var addedStockTicker: String = ""

    init(viewModel: SearchViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                VStack(spacing: 12) {
                    searchBarHeader
                    scopePicker
                    if viewModel.scope == .stocks {
                        sectorChips
                        stocksList
                    } else {
                        newsList
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("Eksplorasi Pasar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showDetailSheet) {
                if let quote = viewModel.selectedDetailQuote {
                    stockDetailSheet(quote: quote)
                }
            }
            .alert("Berhasil Ditambahkan!", isPresented: $showAddSuccessAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(addedStockTicker) telah ditambahkan ke portofolio Anda senilai Rp 10.000.000.")
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
            TextField("Cari ticker (BBCA) atau perusahaan...", text: $viewModel.query)
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
            if !viewModel.query.isEmpty {
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

    private var scopePicker: some View {
        Picker("Scope", selection: $viewModel.scope) {
            ForEach(SearchScope.allCases, id: \.self) { s in
                Text(s.rawValue).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    private var sectorChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.sectors, id: \.self) { sector in
                    let isSelected = viewModel.selectedSector == sector
                    Button(action: { viewModel.selectedSector = sector }) {
                        Text(sector)
                            .font(.caption.bold())
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.teal : Color.white.opacity(0.08), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var stocksList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if viewModel.filteredQuotes.isEmpty {
                    emptyState(title: "Saham Tidak Ditemukan", message: "Coba cari dengan simbol ticker lain seperti BBCA, TLKM, atau GOTO.")
                } else {
                    ForEach(viewModel.filteredQuotes, id: \.ticker) { quote in
                        stockRow(quote: quote)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
    }

    private func stockRow(quote: StockQuote) -> some View {
        Button(action: {
            viewModel.selectStock(quote)
            showDetailSheet = true
        }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(quote.ticker)
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                        if let sector = viewModel.selectedDetailFundamentals?.sector {
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
                    Text("Rp \(NumberFormatters.stockPrice(quote.price))")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    let isPositive = quote.changePercent >= 0
                    HStack(spacing: 2) {
                        Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                        Text(String(format: "%+.2f%%", quote.changePercent))
                    }
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

    private var newsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if viewModel.filteredNews.isEmpty {
                    emptyState(title: "Berita Tidak Ditemukan", message: "Tidak ada berita dengan kata kunci '\(viewModel.query)'.")
                } else {
                    ForEach(viewModel.filteredNews) { article in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(article.sentiment.emoji)
                                Text(article.source)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.teal)
                                Spacer()
                                Text(article.date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(article.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            Text(article.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)

                            HStack(spacing: 4) {
                                ForEach(article.relatedTickers, id: \.self) { ticker in
                                    Text(ticker)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.teal)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.teal.opacity(0.15), in: Capsule())
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .padding(.top, 40)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Stock Detail Sheet

    private func stockDetailSheet(quote: StockQuote) -> some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Title & Price
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(quote.ticker)
                                    .font(.title.bold())
                                    .foregroundStyle(.white)
                                Text(quote.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Rp \(NumberFormatters.stockPrice(quote.price))")
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                                let isPositive = quote.changePercent >= 0
                                Text(String(format: "%+.2f%% (Rp %+.0f)", quote.changePercent, quote.change))
                                    .font(.caption.bold())
                                    .foregroundStyle(isPositive ? .green : .red)
                            }
                        }

                        Divider().background(Color.white.opacity(0.1))

                        // Fundamentals Grid
                        if let fund = viewModel.selectedDetailFundamentals {
                            Text("Fundamental Emiten")
                                .font(.headline.bold())
                                .foregroundStyle(.white)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                metricTile(title: "P/E Ratio", value: String(format: "%.1fx", fund.peRatio))
                                metricTile(title: "PBV Ratio", value: String(format: "%.1fx", fund.pbvRatio))
                                metricTile(title: "ROE", value: String(format: "%.1f%%", fund.roe))
                                metricTile(title: "Market Cap", value: "Rp \(NumberFormatters.compact(fund.marketCap * 1_000_000_000_000))")
                                metricTile(title: "Dividend Yield", value: String(format: "%.1f%%", fund.dividendYield))
                                metricTile(title: "Sektor", value: fund.sector)
                            }
                        }

                        // Performance
                        if let perf = viewModel.selectedDetailPerformance {
                            Text("Performa Historis")
                                .font(.headline.bold())
                                .foregroundStyle(.white)

                            HStack(spacing: 8) {
                                perfChip(label: "1D", val: perf.daily)
                                perfChip(label: "1W", val: perf.weekly)
                                perfChip(label: "1M", val: perf.monthly)
                                perfChip(label: "YTD", val: perf.ytd)
                                perfChip(label: "1Y", val: perf.yearly)
                            }
                        }

                        Spacer(minLength: 20)

                        // Action Button
                        Button(action: {
                            viewModel.addStockToPortfolio(ticker: quote.ticker, amount: 10_000_000)
                            addedStockTicker = quote.ticker
                            showDetailSheet = false
                            showAddSuccessAlert = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Beli & Tambah ke Portofolio (Rp 10jt)")
                            }
                            .font(.headline.bold())
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.teal, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Detail Saham")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tutup") { showDetailSheet = false }
                        .foregroundStyle(.teal)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func perfChip(label: String, val: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%+.1f%%", val))
                .font(.caption.bold())
                .foregroundStyle(val >= 0 ? .green : .red)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
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
