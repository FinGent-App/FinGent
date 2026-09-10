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
    let favoritesRepository: FavoritesRepositoryProtocol = FavoritesRepository.shared

    // MARK: - Use Cases

    private(set) lazy var portfolioUseCase = PortfolioUseCase(
        portfolioRepository: portfolioRepository,
        marketDataRepository: marketDataRepository
    )

    private(set) lazy var newsRetrievalUseCase = NewsRetrievalUseCase(
        newsRepository: newsRepository,
        syncService: NewsSyncService.shared
    )

    private(set) lazy var chatUseCase = ChatUseCase(
        agent: FinGentAgent(),
        newsRetrievalUseCase: newsRetrievalUseCase,
        marketRepo: marketDataRepository
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
        ChatViewModel(chatUseCase: chatUseCase)
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            portfolioRepository: portfolioRepository,
            marketDataRepository: marketDataRepository,
            newsRepository: newsRepository,
            favoritesRepository: favoritesRepository,
            portfolioUseCase: portfolioUseCase
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
