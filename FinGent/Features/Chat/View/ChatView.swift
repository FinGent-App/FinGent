// Features/Chat/View/ChatView.swift

import SwiftUI

struct ChatView: View {
    @State private var viewModel = AppContainer.shared.makeChatViewModel()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.09).ignoresSafeArea()

                VStack(spacing: 0) {
                    agentHeaderBadge
                    messageList
                    quickPromptsBar
                    inputBar
                }
            }
            .navigationTitle("FinGent AI")
            .navigationBarTitleDisplayMode(.inline)
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
                        .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
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

            Text("Agentic AI System • 16 Market Tools Active")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            Text("LLM Foundation")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .foregroundStyle(.cyan)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages) { msg in
                        ChatBubbleRow(message: msg)
                            .id(msg.id)
                    }

                    if viewModel.isProcessing {
                        processingRow
                            .id("processing_indicator")
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
            .onChange(of: viewModel.isProcessing) { _, isProc in
                if isProc {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("processing_indicator", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var processingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.cyan)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.cyan.opacity(0.2)))

            HStack(spacing: 8) {
                ProgressView().tint(.cyan)
                Text("FinGent sedang menganalisis...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )

            Spacer(minLength: 40)
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
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.cyan.opacity(0.12))
                                    .overlay(Capsule().stroke(Color.cyan.opacity(0.3), lineWidth: 1))
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
            TextField("Tanya seputar saham atau portofolio...", text: $viewModel.inputText)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(isInputFocused ? Color.cyan.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
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
                    .foregroundStyle(isSendDisabled ? Color.white.opacity(0.2) : Color.cyan)
            }
            .disabled(isSendDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Color(red: 0.08, green: 0.08, blue: 0.12)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color.white.opacity(0.08)),
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

            Text(message.content)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(.white)
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
