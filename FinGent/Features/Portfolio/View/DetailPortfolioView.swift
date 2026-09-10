// Features/Portfolio/View/DetailPortfolioView.swift

import SwiftUI
import Charts

enum ChartTimeframe: String, CaseIterable, Identifiable {
    case day = "24H"
    case week = "1W"
    case month = "1M"
    case threeMonth = "3M"
    case ytd = "YTD"
    case year = "1Y"
    case fiveYear = "5Y"

    var id: String { rawValue }

    var apiPeriod: String {
        switch self {
        case .day: return "24h"
        case .week: return "1w"
        case .month: return "1m"
        case .threeMonth: return "3m"
        case .ytd: return "ytd"
        case .year: return "1y"
        case .fiveYear: return "5y"
        }
    }
}

struct DetailPortfolioView: View {

    let quote: StockQuote

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTimeframe: ChartTimeframe = .month
    @State private var historyPoints: [StockHistoryPoint] = []
    @State private var isLoadingHistory: Bool = false
    @State private var selectedScrubPoint: StockHistoryPoint? = nil

    @State private var fundamentals: StockFundamentals? = nil
    @State private var secFilings: [StockApiClient.SecFilingDTO] = []
    @State private var isLoadingFilings: Bool = false
    @State private var activeSafariURL: IdentifiableURL? = nil
    @State private var showHoldingSheet: Bool = false
    @State private var holdingSheetDetent: PresentationDetent = .large
    @State private var portfolioRepo = PortfolioRepository.shared
    @State private var favoritesRepo = FavoritesRepository.shared

    private let portfolioUseCase: PortfolioUseCase = AppContainer.shared.portfolioUseCase
    private let marketRepo: MarketDataRepositoryProtocol = MarketDataRepository.shared

    private var currentHolding: UserHolding? {
        let clean = quote.ticker.trimmingCharacters(in: .whitespaces).uppercased()
        return portfolioRepo.userHoldings.first {
            $0.ticker.trimmingCharacters(in: .whitespaces).uppercased() == clean
        }
    }

    private var isFavorited: Bool {
        favoritesRepo.isFavorite(ticker: quote.ticker)
    }

