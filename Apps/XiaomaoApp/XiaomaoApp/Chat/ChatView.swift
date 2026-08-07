import SwiftUI
import UIKit

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var inputFocused: Bool
    @State private var showsClearConfirmation = false

    private let isMockMode: Bool
    private let onReconfigure: () -> Void

    init(
        viewModel: @autoclosure @escaping () -> ChatViewModel,
        isMockMode: Bool,
        onReconfigure: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.isMockMode = isMockMode
        self.onReconfigure = onReconfigure
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .onTapGesture { inputFocused = false }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        stateContent
                        ForEach(viewModel.messages) { message in
                            ChatMessageBubble(message: message)
                                .id(message.id)

                            if isLastMessageInTurn(message),
                               viewModel.failedXiaomaoTurns.contains(message.turnID) {
                                xiaomaoRetryCard(turnID: message.turnID)
                            }
                        }

                        if viewModel.isSending {
                            ChatTypingIndicator()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if viewModel.lastReplyWasDegraded {
                            degradedNotice
                        }

                        Color.clear.frame(height: 1).id("chat.bottom")
                    }
                    .padding(.horizontal, Theme.Spacing.medium)
                    .padding(.vertical, Theme.Spacing.small)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.immediately)
                .simultaneousGesture(
                    TapGesture().onEnded { _ in inputFocused = false }
                )
                .refreshable {
                    await viewModel.refreshHistorySilently()
                }
                .accessibilityIdentifier("chat.messages")
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo("chat.bottom", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.isSending) { _, _ in
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo("chat.bottom", anchor: .bottom)
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIResponder.keyboardDidShowNotification
                    )
                ) { _ in
                    // 让系统键盘 safe-area 完成布局后再锚到底部，避免 TabView 自己再算一份键盘高度。
                    proxy.scrollTo("chat.bottom", anchor: .bottom)
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIResponder.keyboardDidHideNotification
                    )
                ) { _ in
                    // 键盘完全收起、Tab Bar 恢复最终高度后再次锚底，避免还要手动再滑一下。
                    DispatchQueue.main.async {
                        proxy.scrollTo("chat.bottom", anchor: .bottom)
                    }
                }
            }

            modeFooter
                .onTapGesture { inputFocused = false }

            ChatComposerView(
                draft: $viewModel.draft,
                canSend: viewModel.canSend,
                isBusy: viewModel.isBusy,
                isSending: viewModel.isSending,
                characterLimit: ChatViewModel.maximumMessageLength,
                send: {
                    inputFocused = false
                    Task {
                        await Task.yield()
                        await viewModel.send()
                    }
                },
                inputFocused: $inputFocused
            )
        }
        .background(Theme.bg.ignoresSafeArea())
        .accessibilityIdentifier("chat.root")
        .task {
            await viewModel.loadHistoryIfNeeded()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                await viewModel.refreshHistorySilently()
            }
        }
        .confirmationDialog(
            "清空聊天记录？",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空聊天记录", role: .destructive) {
                Task { await viewModel.clear() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("服务器中的聊天历史也会被清空，此操作无法撤销。")
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("聊天")
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                Text("开发者和小猫都在")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack {
                if isMockMode {
                    Text("离线")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Theme.surfaceWarm)
                        .clipShape(Capsule())
                        .accessibilityIdentifier("chat.mode.mock")
                }
                Spacer()
                Menu {
                    Section("小猫参与方式") {
                        ForEach(XiaomaoParticipationMode.allCases, id: \.self) { mode in
                            Button {
                                viewModel.xiaomaoMode = mode
                            } label: {
                                Label(
                                    mode.title,
                                    systemImage: viewModel.xiaomaoMode == mode
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                            }
                        }
                    }
                    if viewModel.canClear {
                        Button("清空聊天记录", role: .destructive) {
                            showsClearConfirmation = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("聊天选项")
                .accessibilityIdentifier("chat.clear")
            }
        }
        .frame(minHeight: 58)
        .padding(.horizontal, Theme.Spacing.medium)
        .background(Theme.bgElevated.opacity(0.96))
        .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
        .accessibilityIdentifier("chat.header")
    }

    @ViewBuilder
    private var stateContent: some View {
        if viewModel.isLoadingHistory {
            HStack(spacing: Theme.Spacing.xSmall) {
                ProgressView()
                Text("正在加载聊天记录…")
                    .font(Theme.subheadFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .accessibilityIdentifier("chat.loading")
        } else if !viewModel.errorMessage.isEmpty {
            errorCard
        } else if viewModel.hasLoadedHistory && viewModel.messages.isEmpty {
            VStack(spacing: Theme.Spacing.small) {
                Text("🐱")
                    .font(.system(size: 38))
                Text("还没有聊天记录")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.textPrimary)
                Text("从一句轻松的话开始，开发者会在真实入口回复，小猫按当前模式参与。")
                    .font(Theme.subheadFont)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 42)
            .accessibilityIdentifier("chat.empty")
        }
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Label(viewModel.errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.subheadFont)
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: Theme.Spacing.small) {
                if viewModel.canRetryHistory {
                    Button("重试") {
                        Task { await viewModel.loadHistory() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                    .accessibilityIdentifier("chat.retry")
                }
                if viewModel.requiresReconfiguration {
                    Button("重新配置连接", action: onReconfigure)
                        .buttonStyle(.bordered)
                }
                if !viewModel.canRetryHistory && !viewModel.requiresReconfiguration {
                    Button("关闭") { viewModel.clearError() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(Theme.Spacing.medium)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .stroke(Theme.danger.opacity(0.22), lineWidth: 1)
        }
        .accessibilityIdentifier("chat.error")
    }

    private func xiaomaoRetryCard(turnID: String) -> some View {
        HStack(spacing: Theme.Spacing.xSmall) {
            Text("🐱")
                .font(.system(size: 17))
            VStack(alignment: .leading, spacing: 2) {
                Text("小猫这一轮没有接上")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textPrimary)
                Text("已有消息已经保存，可以只重试小猫。")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                Task { await viewModel.retryXiaomao(turnID: turnID) }
            } label: {
                if viewModel.retryingXiaomaoTurnID == turnID {
                    ProgressView().controlSize(.small)
                } else {
                    Text("重试")
                }
            }
            .buttonStyle(.bordered)
            .tint(Theme.primary)
            .disabled(!viewModel.canRetryXiaomao(turnID: turnID))
        }
        .padding(12)
        .background(Color(hex: 0xFFF3ED))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("chat.xiaomao.retry.\(turnID)")
    }

    private var degradedNotice: some View {
        Label("刚才的回复由服务端安全降级生成", systemImage: "shield.lefthalf.filled")
            .font(Theme.captionFont)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.surfaceWarm)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("chat.degraded")
    }

    private var modeFooter: some View {
        HStack(spacing: 6) {
            Text("🐱")
                .font(.system(size: 13))
            Text(viewModel.xiaomaoMode.footerTitle)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.primary)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.medium)
        .padding(.vertical, 7)
        .background(Theme.bgElevated)
        .accessibilityIdentifier("chat.xiaomao.mode")
    }

    private func isLastMessageInTurn(_ message: ChatMessage) -> Bool {
        viewModel.messages.last(where: { $0.turnID == message.turnID })?.id == message.id
    }
}

#Preview {
    ChatView(
        viewModel: ChatViewModel(service: MockChatService(delays: .zero)),
        isMockMode: true
    )
}
