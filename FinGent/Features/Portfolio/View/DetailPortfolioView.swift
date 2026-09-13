// Features/Portfolio/View/DetailPortfolioView.swift

import SwiftUI

struct DetailPortfolioView: View {

    let quote: StockQuote

    @Environment(\.dismiss) private var dismiss

    @StateObject private var chartVM: StockDetailChartViewModel
    @State private var selectedPoint: StockHistoryPoint? = nil
    @State private var isDragging: Bool = false
    @State private var chartSize: CGSize = .zero

    @State private var fundamentals: StockFundamentals? = nil
    @State private var activeSafariURL: IdentifiableURL? = nil
    @State private var portfolioRepo = PortfolioRepository.shared
    @State private var favoritesRepo = FavoritesRepository.shared

    private let portfolioUseCase: PortfolioUseCase = AppContainer.shared.portfolioUseCase
    private let marketRepo: MarketDataRepositoryProtocol = MarketDataRepository.shared

    init(quote: StockQuote) {
        self.quote = quote
        _chartVM = StateObject(wrappedValue: StockDetailChartViewModel(quote: quote))
    }

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
                VStack(spacing: 18) {
                    stockHeader
                    chartSection

                    StockHoldingDetailSection(
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
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
            await chartVM.fetchChartData()
        }
        .sheet(item: $activeSafariURL) { item in
            SafariView(url: item.url)
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
        selectedPoint?.price ?? quote.price
    }

    private var displayFormattedPrice: String {
        let p = displayPrice
        if isUSD {
            return String(format: "$%.2f", p)
        } else {
            return "Rp \(NumberFormatters.stockPrice(p))"
        }
    }

    private var currentChange: Double {
        if isDragging, let pt = selectedPoint {
            return pt.price - chartVM.startPrice
        }
        if let first = chartVM.dataPoints.first, let last = chartVM.dataPoints.last {
            return last.price - first.price
        }
        return quote.change
    }

    private var currentChangePct: Double {
        if isDragging, let pt = selectedPoint {
            guard chartVM.startPrice != 0 else { return 0 }
            return ((pt.price - chartVM.startPrice) / chartVM.startPrice) * 100
        }
        if let first = chartVM.dataPoints.first, let last = chartVM.dataPoints.last {
            guard first.price != 0 else { return 0 }
            return ((last.price - first.price) / first.price) * 100
        }
        return quote.changePercent
    }

    private var isGain: Bool {
        currentChange >= 0
    }

    private var themeColor: Color {
        isGain ? Color(red: 0.0, green: 0.831, blue: 0.667) : Color(red: 0.937, green: 0.267, blue: 0.267)
    }

    private var stockHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(quote.ticker)
                    .font(.title2.bold())
                    .foregroundStyle(Color.black)
                Text(quote.name)
                    .font(.subheadline)
                    .foregroundStyle(Color.black.opacity(0.6))
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayFormattedPrice)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Group {
                            let sign = currentChange >= 0 ? "+" : "-"
                            if isUSD {
                                Text(String(format: "%@$%.2f (%@%.2f%%)", sign, abs(currentChange), sign, abs(currentChangePct)))
                            } else {
                                Text(String(format: "%@Rp %@ (%@%.2f%%)", sign, NumberFormatters.stockPrice(abs(currentChange)), sign, abs(currentChangePct)))
                            }
                        }
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(themeColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(themeColor.opacity(0.12), in: Capsule())

                        if chartVM.selectedRange == .oneDay {
                            Text("1D")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.black.opacity(0.6))
                        } else if let scrub = selectedPoint {
                            Text(formatScrubDate(scrub.date))
                                .font(.caption2)
                                .foregroundStyle(Color.black.opacity(0.6))
                                .transition(.opacity)
                        } else {
                            Text(chartVM.selectedRange.rawValue)
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
        .frame(width: 140)
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

    // MARK: - Interactive Line Chart (SahamIndo Style)

    private var chartSection: some View {
        VStack(spacing: 8) {
            StockChartCanvasView(
                chartVM:           chartVM,
                selectedPoint:     $selectedPoint,
                isDragging:        $isDragging,
                chartSize:         $chartSize,
                accentColor:       themeColor,
                displayIsPositive: isGain,
                isUSD:             isUSD,
                lineWidth:         1.6
            )
            .frame(height: 230)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { chartSize = geo.size }
                        .onChange(of: geo.size) { _, s in chartSize = s }
                }
            )

            if !chartVM.dataPoints.isEmpty {
                XAxisAnimatedLabels(
                    chartVM:   chartVM,
                    chartSize: chartSize
                )
                .padding(.horizontal, 4)
                .padding(.top, -8)
                .padding(.bottom, 2)
            }

            TimeRangeSelectorView(chartVM: chartVM) {
                selectedPoint = nil
                isDragging    = false
            }
        }
    }

    private func formatScrubDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "id_ID")
        formatter.timeZone = TimeZone(identifier: "Asia/Jakarta")!
        if chartVM.selectedRange.isIntraday {
            formatter.dateFormat = "d MMM 'pukul' HH:mm"
        } else {
            formatter.dateFormat = "d MMMM yyyy"
        }
        return formatter.string(from: date)
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

