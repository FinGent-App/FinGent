// Features/Chat/ViewModel/ChatViewModel.swift

import Foundation
import Observation

@Observable
@MainActor
final class ChatViewModel {

    // MARK: - Types

    struct ChatMessage: Identifiable {
        let id = UUID()
        enum Role { case user, assistant }
        let role: Role
        let content: String
    }

    // MARK: - Constants

    static let quickPrompts = [
        "📊 Ringkasan Portofolio",
        "📈 Saham Penggerak IHSG",
        "⚖️ Bandingkan GOTO vs BBRI",
        "📰 Berita Portofolio Saya",
        "⚡ Dampak Suku Bunga"
    ]

    private static let welcomeMessage = ChatMessage(
        role: .assistant,
        content: "Halo! Saya FinGent AI Assistant 🤖\n\nSaya terhubung langsung dengan portofolio kamu dan 16 tools pasar modal. Tanyakan apa saja tentang performa portofolio, perbandingan saham, atau berita terkini!"
    )

    // MARK: - Output State

    private(set) var messages: [ChatMessage] = [welcomeMessage]
    private(set) var isProcessing: Bool = false
    var inputText: String = ""

    // MARK: - Dependencies

    private var agent = FinGentAgent()

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
                let reply = try await agent.ask(prompt)
                append(.init(role: .assistant, content: reply))
            } catch {
                append(.init(role: .assistant, content: "Maaf, terjadi kendala: \(error.localizedDescription)"))
            }
        }
    }

    func resetSession() {
        agent.resetSession()
        messages = [Self.welcomeMessage]
    }

    // MARK: - Private

    private func append(_ message: ChatMessage) {
        messages.append(message)
    }
}
