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
                if !isChatting {
                    Spacer(minLength: 0)
                }

                HStack(spacing: 0) {
                    if !isChatting {
                        Spacer(minLength: 0)
                    }

                    headerText(isChatting: isChatting)

                    Spacer(minLength: 0)
                }
                .padding(.leading, isChatting ? 20 : 0)
                .padding(.top, isChatting ? 12 : 0)
                .padding(.bottom, isChatting ? 8 : 24)

                if isChatting {
                    messageList
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom)
                                    .combined(with: .scale(scale: 0.92, anchor: .bottomTrailing))
                                    .combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                }

                inputBar
            }
            .animation(.spring(response: 0.85, dampingFraction: 0.88), value: viewModel.messages.isEmpty)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) {
                        viewModel.resetSession()
                    }
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

    private var isChatting: Bool {
        !viewModel.messages.isEmpty
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(hex: "DFE4EE"), Color(hex: "D7DDE7")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Header Text

    private func headerText(isChatting: Bool) -> some View {
        Text("What financial insights\ncan i give you today?")
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .multilineTextAlignment(isChatting ? .leading : .center)
            .foregroundStyle(Color.black.opacity(isChatting ? 0.6 : 0.85))
            .lineSpacing(isChatting ? 1 : 4)
            .scaleEffect(isChatting ? 0.8 : 1.0, anchor: isChatting ? .leading : .center)
    }


    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.messages) { msg in
                        ChatBubbleRow(message: msg) { url in
                            selectedSafariURL = IdentifiableURL(url: url)
                        }
                        .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
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
                    guard !isSendDisabled else { return }
                    withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) {
                        viewModel.send(viewModel.inputText)
                    }
                }

            Button {
                withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) {
                    viewModel.send(viewModel.inputText)
                }
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

struct ChatBubbleRow: View {
    let message: ChatViewModel.ChatMessage
    var onSelectSource: (URL) -> Void = { _ in }

    var body: some View {
        if message.role == .user {
            HStack(spacing: 0) {
                Spacer(minLength: 40)

                Text(message.content)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineSpacing(4)
                    .foregroundStyle(Color(hex: "0066FF"))
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    if message.content.isEmpty {
                        // Asynchronous Research Steps Badges (Only while generating)
                        if !message.researchSteps.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(message.researchSteps) { step in
                                    HStack(spacing: 7) {
                                        if step.status == .inProgress {
                                            ThreeDotsAnimation(color: Color.black.opacity(0.3))
                                        } else {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(Color.black.opacity(0.85))
                                                .frame(width: 14, height: 14)
                                        }

                                        Text(step.title)
                                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                            .foregroundStyle(Color.black.opacity(step.status == .inProgress ? 0.3 : 0.75))
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(Color.black.opacity(0.06))
                                    )
                                }
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                        }
                    } else {
                        // Message text (shown once generated)
                        Text(message.content)
                            .font(.system(size: 16.5))
                            .lineSpacing(5)
                            .foregroundStyle(Color.black.opacity(0.88))
                            .transition(.opacity.combined(with: .move(edge: .bottom)))

                        // Sources Section (Prefix source: and circular icons)
                        if !message.sources.isEmpty {
                            let distinctSources = Array(Set(message.sources.map { $0.source })).sorted { $0.displayName < $1.displayName }
                            HStack(spacing: 7) {
                                Text("source:")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.black.opacity(0.5))

                                ForEach(distinctSources, id: \.self) { src in
                                    Button {
                                        if let firstCitation = message.sources.first(where: { $0.source == src }) {
                                            onSelectSource(firstCitation.url)
                                        }
                                    } label: {
                                        SourceLogoView(source: src, size: 20)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 4)
                            .transition(.opacity)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: message.content.isEmpty)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)

                Spacer(minLength: 20)
            }
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