// MARK: - Stock Holding Detail Section

struct StockHoldingDetailSection: View {
    let quote: StockQuote
    let sector: String
    let onBuy: (_ amount: Double, _ pricePerShare: Double) -> Void

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

    private func formatEntryDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
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
        VStack(spacing: 16) {
            headerSection

            if let holding = holding {
                ownedPositionSection(holding: holding)
            } else {
                unownedPositionSection
            }
        }
        .onAppear {
            initializeEntries()
        }
        .onDisappear {
            syncHoldingEdits()
        }
        .onChange(of: holding == nil) { _, _ in
            initializeEntries()
        }
        .onChange(of: purchaseEntries) { _, _ in
            syncHoldingEdits()
        }
        .confirmationDialog("Hapus dari Portofolio?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
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
            Button("Delete Seluruh Posisi \(quote.ticker)", role: .destructive) {
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
                    .background(Color(hex: "00B89F"), in: Capsule())
                    .shadow(color: Color.black.opacity(0.4), radius: 8, y: 4)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func initializeEntries() {
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

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .center) {
            Text("Holding Details")
                .font(.headline.bold())
                .foregroundStyle(Color.black)

            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Owned Position Section

    private func ownedPositionSection(holding: UserHolding) -> some View {
        let currentVal = currentPositionValue
        let pnl = currentPnL
        let pnlPct = currentPnLPercent
        let isProfit = pnl >= 0
        let sign = isProfit ? "+" : "-"
        let pnlColor = isProfit ? Color(hex: "00B89F") : Color(hex: "FF3B30")

        return VStack(spacing: 16) {
            // 1. Valuasi Posisi & Total G&L (Side by Side)
            HStack(spacing: 12) {
                metricTile(
                    title: "Valuasi Posisi",
                    value: formatCurrency(currentVal),
                    caption: "\(formattedTotalShares) Shares",
                    icon: "chart.pie.fill",
                    color: Color(hex: "007AFF")
                )

                metricTile(
                    title: "Total G&L",
                    value: String(format: "%@%@", sign, formatCurrency(abs(pnl))),
                    caption: String(format: "%@%.2f%%", sign, abs(pnlPct)),
                    icon: isProfit ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                    color: pnlColor,
                    valueColor: pnlColor,
                    captionColor: pnlColor
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
                    .foregroundStyle(Color(hex: "007AFF"))
                    .frame(width: 76, height: 76)
                    .background(Color(hex: "007AFF").opacity(0.12), in: Circle())

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
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10, weight: .bold))
                            Text(formatEntryDate(entry.date))
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(Color(hex: "007AFF"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4.5)
                        .background(Color(hex: "007AFF").opacity(0.12), in: Capsule())
                        .overlay {
                            DatePicker(
                                "",
                                selection: $entry.date,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .blendMode(.destinationOver)
                            .opacity(0.015)
                        }

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
                                    Text("Delete")
                                        .font(.system(size: 10, weight: .semibold))
                                        .lineLimit(1)
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
                                    Text("Delete")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundStyle(Color(hex: "FF3B30"))
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
                            Text("Cost per Share")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.6))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            HStack(spacing: 3) {
                                Text(isUSD ? "$" : "Rp")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundStyle(Color.black.opacity(0.6))

                                TextField("0", text: $entry.priceInput)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.black)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // 2. Total Beli (Form)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Total Buy")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.6))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            HStack(spacing: 3) {
                                Text(isUSD ? "$" : "Rp")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundStyle(Color.black.opacity(0.6))

                                TextField("0", text: $entry.totalInput)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.black)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // 3. Total Dapat Berapa Share (Calculated)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Share")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.black.opacity(0.6))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text(entry.formattedShares)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                                }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
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
                    .foregroundStyle(Color.black.opacity(0.8))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.5), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
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
        color: Color,
        valueColor: Color = Color.black,
        captionColor: Color = Color.black.opacity(0.45)
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
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.8)
                .lineLimit(1)

            Text(caption)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(captionColor)
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
