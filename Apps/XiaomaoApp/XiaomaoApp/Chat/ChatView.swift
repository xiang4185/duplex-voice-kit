import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel

    @FocusState private var inputFocused: Bool
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusArea
                messageArea
                composer
            }
            .background(Theme.homeBackground.ignoresSafeArea())
            .navigationTitle("小猫")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "cat.fill")
                        .foregroundStyle(Theme.primary)
                        .accessibilityHidden(true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showClearConfirmation = true
                    } label: {
                        if viewModel.isClearing {
                            ProgressView()
                        } else {
                            Image(systemName: "trash")
                        }
                    }
                    .accessibilityLabel("清空聊天")
                    .accessibilityIdentifier("chat.clear")
                    .disabled(!viewModel.canClear)
                }
            }
            .confirmationDialog(
                "清空与小猫的聊天记录？",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("清空聊天记录", role: .destructive) {
                    Task { await viewModel.clear() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作会清空服务器上的当前聊天历史，但保留当前会话。")
            }
            .task {
                await viewModel.loadHistoryIfNeeded()
            }
        }
        .accessibilityIdentifier("chat.root")
    }

    @ViewBuilder
    private var statusArea: some View {
        if viewModel.isLoadingHistory {
            HStack(spacing: Theme.Spacing.xSmall) {
                ProgressView()
                Text("正在加载聊天记录…")
            }
            .font(Theme.footnoteFont)
            .foregroundStyle(Theme.textSecondary)
            .padding(.vertical, Theme.Spacing.small)
        } else if !viewModel.errorMessage.isEmpty {
            VStack(spacing: Theme.Spacing.xSmall) {
                Text(viewModel.errorMessage)
                    .font(Theme.footnoteFont)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
                HStack(spacing: Theme.Spacing.medium) {
                    if viewModel.canRetryHistory {
                        Button("重新加载") {
                            Task { await viewModel.loadHistory() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                    }
                    if viewModel.isConfigurationAvailable {
                        Button("关闭") {
                            viewModel.clearError()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.small)
        } else if viewModel.lastReplyWasDegraded {
            Label("刚才的回复由服务端安全降级生成。", systemImage: "exclamationmark.circle")
                .font(Theme.footnoteFont)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.vertical, Theme.Spacing.xSmall)
        }
    }

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.small) {
                    if viewModel.hasLoadedHistory && viewModel.messages.isEmpty {
                        VStack(spacing: Theme.Spacing.small) {
                            Image(systemName: "message")
                                .font(.system(size: 34))
                                .foregroundStyle(Theme.primary)
                            Text("还没有聊天记录")
                                .font(Theme.headlineFont)
                                .foregroundStyle(Theme.textPrimary)
                            Text("写下第一句话，小猫会从服务器回复你。")
                                .font(Theme.footnoteFont)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, Theme.Spacing.xxLarge)
                    }

                    ForEach(viewModel.messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }

                    if viewModel.isSending {
                        HStack(spacing: Theme.Spacing.xSmall) {
                            ProgressView()
                            Text("小猫正在回复…")
                                .font(Theme.footnoteFont)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, Theme.Spacing.medium)
                    }
                }
                .padding(.vertical, Theme.Spacing.medium)
            }
            .accessibilityIdentifier("chat.messages")
            .onChange(of: viewModel.messages.map(\.id)) { _, ids in
                guard let lastID = ids.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.xSmall) {
            if message.role == .user {
                Spacer(minLength: 52)
            } else {
                Image(systemName: "cat.fill")
                    .frame(width: 28, height: 28)
                    .foregroundStyle(Theme.primary)
                    .background(Theme.primarySoft)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            }

            Text(message.content)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, Theme.Spacing.small)
                .padding(.vertical, 10)
                .background(
                    message.role == .user
                        ? Theme.userMessageSurface
                        : Theme.assistantMessageSurface
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                .accessibilityLabel(message.role == .user ? "你：\(message.content)" : "小猫：\(message.content)")

            if message.role == .assistant {
                Spacer(minLength: 52)
            }
        }
        .padding(.horizontal, Theme.Spacing.medium)
    }

    private var composer: some View {
        VStack(spacing: Theme.Spacing.xSmall) {
            Divider()
                .overlay(Theme.border)
            HStack(alignment: .bottom, spacing: Theme.Spacing.xSmall) {
                TextField("对小猫说点什么", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .font(Theme.bodyFont)
                    .padding(.horizontal, Theme.Spacing.small)
                    .padding(.vertical, 10)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    }
                    .accessibilityIdentifier("chat.input")

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(viewModel.canSend ? Theme.primary : Theme.textTertiary)
                        .frame(minWidth: Theme.controlMinimumSize, minHeight: Theme.controlMinimumSize)
                }
                .accessibilityLabel("发送")
                .accessibilityIdentifier("chat.send")
                .disabled(!viewModel.canSend)
            }

            HStack {
                Text(viewModel.draftCharacterCount > ChatViewModel.maximumMessageLength
                     ? "已超过 200 字符"
                     : "最多 200 字符")
                Spacer()
                Text("\(viewModel.draftCharacterCount)/200")
            }
            .font(Theme.captionFont)
            .foregroundStyle(
                viewModel.draftCharacterCount > ChatViewModel.maximumMessageLength
                    ? Theme.danger
                    : Theme.textTertiary
            )
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.top, Theme.Spacing.xSmall)
        .padding(.bottom, Theme.Spacing.small)
        .background(Theme.bgElevated)
    }
}
