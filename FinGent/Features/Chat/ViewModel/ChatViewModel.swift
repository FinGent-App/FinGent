// Features/Chat/ViewModel/ChatViewModel.swift

import Foundation
import Observation

@Observable
@MainActor
final class ChatViewModel {

    // MARK: - Types

    struct ChatMessage: Identifiable, Sendable {
        let id = UUID()
        enum Role { case user, assistant }
        let role: Role
        let content: String
        let bias: MarketBias?
        let confidence: Double?
        let sources: [NewsCitation]

        init(
            role: Role,
            content: String,
            bias: MarketBias? = nil,
            confidence: Double? = nil,
            sources: [NewsCitation] = []
        ) {
            self.role = role
            self.content = content
            self.bias = bias
            self.confidence = confidence
            self.sources = sources
        }
    }

    // MARK: - Constants

    static let quickPrompts = [
        "📊 Ringkasan Portofolio",
        "⚡ Apakah MU akan naik atau turun?",
        "📰 Berita katalis terbaru NVDA",
        "📈 Saham Penggerak IHSG",
        "⚖️ Bandingkan GOTO vs BBRI"
    ]

    private static let welcomeMessage = ChatMessage(
        role: .assistant,
        content: "Halo! Saya FinGent AI Assistant 🤖\n\nSaya terhubung dengan live feed Yahoo Finance, CNBC RSS, dan portofolio kamu. Tanyakan prospek saham (seperti MU, NVDA, BBCA), katalis terkini, atau pergerakan pasar!"
    )

    // MARK: - Output State

    private(set) var messages: [ChatMessage] = [welcomeMessage]
    private(set) var isProcessing: Bool = false
    var inputText: String = ""

    // MARK: - Dependencies

    private let chatUseCase: ChatUseCaseProtocol

    // MARK: - Init

    init(chatUseCase: ChatUseCaseProtocol) {
        self.chatUseCase = chatUseCase
    }

    convenience init() {
        self.init(chatUseCase: ChatUseCase())
    }

    // MARK: - Actions

    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty, !isProcessing else { return }

        append(.init(role: .user, content: prompt))
        inputText = ""

        Task {
            isProcessing = true
            defer { isProcessing = false }
            do {
                let response = try await chatUseCase.ask(prompt)
                append(.init(
                    role: .assistant,
                    content: response.answer,
                    bias: response.bias,
                    confidence: response.confidence,
                    sources: response.sources
                ))
            } catch {
                append(.init(role: .assistant, content: "Maaf, terjadi kendala: \(error.localizedDescription)"))
            }
        }
    }

    func resetSession() {
        chatUseCase.resetSession()
        messages = [Self.welcomeMessage]
    }

    // MARK: - Private

    private func append(_ message: ChatMessage) {
        messages.append(message)
    }
}
