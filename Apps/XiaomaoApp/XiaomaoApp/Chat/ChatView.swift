import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    let modeTitle: String

    @FocusState private var inputFocused: Bool
    @State private var showClearConfirmation = false

    private let bottomAnchor = "chat.bottom"

    init(viewModel: ChatViewModel, modeTitle: String = "离线演示") {
        self.viewModel = viewModel
        self.modeTitle = modeTitle
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                statusArea
                messageArea
                ChatComposerView(
                    draft: $viewModel.draft,
                    canSend: viewModel.canSend,
                    isBusy: viewModel.isBusy,
                    isSending: viewModel.isSending,
                    characterLimit: ChatViewModel.maximumMessageLength,
                    send: { Task { await viewModel.send() } },
                    inputFocused: $inputFocused
                )
            }
            .background(Theme.homeBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(
                "清空当前三人聊天？",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("清空聊天记录", role: .destructive) {
                    Task { await viewModel.clear() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只清空本次运行中的本地消息时间流，不调用服务器清空接口。")
            }
            .task {
                await viewModel.loadHistoryIfNeeded()
            }
        }
        .accessibilityIdentifier("chat.root")
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.small) {
            HStack(spacing: -8) {
                participantAvatar("person.fill", label: "你")
                participantAvatar("cat.fill", label: "小猫")
                participantAvatar("heart.fill", label: "伙伴")
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
                Text("三人聊天")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.textPrimary)

                Label(modeTitle, systemImage: "person.3.fill")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("chat.mode.mock")
            }

            Spacer()

            Button {
                showClearConfirmation = true
            } label: {
                Group {
                    if viewModel.isClearing {
                        ProgressView()
                    } else {
                        Image(systemName: "trash")
                    }
                }
                .frame(
                    minWidth: Theme.controlMinimumSize,
                    minHeight: Theme.controlMinimumSize
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.canClear ? Theme.textSecondary : Theme.textTertiary)
            .disabled(!viewModel.canClear)
            .accessibilityLabel(viewModel.isClearing ? "正在清空聊天" : "清空聊天")
            .accessibilityIdentifier("chat.clear")
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.vertical, Theme.Spacing.small)
        .background(Theme.bgElevated.opacity(0.96))
        .overlay(alignment: .bottom) {
            Divider().overlay(Theme.border)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.header")
    }

    private func participantAvatar(_ symbol: String, label: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 34, height: 34)
            .foregroundStyle(Theme.primary)
            .background(Theme.primarySoft)
            .clipShape(Circle())
            .overlay(Circle().stroke(Theme.bgElevated, lineWidth: 2))
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private var statusArea: some View {
        if viewModel.isLoadingHistory {
            Label("正在准备本地消息时间流", systemImage: "clock")
                .font(Theme.footnoteFont)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.vertical, Theme.Spacing.small)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("chat.loading")
        } else if !viewModel.errorMessage.isEmpty {
            VStack(spacing: Theme.Spacing.xSmall) {
                Label(viewModel.errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.footnoteFont)
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)

                HStack(spacing: Theme.Spacing.small) {
                    if viewModel.requiresReconfiguration {
                        Button("重新配置连接") {
                            NotificationCenter.default.post(
                                name: .reconfigureConnection,
                                object: nil
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                        .accessibilityIdentifier("chat.reconfigure")
                    }
                    if viewModel.canRetryHistory {
                        Button("重新加载") {
                            Task { await viewModel.loadHistory() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                        .accessibilityIdentifier("chat.retry")
                    } else if viewModel.isConfigurationAvailable {
                        Button("关闭") {
                            viewModel.clearError()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.small)
            .frame(maxWidth: .infinity)
            .background(Theme.surface.opacity(0.88))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat.error")
        } else if viewModel.lastReplyWasDegraded {
            Label(
                "刚才的回复由服务端安全降级生成",
                systemImage: "exclamationmark.circle"
            )
            .font(Theme.footnoteFont)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.Spacing.medium)
            .padding(.vertical, Theme.Spacing.xSmall)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("chat.degraded")
        }
    }

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.small) {
                    if viewModel.hasLoadedHistory && viewModel.messages.isEmpty {
                        emptyState
                    }

                    ForEach(viewModel.messages) { message in
                        ChatMessageBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.isSending {
                        ChatTypingIndicator()
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .padding(.vertical, Theme.Spacing.medium)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("chat.messages")
            .onChange(of: viewModel.messages.map(\.id)) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.isLoadingHistory) { _, loading in
                if !loading { scrollToBottom(proxy, animated: false) }
            }
            .onChange(of: viewModel.isSending) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: inputFocused) { _, focused in
                if focused { scrollToBottom(proxy) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.small) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(Theme.primary)
                .accessibilityHidden(true)

            Text("还没有聊天记录")
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.textPrimary)

            Text("从一句简单的话开始。当前版本只在本次运行期间维护消息时间流。")
                .font(Theme.footnoteFont)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.xLarge)
        .padding(.top, Theme.Spacing.xxLarge)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.empty")
    }

    private func scrollToBottom(
        _ proxy: ScrollViewProxy,
        animated: Bool = true
    ) {
        let action = {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        } else {
            action()
        }
    }
}
