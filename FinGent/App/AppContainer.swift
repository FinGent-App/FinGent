// App/AppContainer.swift

import Foundation

/// Composition root — assembles all dependencies.
/// Views and ViewModels receive dependencies through this container.
@MainActor
final class AppContainer {

    static let shared = AppContainer()

    // MARK: - Repositories (singletons as data sources)

    let portfolioRepository: PortfolioRepositoryProtocol = PortfolioRepository.shared
    let marketDataRepository: MarketDataRepositoryProtocol = MarketDataRepository.shared
    let newsRepository: NewsRepositoryProtocol = NewsRepository.shared

    // MARK: - Use Cases

    private(set) lazy var portfolioUseCase = PortfolioUseCase(
        portfolioRepository: portfolioRepository,
        marketDataRepository: marketDataRepository
    )

    // MARK: - ViewModels

    func makePortfolioViewModel() -> PortfolioViewModel {
        PortfolioViewModel(
            portfolioRepository: portfolioRepository,
            marketDataRepository: marketDataRepository,
            portfolioUseCase: portfolioUseCase
        )
    }

    func makeAddStockViewModel() -> AddStockViewModel {
        AddStockViewModel(
            portfolioUseCase: portfolioUseCase,
            marketDataRepository: marketDataRepository
        )
    }

    func makeChatViewModel() -> ChatViewModel {
        ChatViewModel()
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            portfolioRepository: portfolioRepository,
            marketDataRepository: marketDataRepository,
            newsRepository: newsRepository
        )
    }

    func makeSearchViewModel() -> SearchViewModel {
        SearchViewModel(
            marketDataRepository: marketDataRepository,
            newsRepository: newsRepository,
            portfolioUseCase: portfolioUseCase
        )
    }

    func makeProfileViewModel() -> ProfileViewModel {
        ProfileViewModel(
            portfolioRepository: portfolioRepository,
            portfolioUseCase: portfolioUseCase
        )
    }

    private init() {}
}
