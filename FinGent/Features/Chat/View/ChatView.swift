// Features/Chat/View/ChatView.swift

import SwiftUI

struct ChatView: View {
    @State private var viewModel = AppContainer.shared.makeChatViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var selectedSafariURL: IdentifiableURL? = nil
    @State private var isMicPulsing: Bool = false
    @State private var isChatInputVisible: Bool = false

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                if !isChatting {
                    Spacer(minLength: 0)

                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if !viewModel.speechTranscript.isEmpty {
                            Text(viewModel.speechTranscript)
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(hex: "0066FF"))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                                .padding(.horizontal, 24)
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        } else {
                            headerText(isChatting: false)
                        }
                        Spacer(minLength: 0)
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.speechTranscript.isEmpty)
                    .padding(.bottom, 32)
                }

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

                if isChatInputVisible {
                    inputBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    ZStack {
                        // Lingkaran Liquid Video dengan Gelombang Border
                        let circleSize: CGFloat = isChatting ? 76 : 88
                        ZStack(alignment: .center) {
                            CircleBorderWaveView(
                                diameter: circleSize,
                                isListening: viewModel.isListening,
                                audioLevel: viewModel.audioLevel
                            )

                            Circle()
                                .fill(Color.white)
                                .frame(width: circleSize, height: circleSize)
                                .shadow(
                                    color: Color.black.opacity(0.18),
                                    radius: 12,
                                    x: 0,
                                    y: 6
                                )

                            LoopingVideoPlayerView(
                                videoName: "liquid-circle",
                                videoExtension: "mp4"
                            )
                            .frame(width: circleSize, height: circleSize)
                            .scaleEffect(1.2, anchor: .center)
                            .clipShape(Circle())
                        }
                        .frame(width: circleSize, height: circleSize)
                        .scaleEffect(viewModel.isProcessing ? 0.5 : 1.0, anchor: .center)
                        .opacity(viewModel.isProcessing ? 0.5 : 1.0)
                        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: viewModel.isProcessing)
                        .onTapGesture {
                            guard !viewModel.isProcessing else { return }
                            if !viewModel.speechTranscript.isEmpty {
                                viewModel.send(viewModel.speechTranscript)
                            } else {
                                viewModel.toggleListening()
                            }
                        }

                        // Floating keyboard di kanan bawah
                        HStack {
                            Spacer()
                            floatingKeyboardButton
                        }
                    }
                    .padding(.bottom, isChatting ? 12 : 48)
                }

                if !isChatting {
                    Spacer(minLength: 0)
                }
            }
            .animation(.spring(response: 0.85, dampingFraction: 0.88), value: viewModel.messages.isEmpty)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isInputFocused {
                isInputFocused = false
                if viewModel.inputText.isEmpty {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        isChatInputVisible = false
                    }
                }
            }
        }
        .onAppear {
            viewModel.startListening()
            isMicPulsing = true
        }
        .onDisappear {
            viewModel.stopListening()
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
        .overlay(alignment: .top) {
            if isChatting {
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.25), location: 0.0),
                        .init(color: Color.black.opacity(0.12), location: 0.45),
                        .init(color: Color.black.opacity(0.03), location: 0.8),
                        .init(color: Color.clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 105)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
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
                        ChatBubbleRow(
                            message: msg,
                            onFeedback: { fb in
                                viewModel.submitFeedback(for: msg.id, type: fb)
                            },
                            onSelectSource: { url in
                                selectedSafariURL = IdentifiableURL(url: url)
                            }
                        )
                        .id(msg.id)
                    }

                    if !viewModel.speechTranscript.isEmpty {
                        HStack(spacing: 0) {
                            Spacer(minLength: 40)

                            Text(viewModel.speechTranscript)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .lineSpacing(4)
                                .foregroundStyle(Color(hex: "0066FF"))
                                .multilineTextAlignment(.trailing)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 148)
                .padding(.bottom, 96)
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
        HStack(spacing: 6) {
            Button {
                viewModel.toggleListening()
            } label: {
                ZStack {
                    if viewModel.isListening {
                        Circle()
                            .fill(Color(hex: "0066FF").opacity(0.18))
                            .frame(width: 32, height: 32)
                            .scaleEffect(isMicPulsing ? 1.25 : 0.95)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isMicPulsing)
                    }

                    Image(systemName: viewModel.isListening ? "waveform.and.mic" : "mic.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(viewModel.isListening ? Color(hex: "0066FF") : Color.black.opacity(0.5))
                        .frame(width: 32, height: 32)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .accessibilityLabel(viewModel.isListening ? "Hentikan mikrofon" : "Mulai bicara")

            TextField("Ask about stocks, e.g., Will MU go up?", text: $viewModel.inputText)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .focused($isInputFocused)
                .padding(.horizontal, 8)
                .padding(.vertical, 11)
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
                    .foregroundStyle(isSendDisabled ? Color.primary.opacity(0.2) : Color.primary)
            }
            .disabled(isSendDisabled)
            .padding(.trailing, 6)
        }
        .padding(.leading, 2)
        .padding(.vertical, 2)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var isSendDisabled: Bool {
        viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isProcessing
    }

    private var floatingKeyboardButton: some View {
        Button {
            viewModel.stopListening()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                isChatInputVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isInputFocused = true
            }
        } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.8))
                .frame(width: 48, height: 48)
                .glassEffect(.regular.interactive(), in: .circle)
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

// MARK: - Chat Bubble Row

struct ChatBubbleRow: View {
    let message: ChatViewModel.ChatMessage
    var onFeedback: ((ChatViewModel.ChatFeedbackType) -> Void)? = nil
    var onSelectSource: (URL) -> Void = { _ in }
    @State private var isCopied: Bool = false

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
            HStack(alignment: .top, spacing: 8) {
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
                        // Top row with response text and copy button at top right
                        HStack(alignment: .top, spacing: 8) {
                            Text(message.content)
                                .font(.system(size: 16.5))
                                .lineSpacing(5)
                                .foregroundStyle(Color.black.opacity(0.88))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                copyResponse()
                            } label: {
                                Image(systemName: isCopied ? "checkmark" : "document.on.document")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(isCopied ? Color(hex: "0066FF") : Color.black.opacity(0.4))
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(Color.black.opacity(0.05)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Salin respon AI")
                        }
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

                        // Like & Dislike Action Row (Icon saja tanpa border)
                        HStack(spacing: 16) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onFeedback?(.like)
                            } label: {
                                Image(systemName: message.feedback == .like ? "hand.thumbsup.fill" : "hand.thumbsup")
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(message.feedback == .like ? Color(hex: "0066FF") : Color.black.opacity(0.35))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Suka respon")

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onFeedback?(.dislike)
                            } label: {
                                Image(systemName: message.feedback == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(message.feedback == .dislike ? Color(hex: "FF3B30") : Color.black.opacity(0.35))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Tidak suka respon")

                            Spacer()
                        }
                        .padding(.top, 4)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.35), value: message.content.isEmpty)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
    }

    private func copyResponse() {
        UIPasteboard.general.string = message.content
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
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
