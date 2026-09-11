// Features/Chat/View/FinGentChatSheetView.swift

import SwiftUI

struct FinGentChatSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AppContainer.shared.makeChatViewModel()
    @FocusState private var isInputFocused: Bool
    @State private var selectedSafariURL: IdentifiableURL? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.14).ignoresSafeArea()
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
            .toolbar { toolbarItems }
            .sheet(item: $selectedSafariURL) { item in
                SafariView(url: item.url)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var isChatting: Bool {
        !viewModel.messages.isEmpty
    }

    // MARK: - Header Text

    private func headerText(isChatting: Bool) -> some View {
        Text("What financial insights\ncan i give you today?")
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .multilineTextAlignment(isChatting ? .leading : .center)
            .foregroundStyle(Color.white.opacity(isChatting ? 0.6 : 0.85))
            .lineSpacing(isChatting ? 1 : 4)
            .scaleEffect(isChatting ? 0.8 : 1.0, anchor: isChatting ? .leading : .center)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.messages) { msg in
                        ChatBubbleView(message: msg) { url in
                            selectedSafariURL = IdentifiableURL(url: url)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.messages.last?.researchSteps.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }



    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Tanya seputar saham atau portofolio...", text: $viewModel.inputText)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background { RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)) }
                .onSubmit {
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
                    .foregroundStyle(isSendDisabled ? .white.opacity(0.2) : .cyan)
            }
            .disabled(isSendDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Color(red: 0.08, green: 0.08, blue: 0.12)
                .overlay(alignment: .top) {
                    Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.08))
                }
        }
    }

    private var isSendDisabled: Bool {
        viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isProcessing
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Tutup") { dismiss() }.foregroundStyle(.white.opacity(0.7))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) {
                    viewModel.resetSession()
                }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

// MARK: - Chat Bubble

private struct ChatBubbleView: View {
    let message: ChatViewModel.ChatMessage
    var onSelectSource: (URL) -> Void = { _ in }

    var body: some View {
        if message.role == .user {
            HStack(spacing: 0) {
                Spacer(minLength: 40)

                Text(message.content)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .lineSpacing(4)
                    .foregroundStyle(Color.cyan)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    if message.content.isEmpty {
                        // Asynchronous Research Steps Badges
                        if !message.researchSteps.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(message.researchSteps) { step in
                                    HStack(spacing: 7) {
                                        if step.status == .inProgress {
                                            ThreeDotsAnimation(color: Color.white.opacity(0.6))
                                        } else {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundStyle(Color.white.opacity(0.85))
                                                .frame(width: 14, height: 14)
                                        }

                                        Text(step.title)
                                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                            .foregroundStyle(Color.white.opacity(step.status == .inProgress ? 0.6 : 0.85))
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(Color.white.opacity(0.06))
                                    )
                                }
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                        }
                    } else {
                        Text(message.content)
                            .font(.system(size: 16))
                            .lineSpacing(5)
                            .foregroundStyle(.white)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))

                        if !message.sources.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 4) {
                                    Image(systemName: "newspaper.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.cyan)
                                    Text("Sources (\(message.sources.count))")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                                .padding(.top, 2)

                                ForEach(message.sources) { citation in
                                    NewsCitationView(citation: citation) { url in
                                        onSelectSource(url)
                                    }
                                }
                            }
                            .padding(.top, 2)
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
