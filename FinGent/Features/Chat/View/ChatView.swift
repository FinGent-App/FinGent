// Features/Chat/View/ChatView.swift

import SwiftUI

struct ChatView: View {
    @State private var viewModel = AppContainer.shared.makeChatViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var selectedSafariURL: IdentifiableURL? = nil

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                agentHeaderBadge
                messageList
                quickPromptsBar
                inputBar
            }
        }
        .navigationTitle("FinGent AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.resetSession()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.7))
                }
            }
        }
        .sheet(item: $selectedSafariURL) { item in
            SafariView(url: item.url)
        }
        .preferredColorScheme(.light)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(hex: "DFE4EE"), Color(hex: "D7DDE7")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Agent Status Header

    private var agentHeaderBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 0.0, green: 0.82, blue: 0.61))
                .frame(width: 8, height: 8)
                .overlay {
                    Circle()
                        .stroke(Color(red: 0.0, green: 0.82, blue: 0.61).opacity(0.4), lineWidth: 4)
                }

            Text("RSS Grounded AI • Yahoo Finance & CNBC Live")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.7))

            Spacer()

            Text("News Evidence Active")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.cyan.opacity(0.15))
                .clipShape(Capsule())
                .foregroundStyle(.cyan)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.35))
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages) { msg in
                        ChatBubbleRow(message: msg) { url in
                            selectedSafariURL = IdentifiableURL(url: url)
                        }
                        .id(msg.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.messages.last?.researchSteps.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Quick Prompts Bar

    private var quickPromptsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChatViewModel.quickPrompts, id: \.self) { prompt in
                    Button {
                        viewModel.send(prompt)
                    } label: {
                        Text(prompt)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.45))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.7), lineWidth: 1)
                                    )
                            )
                    }
                    .disabled(viewModel.isProcessing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Tanya saham, misal: Apakah MU akan naik?", text: $viewModel.inputText)
                .font(.system(size: 14))
                .foregroundStyle(Color.black)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isInputFocused ? Color.cyan.opacity(0.5) : Color.black.opacity(0.08), lineWidth: 1)
                        )
                )
                .onSubmit {
                    viewModel.send(viewModel.inputText)
                }

            Button {
                viewModel.send(viewModel.inputText)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(isSendDisabled ? Color.black.opacity(0.2) : Color.cyan)
            }
            .disabled(isSendDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color.white.opacity(0.35)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color.black.opacity(0.06)),
                    alignment: .top
                )
        )
    }

    private var isSendDisabled: Bool {
        viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isProcessing
    }
}

// MARK: - Chat Bubble Row

private struct ChatBubbleRow: View {
    let message: ChatViewModel.ChatMessage
    var onSelectSource: (URL) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.cyan)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.cyan.opacity(0.2)))
            } else {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
                // Asynchronous Research Steps Badges
                if !message.researchSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(message.researchSteps) { step in
                            HStack(spacing: 7) {
                                if step.status == .inProgress {
                                    ProgressView()
                                        .tint(.cyan)
                                        .scaleEffect(0.65)
                                        .frame(width: 14, height: 14)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color(red: 0.0, green: 0.85, blue: 0.6))
                                        .frame(width: 14, height: 14)
                                }

                                Text(step.title)
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(step.status == .inProgress ? Color.cyan : Color.white.opacity(0.85))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(step.status == .inProgress ? Color.cyan.opacity(0.14) : Color.white.opacity(0.06))
                                    .overlay(
                                        Capsule()
                                            .stroke(step.status == .inProgress ? Color.cyan.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .padding(.bottom, message.content.isEmpty ? 0 : 4)
                } else if message.isGenerating && message.content.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.cyan)
                            .scaleEffect(0.7)
                        Text("FinGent AI is initializing...")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.vertical, 4)
                }

                // Optional Market Bias Badge
                if let bias = message.bias {
                    HStack(spacing: 5) {
                        Text(bias.emoji)
                            .font(.system(size: 10))
                        Text("Market Bias: \(bias.label)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(biasColor(bias))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(biasColor(bias).opacity(0.15), in: Capsule())
                }

                // Message text (shown once generated)
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(.white)
                }

                // Sources Section (Only shown if sources exist)
                if !message.sources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "newspaper.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.cyan)

                            Text("Sources (\(message.sources.count))")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.top, 4)

                        VStack(spacing: 6) {
                            ForEach(message.sources) { citation in
                                NewsCitationView(citation: citation) { url in
                                    onSelectSource(url)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground)

            if message.role == .user {
                Image(systemName: "person.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.white.opacity(0.15)))
            } else {
                Spacer(minLength: 40)
            }
        }
    }

    private func biasColor(_ bias: MarketBias) -> Color {
        switch bias {
        case .bullish: return Color(red: 0.0, green: 0.82, blue: 0.52)
        case .bearish: return Color(red: 1.0, green: 0.23, blue: 0.19)
        case .neutral: return Color(red: 0.85, green: 0.85, blue: 0.85)
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.85), Color.blue.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

// Helper extension untuk hex color
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