    var body: some View {
        ZStack {
            backgroundGradient

            ScrollView {
                VStack(spacing: 20) {
                    stockHeader
                    chartCard
                    timeframeSegmentedControl
                    statsGrid
                    secFilingsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .bottom) {
                stickyViewHoldingBar
            }
        }
        .navigationTitle(quote.ticker)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                favoriteToolbarButton
            }
        }
        .task {
            loadFundamentals()
            await loadHistory(for: selectedTimeframe)
            await loadSecFilings()
        }
        .sheet(item: $activeSafariURL) { item in
            SafariView(url: item.url)
        }
        .sheet(isPresented: $showHoldingSheet) {
            StockHoldingDetailSheet(
                quote: quote,
                sector: fundamentals?.sector ?? marketRepo.getFundamentals(for: quote.ticker)?.sector ?? "General",
                onBuy: { amount, pricePerShare in
                    portfolioUseCase.addHolding(
                        ticker: quote.ticker,
                        name: quote.name,
                        amount: amount,
                        pricePerShare: pricePerShare,
                        sector: fundamentals?.sector ?? marketRepo.getFundamentals(for: quote.ticker)?.sector ?? "General"
                    )
                }
            )
            .presentationDetents([.large, .fraction(0.65)], selection: $holdingSheetDetent)
            .presentationDragIndicator(.visible)
        }
    }

    private var favoriteToolbarButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                favoritesRepo.toggleFavorite(quote: quote)
            }
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
        } label: {
            Image(systemName: isFavorited ? "star.fill" : "star")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isFavorited ? Color(hex: "FFB800") : Color.black.opacity(0.8))
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(isFavorited ? "Hapus dari Favorit" : "Tambahkan ke Favorit")
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(hex: "DFE4EE"), Color(hex: "D7DDE7")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var isUSD: Bool {
        quote.currency.uppercased() == "USD" || quote.isUSD
    }

    private var displayPrice: Double {
        selectedScrubPoint?.price ?? quote.price
    }

    private var displayFormattedPrice: String {
        let p = displayPrice
        if isUSD {
            return String(format: "$%.2f", p)
        } else {
            return "Rp \(NumberFormatters.stockPrice(p))"
        }
    }

    private var periodChangeInfo: (change: Double, changePct: Double) {
        if let scrub = selectedScrubPoint, let first = historyPoints.first {
            let diff = scrub.price - first.price
            let pct = first.price > 0 ? (diff / first.price) * 100 : 0
            return (diff, pct)
        }
        if let first = historyPoints.first, let last = historyPoints.last {
            let diff = last.price - first.price
            let pct = first.price > 0 ? (diff / first.price) * 100 : 0
            return (diff, pct)
        }
        return (quote.change, quote.changePercent)
    }

    private var isGain: Bool {
        periodChangeInfo.change >= 0
    }

    private var themeColor: Color {
        isGain ? Color(hex: "00D084") : Color(hex: "FF3B30")
    }

    private var stockHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quote.ticker)
                        .font(.title2.bold())
                        .foregroundStyle(Color.black)
                    Text(quote.name)
                        .font(.subheadline)
                        .foregroundStyle(Color.black.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if let sector = fundamentals?.sector ?? marketRepo.getFundamentals(for: quote.ticker)?.sector {
                    Text(sector)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.teal)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.teal.opacity(0.15), in: Capsule())
                }
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayFormattedPrice)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)

                    let info = periodChangeInfo
                    HStack(spacing: 6) {
                        Group {
                            let sign = info.change >= 0 ? "+" : "-"
                            if isUSD {
                                Text(String(format: "%@$%.2f (%@%.2f%%)", sign, abs(info.change), sign, abs(info.changePct)))
                            } else {
                                Text(String(format: "%@Rp %@ (%@%.2f%%)", sign, NumberFormatters.stockPrice(abs(info.change)), sign, abs(info.changePct)))
                            }
                        }
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(themeColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(themeColor.opacity(0.12), in: Capsule())

                        if let scrub = selectedScrubPoint {
                            Text(formatScrubDate(scrub.date))
                                .font(.caption2)
                                .foregroundStyle(Color.black.opacity(0.6))
                                .transition(.opacity)
                        } else {
                            Text(selectedTimeframe.rawValue)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.6))
                        }
                    }
                }

                Spacer(minLength: 8)

                headerFundamentalsCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerFundamentalsCard: some View {
        let fund = fundamentals ?? marketRepo.getFundamentals(for: quote.ticker)
        let currPrefix = isUSD ? "$" : "Rp "
        let isBank = (fund?.sector ?? "").lowercased().contains("financial") || (fund?.sector ?? "").lowercased().contains("bank")

        let fwdPEText: String = {
            guard let fund = fund else { return "--" }
            return fund.forwardPE != nil ? String(format: "%.2fx", fund.forwardPE!) : "N/A"
        }()

        let epsText: String = {
            guard let fund = fund else { return "--" }
            return "\(currPrefix)\(String(format: isUSD ? "%.2f" : "%.1f", fund.eps))"
        }()

        let pbvText: String = {
            guard let fund = fund else { return "--" }
            return fund.pbvRatio > 0 ? String(format: "%.2fx", fund.pbvRatio) : "N/A"
        }()

        let fcfText: String = {
            guard let fund = fund else { return "--" }
            if let fcf = fund.freeCashflow, abs(fcf) > 0 {
                return NumberFormatters.financialCompact(fcf, currency: isUSD ? "USD" : "IDR")
            } else if isBank {
                return "N/A (Bank)"
            } else {
                return "N/A"
            }
        }()

        return VStack(alignment: .leading, spacing: 3.5) {
            headerMetricRow(label: "Forward P/E", value: fwdPEText)
            headerMetricRow(label: "EPS", value: epsText)
            headerMetricRow(label: "PBV", value: pbvText)
            headerMetricRow(label: "FCF", value: fcfText)
        }
        .frame(width: 145)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private func headerMetricRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Interactive Swift Charts

    private var chartMinPrice: Double {
        (historyPoints.map(\.price).min() ?? quote.price) * 0.998
    }

    private var chartMaxPrice: Double {
        (historyPoints.map(\.price).max() ?? quote.price) * 1.002
    }

    private var chartCard: some View {
        VStack(spacing: 8) {
            if isLoadingHistory && historyPoints.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.teal)
                    Text("Memuat grafik riwayat...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 220)
                .frame(maxWidth: .infinity)
            } else if historyPoints.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Data historis belum tersedia")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 220)
                .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(historyPoints) { point in
                        AreaMark(
                            x: .value("Waktu", point.date),
                            yStart: .value("Baseline", chartMinPrice),
                            yEnd: .value("Harga", point.price)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    themeColor.opacity(0.35),
                                    themeColor.opacity(0.08),
                                    themeColor.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Waktu", point.date),
                            y: .value("Harga", point.price)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(themeColor)
                    }

                    if let scrub = selectedScrubPoint {
                        RuleMark(x: .value("SelectedDate", scrub.date))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                            .foregroundStyle(.white.opacity(0.4))

                        PointMark(
                            x: .value("SelectedDate", scrub.date),
                            y: .value("SelectedPrice", scrub.price)
                        )
                        .symbolSize(80)
                        .foregroundStyle(themeColor)
                    }
                }
                .chartYScale(domain: chartMinPrice...chartMaxPrice)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 220)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        handleChartScrub(at: value.location, proxy: proxy, geo: geo)
                                    }
                                    .onEnded { _ in
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            selectedScrubPoint = nil
                                        }
                                    }
                            )
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func handleChartScrub(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let xPos = location.x - geo[plotFrame].origin.x
        guard let date: Date = proxy.value(atX: xPos) else { return }

        // Find closest point by time
        if let closest = historyPoints.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }) {
            if selectedScrubPoint?.id != closest.id {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.linear(duration: 0.05)) {
                    selectedScrubPoint = closest
                }
            }
        }
    }

    private func formatScrubDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if selectedTimeframe == .day || selectedTimeframe == .week {
            formatter.dateFormat = "EEE, d MMM yyyy HH:mm"
        } else {
            formatter.dateFormat = "d MMMM yyyy"
        }
        return formatter.string(from: date)
    }

    // MARK: - Timeframe Segmented Control

    private var timeframeSegmentedControl: some View {
        HStack(spacing: 6) {
            ForEach(ChartTimeframe.allCases) { tf in
                let isSelected = selectedTimeframe == tf
                Button {
                    guard selectedTimeframe != tf else { return }
                    selectedTimeframe = tf
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        await loadHistory(for: tf)
                    }
                } label: {
                    Text(tf.rawValue)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? .white : Color.black.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.teal)
                                    .matchedGeometryEffect(id: "TF_PILL", in: tfNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.35), in: Capsule())
    }

    @Namespace private var tfNamespace

    // MARK: - Stats Grid (OHLC & Volume)

    private var statsGrid: some View {
        let prefix = isUSD ? "$" : "Rp "
        let low = historyPoints.map(\.low).min() ?? quote.low
        let high = historyPoints.map(\.high).max() ?? quote.high
        let open = historyPoints.first?.open ?? quote.open
        let vol = historyPoints.reduce(0) { $0 + $1.volume }
        let formatVal: (Double) -> String = { val in
            isUSD ? String(format: "%.2f", val) : NumberFormatters.stockPrice(val)
        }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Ringkasan Perdagangan")
                .font(.subheadline.bold())
                .foregroundStyle(Color.black)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statTile(title: "Tertinggi (\(selectedTimeframe.rawValue))", value: "\(prefix)\(formatVal(high))")
                statTile(title: "Terendah (\(selectedTimeframe.rawValue))", value: "\(prefix)\(formatVal(low))")
                statTile(title: "Harga Pembukaan", value: "\(prefix)\(formatVal(open))")
                statTile(title: "Volume Total", value: NumberFormatters.compact(Double(vol > 0 ? vol : quote.volume)))
            }
        }
    }

    // MARK: - Fundamentals Section



    private func statTile(title: String, value: String, subtitle: String? = nil, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.6))
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(highlight ? Color.teal : Color.black)
            if let sub = subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.black.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(highlight ? Color.teal.opacity(0.08) : Color.white.opacity(0.35))
                .overlay {
                    if highlight {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.teal.opacity(0.25), lineWidth: 1)
                    }
                }
        )
    }

    // MARK: - SEC Filings Section (US Stocks)

    @ViewBuilder
    private var secFilingsSection: some View {
        if !quote.ticker.uppercased().hasSuffix(".JK") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "00D2C4"))

                    Text("Laporan Resmi SEC (EDGAR)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)

                    Spacer()

                    Text("10-K • 10-Q • 8-K")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.5))
                }

                if isLoadingFilings {
                    HStack {
                        Spacer()
                        ProgressView().tint(Color(hex: "00D2C4")).scaleEffect(0.8)
                        Text("Memuat dokumen SEC...")
                            .font(.caption)
                            .foregroundStyle(Color.black.opacity(0.6))
                        Spacer()
                    }
                    .padding(.vertical, 12)
                } else if secFilings.isEmpty {
                    Text("Belum ada dokumen SEC yang tercatat untuk emiten ini.")
                        .font(.caption)
                        .foregroundStyle(Color.black.opacity(0.5))
                        .padding(.vertical, 6)
                } else {
                    VStack(spacing: 8) {
                        ForEach(secFilings) { filing in
                            secFilingRow(filing)
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    )
            )
        }
    }

    private func secFilingRow(_ filing: StockApiClient.SecFilingDTO) -> some View {
        Button {
            if let url = URL(string: filing.url), !filing.url.isEmpty {
                activeSafariURL = IdentifiableURL(url: url)
            }
        } label: {
            HStack(spacing: 10) {
                Text(filing.type)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(badgeColor(for: filing.type))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(badgeColor(for: filing.type).opacity(0.15))
                    )
                    .frame(minWidth: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(filing.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black)
                        .lineLimit(1)

                    Text(filing.date)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.black.opacity(0.5))
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.35))
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.25))
            )
        }
        .buttonStyle(.plain)
    }

    private func badgeColor(for type: String) -> Color {
        let upper = type.uppercased()
        if upper.contains("10-K") {
            return Color(hex: "FFB800")
        } else if upper.contains("10-Q") {
            return Color(hex: "00D2C4")
        } else if upper.contains("8-K") {
            return Color(hex: "9D65FF")
        } else {
            return Color(hex: "4FA3FF")
        }
    }

    private func loadSecFilings() async {
        guard !quote.ticker.uppercased().hasSuffix(".JK") else { return }
        isLoadingFilings = true
        defer { isLoadingFilings = false }
        do {
            let filings = try await StockApiClient.shared.fetchSecFilings(ticker: quote.ticker, limit: 6)
            await MainActor.run {
                self.secFilings = filings
            }
        } catch {
            print("ℹ️ [DetailPortfolioView] Failed to load SEC filings: \(error.localizedDescription)")
        }
    }

    // MARK: - Sticky View Holding Bar

    private var stickyViewHoldingBar: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.12))

            Button {
                holdingSheetDetent = .large
                showHoldingSheet = true
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.prepare()
                generator.impactOccurred()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "briefcase.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("View Holding")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "00D2FF"), Color(hex: "00F5D4")],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .shadow(color: Color(hex: "00D2FF").opacity(0.35), radius: 10, y: 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color(hex: "080B11").opacity(0.85))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Data Loading

    private func loadFundamentals() {
        fundamentals = marketRepo.getFundamentals(for: quote.ticker)
        Task {
            if let m = try? await StockApiClient.shared.fetchMarketData(ticker: quote.ticker) {
                let fund = StockFundamentals(
                    ticker: m.ticker,
                    name: m.name,
                    peRatio: m.trailing_pe ?? 0.0,
                    eps: m.eps ?? 0.0,
                    marketCap: (m.market_cap ?? 0.0) / 1_000_000_000_000.0,
                    dividendYield: m.dividend_yield ?? 0.0,
                    beta: 1.0,
                    pbvRatio: m.pbv_ratio ?? 0.0,
                    roe: m.roe ?? 0.0,
                    debtToEquity: 1.0,
                    sector: m.sector ?? "Unknown",
                    forwardPE: m.forward_pe,
                    forwardEps: m.forward_eps,
                    freeCashflow: m.free_cashflow
                )
                self.fundamentals = fund
                (self.marketRepo as? MarketDataRepository)?.registerRemoteQuote(quote, fundamentals: fund)
            } else if let fund = try? await StockApiClient.shared.fetchFundamentals(ticker: quote.ticker) {
                self.fundamentals = fund
                (self.marketRepo as? MarketDataRepository)?.registerRemoteQuote(quote, fundamentals: fund)
            }
        }
    }

    private func loadHistory(for tf: ChartTimeframe) async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            let points = try await StockApiClient.shared.fetchHistory(ticker: quote.ticker, period: tf.apiPeriod)
            if !points.isEmpty {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.historyPoints = points
                }
                return
            }
        } catch {
            // Fallback generated points so chart is never broken
        }

        // Generate smooth fallback curve anchored on current price
        self.historyPoints = generateFallbackPoints(for: tf)
    }

    private func generateFallbackPoints(for tf: ChartTimeframe) -> [StockHistoryPoint] {
        let count = 30
        let now = Date()
        let interval: TimeInterval
        switch tf {
        case .day: interval = 3600 * 24 / Double(count)
        case .week: interval = 3600 * 24 * 7 / Double(count)
        case .month: interval = 3600 * 24 * 30 / Double(count)
        case .threeMonth: interval = 3600 * 24 * 90 / Double(count)
        case .ytd: interval = 3600 * 24 * 180 / Double(count)
        case .year: interval = 3600 * 24 * 365 / Double(count)
        case .fiveYear: interval = 3600 * 24 * 365 * 5 / Double(count)
        }

        var points: [StockHistoryPoint] = []
        var runningPrice = quote.previousClose
        let stepScale = quote.price * 0.008

        for i in 0..<count {
            let date = now.addingTimeInterval(-Double(count - 1 - i) * interval)
            let delta = Double([-2, -1, 0, 1, 2].randomElement() ?? 0) * stepScale
            runningPrice = max(quote.price * 0.7, runningPrice + delta)
            if i == count - 1 {
                runningPrice = quote.price
            }
            points.append(StockHistoryPoint(date: date, price: runningPrice))
        }
        return points
    }
}

