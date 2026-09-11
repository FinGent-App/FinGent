// Features/Chat/ViewModel/ChatViewModel.swift

import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class ChatViewModel {

    // MARK: - Types

    struct ResearchStepItem: Identifiable, Sendable, Equatable {
        let id: String
        var title: String
        let iconName: String
        var status: Status

        enum Status: Sendable, Equatable {
            case inProgress
            case completed
        }
    }

    struct ChatMessage: Identifiable, Sendable {
        let id: UUID
        enum Role { case user, assistant }
        let role: Role
        var content: String
        var bias: MarketBias?
        var confidence: Double?
        var sources: [NewsCitation]
        var researchSteps: [ResearchStepItem]
        var isGenerating: Bool

        init(
            id: UUID = UUID(),
            role: Role,
            content: String,
            bias: MarketBias? = nil,
            confidence: Double? = nil,
            sources: [NewsCitation] = [],
            researchSteps: [ResearchStepItem] = [],
            isGenerating: Bool = false
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.bias = bias
            self.confidence = confidence
            self.sources = sources
            self.researchSteps = researchSteps
            self.isGenerating = isGenerating
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

    // MARK: - Output State

    private(set) var messages: [ChatMessage] = []
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

        let assistantMessageId = UUID()
        let userMsg = ChatMessage(role: .user, content: prompt)
        let initialPhase = ChatResearchPhase.readingNews(sources: "Financial news")
        let assistantMsg = ChatMessage(
            id: assistantMessageId,
            role: .assistant,
            content: "",
            researchSteps: [
                ResearchStepItem(
                    id: initialPhase.id,
                    title: initialPhase.title,
                    iconName: initialPhase.iconName,
                    status: .inProgress
                )
            ],
            isGenerating: true
        )
        inputText = ""
        messages.append(contentsOf: [userMsg, assistantMsg])

        Task {
            isProcessing = true
            defer { isProcessing = false }
            do {
                let response = try await chatUseCase.ask(prompt) { [weak self] phase in
                    guard let self else { return }
                    self.updateResearchStep(for: assistantMessageId, phase: phase)
                }

                self.finalizeMessage(for: assistantMessageId, response: response)
            } catch {
                self.failMessage(for: assistantMessageId, error: error.localizedDescription)
            }
        }
    }

    func resetSession() {
        chatUseCase.resetSession()
        messages = []
    }

    // MARK: - Private

    private func append(_ message: ChatMessage) {
        messages.append(message)
    }

    private func updateResearchStep(for id: UUID, phase: ChatResearchPhase) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        var steps = messages[index].researchSteps

        // Mark all previous steps as completed
        for i in 0..<steps.count {
            steps[i].status = .completed
        }

        // Add new step as inProgress if not present
        if let existingIdx = steps.firstIndex(where: { $0.id == phase.id }) {
            steps[existingIdx].status = .inProgress
            steps[existingIdx].title = phase.title
        } else {
            steps.append(ResearchStepItem(
                id: phase.id,
                title: phase.title,
                iconName: phase.iconName,
                status: .inProgress
            ))
        }

        messages[index].researchSteps = steps
    }

    private func finalizeMessage(for id: UUID, response: AIResponse) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        var steps = messages[index].researchSteps
        for i in 0..<steps.count {
            steps[i].status = .completed
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            messages[index].researchSteps = steps
            messages[index].content = response.answer
            messages[index].bias = response.bias
            messages[index].confidence = response.confidence
            messages[index].sources = response.sources
            messages[index].isGenerating = false
        }
    }

    private func failMessage(for id: UUID, error: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            messages[index].content = "Maaf, terjadi kendala: \(error)"
            messages[index].isGenerating = false
        }
    }
}
