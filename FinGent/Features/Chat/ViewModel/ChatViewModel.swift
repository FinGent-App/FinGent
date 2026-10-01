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

    enum ChatFeedbackType: String, Codable, Sendable {
        case like
        case dislike
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
        var userPrompt: String?
        var feedback: ChatFeedbackType?
        var traceId: String?

        init(
            id: UUID = UUID(),
            role: Role,
            content: String,
            bias: MarketBias? = nil,
            confidence: Double? = nil,
            sources: [NewsCitation] = [],
            researchSteps: [ResearchStepItem] = [],
            isGenerating: Bool = false,
            userPrompt: String? = nil,
            feedback: ChatFeedbackType? = nil,
            traceId: String? = nil
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.bias = bias
            self.confidence = confidence
            self.sources = sources
            self.researchSteps = researchSteps
            self.isGenerating = isGenerating
            self.userPrompt = userPrompt
            self.feedback = feedback
            self.traceId = traceId
        }
    }

    // MARK: - Constants

    static let quickPrompts = [
        "📊 Portfolio Summary",
        "⚡ Will MU go up or down?",
        "📰 Latest catalyst news for NVDA",
        "📈 Top Market Movers",
        "⚖️ Compare GOTO vs BBRI"
    ]

    // MARK: - Output State

    private(set) var messages: [ChatMessage] = []
    private(set) var isProcessing: Bool = false
    var inputText: String = ""

    // MARK: - Speech Recognition State

    let speechService: SpeechRecognizerService

    var isListening: Bool {
        speechService.isListening
    }

    var latestWord: String {
        speechService.latestWord
    }

    var recognizedWords: [String] {
        speechService.recognizedWords
    }

    var speechTranscript: String {
        speechService.transcript
    }

    var speechErrorMessage: String? {
        speechService.errorMessage
    }

    var audioLevel: CGFloat {
        speechService.audioLevel
    }

    var isSpeaking: Bool {
        speechService.isSpeaking
    }

    var speechLocale: SpeechRecognizerService.SpeechLocale {
        speechService.selectedLocale
    }

    // MARK: - Dependencies

    private let chatUseCase: ChatUseCaseProtocol

    // MARK: - Init

    init(
        chatUseCase: ChatUseCaseProtocol,
        speechService: SpeechRecognizerService
    ) {
        self.chatUseCase = chatUseCase
        self.speechService = speechService
        self.speechService.onSilenceDetected = { [weak self] fullText in
            guard let self = self else { return }
            let prompt = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty, !self.isProcessing else { return }
            self.send(prompt)
        }
    }

    convenience init(chatUseCase: ChatUseCaseProtocol) {
        self.init(chatUseCase: chatUseCase, speechService: SpeechRecognizerService())
    }

    convenience init() {
        self.init(chatUseCase: ChatUseCase())
    }

    // MARK: - Speech Actions

    func startListening() {
        speechService.startListening()
    }

    func stopListening() {
        speechService.stopListening()
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func toggleSpeechLocale() {
        speechService.selectedLocale = (speechService.selectedLocale == .indonesian) ? .english : .indonesian
    }

    // MARK: - Actions

    func send(_ text: String) {
        stopListening()
        speechService.reset()
        let prompt = text.trimmingCharacters(in: .whitespaces)
        guard !prompt.isEmpty, !isProcessing else { return }

        isProcessing = true

        let currentHistory = messages.map { msg in
            (role: msg.role == .user ? "user" : "assistant", content: msg.content)
        }

        let assistantMessageId = UUID()
        let userMsg = ChatMessage(role: .user, content: prompt)
        let initialPhase = ChatResearchPhase.evaluatingRequest
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
            isGenerating: true,
            userPrompt: prompt
        )
        inputText = ""
        messages.append(contentsOf: [userMsg, assistantMsg])

        Task { [weak self] in
            guard let self else { return }
            defer {
                self.isProcessing = false
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.inputText.isEmpty {
                        self.startListening()
                    }
                }
            }
            do {
                let response = try await self.chatUseCase.ask(prompt, history: currentHistory) { [weak self] phase in
                    guard let self else { return }
                    self.updateResearchStep(for: assistantMessageId, phase: phase)
                }

                self.finalizeMessage(for: assistantMessageId, response: response)
            } catch {
                self.failMessage(for: assistantMessageId, error: error.localizedDescription)
            }
        }
    }

    /// Submits or toggles user feedback (like / dislike) for an assistant response.
    func submitFeedback(for messageId: UUID, type: ChatFeedbackType) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let current = messages[index].feedback
        let newFeedback: ChatFeedbackType? = (current == type) ? nil : type
        messages[index].feedback = newFeedback

        let prompt = messages[index].userPrompt
        let traceId = messages[index].traceId
        let feedbackStr = newFeedback?.rawValue ?? "none"

        Task {
            await StockApiClient.shared.submitFeedback(traceId: traceId, prompt: prompt, feedback: feedbackStr)
        }
    }

    func resetSession() {
        stopListening()
        speechService.reset()
        chatUseCase.resetSession()
        ConversationContextManager.shared.reset()
        messages = []
    }

    // MARK: - Private

    private func append(_ message: ChatMessage) {
        messages.append(message)
    }

    private func updateResearchStep(for id: UUID, phase: ChatResearchPhase) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        var steps = messages[index].researchSteps

        // If the only step is the temporary "evaluatingRequest" placeholder, replace it with the first concrete step
        if steps.count == 1 && steps[0].id == ChatResearchPhase.evaluatingRequest.id {
            steps = [
                ResearchStepItem(
                    id: phase.id,
                    title: phase.title,
                    iconName: phase.iconName,
                    status: .inProgress
                )
            ]
            messages[index].researchSteps = steps
            return
        }

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
            messages[index].traceId = response.traceId
            messages[index].isGenerating = false
        }
    }

    private func failMessage(for id: UUID, error: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            messages[index].content = "Sorry, an error occurred: \(error)"
            messages[index].isGenerating = false
        }
    }
}