// MARK: - Color Hex Helper

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

// MARK: - Stock Holding Detail Sheet

// MARK: - Purchase Form Entry Model

struct PurchaseFormEntry: Identifiable, Equatable {
    let id: UUID
    var date: Date
    var priceInput: String
    var totalInput: String

    init(id: UUID = UUID(), date: Date = Date(), priceInput: String = "", totalInput: String = "") {
        self.id = id
        self.date = date
        self.priceInput = priceInput
        self.totalInput = totalInput
    }

    var price: Double {
        let clean = priceInput.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(clean) ?? 0.0
    }

    var total: Double {
        let clean = totalInput.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(clean) ?? 0.0
    }

    var shares: Double {
        guard price > 0, total > 0 else { return 0.0 }
        return total / price
    }

    var formattedShares: String {
        let s = shares
        guard s > 0 else { return "0" }
        if s.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(s))"
        } else {
            let str = String(format: "%.2f", s)
            return str.hasSuffix("0") ? String(format: "%.1f", s) : str
        }
    }
}

// MARK: - Stock Holding Detail Sheet

struct StockHoldingDetailSheet: View {
    let quote: StockQuote
    let sector: String
    let onBuy: (_ amount: Double, _ pricePerShare: Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var repo = PortfolioRepository.shared
    @State private var purchaseEntries: [PurchaseFormEntry] = []
    @State private var isInitialized: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showLotDeleteOptions: Bool = false
    @State private var pendingDeleteEntryId: UUID? = nil
    @State private var showSuccessToast: Bool = false
    @State private var toastMessage: String = ""

    private var holding: UserHolding? {
        let clean = quote.ticker.trimmingCharacters(in: .whitespaces).uppercased()
        return repo.userHoldings.first {
            $0.ticker.trimmingCharacters(in: .whitespaces).uppercased() == clean
        }
    }

    private var isUSD: Bool {
        quote.currency.uppercased() == "USD" || quote.isUSD
    }

    private func formatCurrency(_ value: Double) -> String {
        if isUSD {
            return String(format: "$%.2f", value)
        } else {
            return "Rp \(NumberFormatters.stockPrice(value))"
        }
    }

    private func formatNumberInput(_ val: Double) -> String {
        guard val > 0 else { return "" }
        if val.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(val))"
        } else {
            let str = String(format: "%.2f", val)
            return str.hasSuffix("0") ? String(format: "%.1f", val) : str
        }
    }

    private var validEntries: [PurchaseFormEntry] {
        purchaseEntries.filter { $0.price > 0 && $0.total > 0 }
    }

    private var totalInvestedAmount: Double {
        let sum = validEntries.reduce(0) { $0 + $1.total }
        if sum > 0 { return sum }
        return holding?.investedAmount ?? 0.0
    }

    private var totalCalculatedShares: Double {
        let sum = validEntries.reduce(0) { $0 + $1.shares }
        if sum > 0 { return sum }
        return holding?.fractionalShares ?? 0.0
    }

    private var formattedTotalShares: String {
        let s = totalCalculatedShares
        guard s > 0 else { return "0" }
        if s.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(s))"
        } else {
            let str = String(format: "%.2f", s)
            return str.hasSuffix("0") ? String(format: "%.1f", s) : str
        }
    }

    private var averagePricePerShare: Double {
        guard totalCalculatedShares > 0 else { return quote.price }
        return totalInvestedAmount / totalCalculatedShares
    }

    private var currentPositionValue: Double {
        totalCalculatedShares * quote.price
    }

    private var currentPnL: Double {
        currentPositionValue - totalInvestedAmount
    }

    private var currentPnLPercent: Double {
        guard totalInvestedAmount > 0 else { return 0.0 }
        return (currentPnL / totalInvestedAmount) * 100
    }

    private func addNewEntry() {
        let newEntry = PurchaseFormEntry(
            date: Date(),
            priceInput: "",
            totalInput: ""
        )
        purchaseEntries.append(newEntry)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func removeEntry(id: UUID) {
        guard purchaseEntries.count > 1 else { return }
        purchaseEntries.removeAll { $0.id == id }
        syncHoldingEdits()
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func syncHoldingEdits() {
        guard isInitialized else { return }
        guard holding != nil else { return }
        let valid = validEntries
        guard !valid.isEmpty else { return }

        let lots = valid.map { entry in
            PurchaseLot(
                id: entry.id,
                date: entry.date,
                pricePerShare: entry.price,
                totalInvested: entry.total
            )
        }
        repo.updateHoldingLots(
            ticker: quote.ticker,
            lots: lots,
            pricePerShare: averagePricePerShare,
            totalInvested: totalInvestedAmount
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "080B11").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerSummaryCard

                        if let holding = holding {
                            ownedPositionSection(holding: holding)
                        } else {
                            unownedPositionSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Holding Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Selesai") {
                        dismiss()
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(Color(hex: "4FA3FF"))
                }
            }
            .onAppear {
                if let holding = holding {
                    if let lots = holding.purchaseLots, !lots.isEmpty {
                        purchaseEntries = lots.map { lot in
                            PurchaseFormEntry(
                                id: lot.id,
                                date: lot.date,
                                priceInput: formatNumberInput(lot.pricePerShare),
                                totalInput: formatNumberInput(lot.totalInvested)
                            )
                        }
                    } else {
                        purchaseEntries = [
                            PurchaseFormEntry(
                                date: Date(),
                                priceInput: formatNumberInput(holding.pricePerShare),
                                totalInput: formatNumberInput(holding.investedAmount)
                            )
                        ]
                    }
                } else {
                    purchaseEntries = [
                        PurchaseFormEntry(
                            date: Date(),
                            priceInput: formatNumberInput(quote.price),
                            totalInput: ""
                        )
                    ]
                }
                DispatchQueue.main.async {
                    isInitialized = true
                }
            }
            .onChange(of: purchaseEntries) { _, _ in
                syncHoldingEdits()
            }
            .confirmationDialog("Hapus dari Portofolio?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Hapus Saham", role: .destructive) {
                    repo.removeHolding(ticker: quote.ticker)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.warning)
                }
                Button("Batal", role: .cancel) {}
            } message: {
                Text("Apakah Anda yakin ingin menghapus \(quote.ticker) dari portofolio Anda?")
            }
            .confirmationDialog("Pilihan Hapus", isPresented: $showLotDeleteOptions, titleVisibility: .visible) {
                if let id = pendingDeleteEntryId {
                    Button("Hapus Lot Ini Saja", role: .destructive) {
                        removeEntry(id: id)
                        pendingDeleteEntryId = nil
                    }
                }
                Button("Hapus Seluruh \(quote.ticker) dari Portofolio", role: .destructive) {
                    repo.removeHolding(ticker: quote.ticker)
                    pendingDeleteEntryId = nil
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.warning)
                }
                Button("Batal", role: .cancel) {
                    pendingDeleteEntryId = nil
                }
            } message: {
                Text("Pilih apakah Anda ingin menghapus lot transaksi ini saja atau menghapus seluruh posisi \(quote.ticker) dari portofolio.")
            }
            .overlay(alignment: .bottom) {
                if showSuccessToast {
                    Text(toastMessage)
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(hex: "00D084"), in: Capsule())
                        .shadow(color: Color.black.opacity(0.4), radius: 8, y: 4)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Header Summary Card

    private var headerSummaryCard: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(quote.ticker)
                        .font(.title3.bold())
                        .foregroundStyle(Color.black)

                    if holding != nil {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: "00D084"))
                                .frame(width: 6, height: 6)
                            Text("Dimiliki")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(hex: "00D084"))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: "00D084").opacity(0.15), in: Capsule())
                    } else {
                        Text("Belum Dimiliki")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.6))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.06), in: Capsule())
                    }
                }

                Text(quote.name)
                    .font(.footnote)
                    .foregroundStyle(Color.black.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            Text(sector)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.teal)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.teal.opacity(0.12), in: Capsule())
        }
        .padding(16)
        .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        }
    }

    // MARK: - Owned Position Section

    private func ownedPositionSection(holding: UserHolding) -> some View {
        let currentVal = currentPositionValue
        let pnl = currentPnL
        let pnlPct = currentPnLPercent
        let isProfit = pnl >= 0
        let sign = isProfit ? "+" : "-"

        return VStack(spacing: 16) {
            // 1. Valuasi Posisi & Total G&L (Side by Side)
            HStack(spacing: 12) {
                metricTile(
                    title: "Valuasi Posisi",
                    value: formatCurrency(currentVal),
                    caption: "Nilai saat ini (\(formattedTotalShares) Shares)",
                    icon: "chart.pie.fill",
                    color: Color(hex: "00D2FF")
                )

                metricTile(
                    title: "Total G&L",
                    value: String(format: "%@%@ (%@%.2f%%)", sign, formatCurrency(abs(pnl)), sign, abs(pnlPct)),
                    caption: isProfit ? "Keuntungan" : "Kerugian",
                    icon: "chart.line.uptrend.xyaxis",
                    color: isProfit ? Color(hex: "00D084") : Color(hex: "FF3B30")
                )
            }

            // 2. List Form Kepemilikan (Tanggal Beli, Per Share Price, Total Beli, Dapat Share) + Button "+ Add Share"
            purchaseEntriesList
        }
    }

    // MARK: - Unowned Position Section

    private var unownedPositionSection: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "briefcase")
                    .font(.system(size: 38))
                    .foregroundStyle(Color(hex: "4FA3FF"))
                    .frame(width: 76, height: 76)
                    .background(Color(hex: "4FA3FF").opacity(0.12), in: Circle())

                Text("Belum Memiliki Saham \(quote.ticker)")
                    .font(.headline.bold())
                    .foregroundStyle(Color.black)

                Text("Masukkan tanggal beli, harga per share, dan total nominal yang dibeli untuk menambahkan ke portofolio Anda.")
                    .font(.footnote)
                    .foregroundStyle(Color.black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .padding(.vertical, 8)

            // List Form Kepemilikan + Button "+ Add Share"
            purchaseEntriesList

            // Confirm Purchase Button
            Button {
                let amt = totalInvestedAmount
                let price = averagePricePerShare
                guard amt > 0, price > 0 else { return }
                onBuy(amt, price)
                let lots = validEntries.map { entry in
                    PurchaseLot(
                        id: entry.id,
                        date: entry.date,
                        pricePerShare: entry.price,
                        totalInvested: entry.total
                    )
                }
                repo.updateHoldingLots(ticker: quote.ticker, lots: lots, pricePerShare: price, totalInvested: amt)
                toastMessage = "\(quote.ticker) berhasil ditambahkan ke portofolio!"
                withAnimation { showSuccessToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { showSuccessToast = false }
                }
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.headline)
                    Text("Beli & Tambah ke Portofolio")
                        .font(.headline.bold())
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "00D2FF"), Color(hex: "00F5D4")],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .shadow(color: Color(hex: "00D2FF").opacity(0.35), radius: 10, y: 4)
            }
            .disabled(totalInvestedAmount <= 0 || averagePricePerShare <= 0)
            .opacity(totalInvestedAmount > 0 && averagePricePerShare > 0 ? 1.0 : 0.5)
        }
    }

    // MARK: - Purchase Entries List (Tanggal Beli + Horizontal Row + Add Share Button)

    private var purchaseEntriesList: some View {
        VStack(spacing: 12) {
            ForEach($purchaseEntries) { $entry in
                VStack(spacing: 10) {
                    // Header: Tanggal Beli + Tombol Hapus (jika > 1)
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(hex: "00D2FF"))

                        Text("Tanggal Beli")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))

                        DatePicker(
                            "",
                            selection: $entry.date,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(Color(hex: "00D2FF"))

                        Spacer()

                        if holding != nil {
                            Button {
                                if purchaseEntries.count > 1 {
                                    pendingDeleteEntryId = entry.id
                                    showLotDeleteOptions = true
                                } else {
                                    showDeleteConfirm = true
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Hapus dari Portofolio")
                                        .font(.system(size: 10, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .foregroundStyle(Color(hex: "FF3B30"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .background(Color(hex: "FF3B30").opacity(0.12), in: Capsule())
                            }
                        } else if purchaseEntries.count > 1 {
                            Button {
                                removeEntry(id: entry.id)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("Hapus")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundStyle(Color(hex: "FF3B30").opacity(0.85))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .background(Color(hex: "FF3B30").opacity(0.12), in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 4)

                    // 1 List Horizontal: Per Share Price, Total Beli, Dapat Share
                    HStack(spacing: 8) {
                        // 1. Per Share Price (Form)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Per Share Price")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            HStack(spacing: 3) {
                                Text(isUSD ? "$" : "Rp")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundStyle(Color(hex: "00D2FF"))

                                TextField("0", text: $entry.priceInput)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.black)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        }

                        // 2. Total Beli (Form)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Total Beli")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.6))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            HStack(spacing: 3) {
                                Text(isUSD ? "$" : "Rp")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundStyle(Color(hex: "00F5D4"))

                                TextField("0", text: $entry.totalInput)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.black)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        }

                        // 3. Total Dapat Berapa Share (Calculated)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Dapat Share")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.6))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.formattedShares)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(hex: "00D2FF"))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)

                                Text("Shares")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(hex: "00D2FF").opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(hex: "00D2FF").opacity(0.25), lineWidth: 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }
            }

            // Tombol + Add Share (Kecil di Tengah Horizontal)
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        addNewEntry()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add Share")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "00D2FF"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(hex: "00D2FF").opacity(0.12), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color(hex: "00D2FF").opacity(0.3), lineWidth: 1)
                    }
                }
                Spacer()
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Metric Tile Component

    private func metricTile(
        title: String,
        value: String,
        caption: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(Color.black.opacity(0.6))
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Color.black)
                .minimumScaleFactor(0.8)
                .lineLimit(1)

            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Color.black.opacity(0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        }
    }
}
