// Features/Profile/ViewModel/ProfileViewModel.swift

import Foundation
import Observation

@Observable
@MainActor
final class ProfileViewModel {

    // MARK: - Dependencies

    private let portfolioRepository: PortfolioRepositoryProtocol
    private let portfolioUseCase: PortfolioUseCase

    // MARK: - State

    var userName: String = "" {
        didSet {
            if let repo = portfolioRepository as? PortfolioRepository {
                repo.userName = userName
            }
        }
    }

    var isLiveSimulationEnabled: Bool = true
    var isBiometricEnabled: Bool = false
    var isShowingResetAlert: Bool = false

    private(set) var holdingCount: Int = 0
    private(set) var totalMarketValue: Double = 0
    private(set) var totalInvested: Double = 0
    private(set) var totalPnL: Double = 0
    private(set) var totalPnLPercent: Double = 0

    // MARK: - Siri Shortcuts Guide

    struct SiriVoiceGuide: Identifiable {
        let id = UUID()
        let prompt: String
        let description: String
        let category: String
        let icon: String
    }

    let siriGuides: [SiriVoiceGuide] = [
        SiriVoiceGuide(
            prompt: "\"Is there any news about my portfolio today in FinGent?\"",
            description: "Siri langsung merangkum berita terkini dari seluruh saham yang kamu miliki di portofolio.",
            category: "Portfolio News",
            icon: "newspaper.fill"
        ),
        SiriVoiceGuide(
            prompt: "\"How is my portfolio performing in FinGent?\"",
            description: "Mengecek total nilai portofolio, total modal terinvestasi, dan persentase keuntungan saat ini.",
            category: "Portfolio Performance",
            icon: "chart.line.uptrend.xyaxis"
        ),
        SiriVoiceGuide(
            prompt: "\"What is the price of BBCA in FinGent?\"",
            description: "Menanyakan harga realtime, perubahan harian, dan ringkasan tren saham emiten.",
            category: "Stock Quote",
            icon: "dollarsign.circle.fill"
        ),
        SiriVoiceGuide(
            prompt: "\"Compare BBCA and BBRI in FinGent\"",
            description: "Analisis komparasi valuasi fundamental (P/E, PBV, RoE) dan performa 2 saham.",
            category: "Market Comparison",
            icon: "arrow.left.arrow.right"
        ),
        SiriVoiceGuide(
            prompt: "\"Ask FinGent agent for market overview\"",
            description: "Meminta AI Agent menganalisis ringkasan IHSG, top gainers, dan sentimen pasar modal.",
            category: "Market Intelligence",
            icon: "sparkles"
        )
    ]

    // MARK: - Init

    init(
        portfolioRepository: PortfolioRepositoryProtocol,
        portfolioUseCase: PortfolioUseCase
    ) {
        self.portfolioRepository = portfolioRepository
        self.portfolioUseCase = portfolioUseCase
        load()
    }

    // MARK: - Actions

    func load() {
        if let repo = portfolioRepository as? PortfolioRepository {
            self.userName = repo.userName.isEmpty ? "Investor FinGent" : repo.userName
        }
        let summary = portfolioUseCase.portfolioSummary()
        self.holdingCount = summary.holdingCount
        self.totalMarketValue = summary.totalMarketValue
        self.totalInvested = summary.totalInvested
        self.totalPnL = summary.totalPnL
        self.totalPnLPercent = summary.totalPnLPercent
    }

    func resetToDefaultData() {
        if let repo = portfolioRepository as? PortfolioRepository {
            repo.removeHolding(ticker: "BBCA")
            repo.removeHolding(ticker: "TLKM")
            repo.removeHolding(ticker: "GOTO")
            repo.removeHolding(ticker: "BBRI")
            repo.removeHolding(ticker: "ASII")

            repo.addHolding(ticker: "BBCA", name: "Bank Central Asia", amount: 10_000_000, pricePerShare: 10_000, sector: "Financials")
            repo.addHolding(ticker: "TLKM", name: "Telkom Indonesia", amount: 5_000_000, pricePerShare: 3_100, sector: "Infrastructure")
            repo.userName = "Surya"
            self.userName = "Surya"
        }
        load()
    }
}
