// Features/Chat/View/FinGentChatSheetView.swift

import SwiftUI

struct FinGentChatSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AppContainer.shared.makeChatViewModel()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.14).ignoresSafeArea()
                VStack(spacing: 0) {
                    messageList
                    quickPromptsBar
                    inputBar
                }
            }
            .navigationTitle("FinGent AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages) { msg in
                        ChatBubbleView(message: msg)
                    }
                    if viewModel.isProcessing {
                        processingIndicator
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.isProcessing) { _, isProc in
                if isProc {
                    withAnimation { proxy.scrollTo("loading_indicator", anchor: .bottom) }
                }
            }
        }
    }

    private var processingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().tint(.cyan)
            Text("FinGent sedang menganalisis...")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .id("loading_indicator")
    }

    // MARK: - Quick Prompts

    private var quickPromptsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChatViewModel.quickPrompts, id: \.self) { prompt in
                    Button { viewModel.send(prompt) } label: {
                        Text(prompt)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background {
                                Capsule()
                                    .fill(.cyan.opacity(0.12))
                                    .overlay { Capsule().stroke(.cyan.opacity(0.3), lineWidth: 1) }
                            }
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
                .background { RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)) }
                .onSubmit { viewModel.send(viewModel.inputText) }

            Button { viewModel.send(viewModel.inputText) } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(isSendDisabled ? .white.opacity(0.2) : .cyan)
            }
            .disabled(isSendDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var isSendDisabled: Bool {
        viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isProcessing
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Tutup") { dismiss() }.foregroundStyle(.white.opacity(0.7))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { viewModel.resetSession() } label: {
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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                assistantAvatar
            } else {
                Spacer(minLength: 40)
            }

            Text(message.content)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background { bubble }

            if message.role == .user {
                userAvatar
            } else {
                Spacer(minLength: 40)
            }
        }
    }

    private var bubble: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(
                message.role == .user
                    ? LinearGradient(colors: [.cyan.opacity(0.8), .blue.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
    }

    private var assistantAvatar: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.cyan)
            .frame(width: 28, height: 28)
            .background { Circle().fill(.cyan.opacity(0.2)) }
    }

    private var userAvatar: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: 28, height: 28)
            .background { Circle().fill(.white.opacity(0.15)) }
    }
}
