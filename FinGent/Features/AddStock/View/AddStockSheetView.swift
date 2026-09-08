// Features/AddStock/View/AddStockSheetView.swift

import SwiftUI

struct AddStockSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AppContainer.shared.makeAddStockViewModel()
    @State private var portfolioRepo = PortfolioRepository.shared

    let onSaved: () -> Void

    @FocusState private var isAmountFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.16).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        if viewModel.selectedStock == nil {
                            stockPickerSection
                        } else {
                            amountEntrySection
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(viewModel.selectedStock == nil ? "Pilih Saham" : "Tambah \(viewModel.selectedStock!.ticker)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { viewModel.ownedTickers = Set(portfolioRepo.userHoldings.map(\.ticker)) }
    }

    // MARK: - Step 1: Stock Picker

    private var stockPickerSection: some View {
        VStack(spacing: 16) {
            searchBar
            ForEach(viewModel.filteredStocks, id: \.ticker) { stock in
                StockPickerRowView(
                    stock: stock,
                    isOwned: viewModel.ownedTickers.contains(stock.ticker),
                    onSelect: {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.selectStock(stock)
                        }
                    }
                )
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
            TextField("Cari saham...", text: $viewModel.searchText)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background { RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)) }
    }

    // MARK: - Step 2: Amount Entry

    private var amountEntrySection: some View {
        VStack(spacing: 20) {
            if let stock = viewModel.selectedStock {
                selectedStockCard(stock)
            }

            amountInputField

            quickAmountChips

            if viewModel.inputAmount > 0, let stock = viewModel.selectedStock {
                estimationPreview(stock: stock)
            }

            saveButton
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { isAmountFocused = true }
        }
    }

    private func selectedStockCard(_ stock: AvailableStock) -> some View {
        HStack(spacing: 12) {
            Text(stock.ticker)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 56, height: 40)
                .background { RoundedRectangle(cornerRadius: 10).fill(.cyan.opacity(0.2)) }

            VStack(alignment: .leading, spacing: 2) {
                Text(stock.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Harga: Rp \(NumberFormatters.stockPrice(stock.price)) / lembar")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(16)
        .background { RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)) }
    }

    private var amountInputField: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Jumlah Investasi")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 8) {
                Text("Rp")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)

                TextField("0", text: $viewModel.amountText)
                    .keyboardType(.numberPad)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($isAmountFocused)

                if !viewModel.amountText.isEmpty {
                    Button { viewModel.amountText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.08))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(.cyan.opacity(0.3), lineWidth: 1) }
            }
        }
    }

    private var quickAmountChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AddStockViewModel.quickAmounts, id: \.label) { item in
                    QuickAmountChip(label: item.label) {
                        viewModel.addQuickAmount(item.amount)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func estimationPreview(stock: AvailableStock) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Estimasi Lembar Saham:")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                let isUSD = stock.isUSD
                let lotCount = viewModel.estimatedShares / 100
                let lotText: String = {
                    if !isUSD && lotCount > 0 {
                        return "\(lotCount) lot (\(NumberFormatters.stockPrice(Double(viewModel.estimatedShares))) lembar)"
                    }
                    return "\(viewModel.estimatedShares) lembar"
                }()
                Text(lotText)
                    .font(.subheadline.bold())
                    .foregroundStyle(.cyan)
            }
            HStack {
                Text("Investasi Efektif:")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                let effText = stock.isUSD
                    ? String(format: "$%.2f", viewModel.effectiveInvestment)
                    : "Rp \(NumberFormatters.stockPrice(viewModel.effectiveInvestment))"
                Text(effText)
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.7))
            }
            if viewModel.estimatedShares == 0 {
                Text("⚠️ Jumlah terlalu kecil untuk 1 lembar saham")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background { RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)) }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var saveButton: some View {
        Button(action: saveStock) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").font(.headline)
                Text("Tambah ke Portfolio").font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        viewModel.canSave
                            ? LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(color: viewModel.canSave ? .cyan.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
            }
        }
        .disabled(!viewModel.canSave)
        .padding(.top, 4)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Batal") { dismiss() }
                .foregroundStyle(.white.opacity(0.7))
        }
        if viewModel.selectedStock != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.spring(response: 0.3)) { viewModel.clearSelection() }
                } label: {
                    Image(systemName: "chevron.left").foregroundStyle(.cyan)
                }
            }
        }
    }

    // MARK: - Actions

    private func saveStock() {
        guard viewModel.canSave else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { viewModel.save() }
        dismiss()
        onSaved()
    }
}

// MARK: - Stock Picker Row

private struct StockPickerRowView: View {
    let stock: AvailableStock
    let isOwned: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Text(stock.ticker)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 36)
                    .background { RoundedRectangle(cornerRadius: 8).fill(.cyan.opacity(0.2)) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(stock.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(stock.sector)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(stock.formattedPrice)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    if isOwned {
                        Text("Sudah punya")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green.opacity(0.8))
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background { RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.04)) }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Amount Chip

private struct QuickAmountChip: View {
    let label: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.cyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(.cyan.opacity(0.12))
                        .overlay { Capsule().stroke(.cyan.opacity(0.3), lineWidth: 1) }
                }
        }
    }
}
