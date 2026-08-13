import SwiftUI
import UIKit

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var inputFocused: Bool
    @State private var showsClearConfirmation = false
    @State private var keyboardVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appVisualMode) private var visualMode
    @EnvironmentObject private var companionStore: CompanionModeStore

    private let isMockMode: Bool
    private let localParticipant: ChatParticipant
    private let onReconfigure: () -> Void

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    init(
        viewModel: @autoclosure @escaping () -> ChatViewModel,
        isMockMode: Bool,
        localParticipant: ChatParticipant = .user,
        onReconfigure: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.isMockMode = isMockMode
        self.localParticipant = localParticipant
        self.onReconfigure = onReconfigure
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            stateContent
                            ForEach(viewModel.messages) { message in
                                ChatMessageBubble(
                                    message: message,
                                    localParticipant: localParticipant,
                                    groupedWithPrevious: isGrouped(message: message, direction: -1),
                                    groupedWithNext: isGrouped(message: message, direction: 1)
                                )
                                .id(message.id)
                                .transition(messageTransition)
                                .padding(.top, messageSpacingBefore(message))

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
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
                            value: viewModel.messages.map(\.id)
                        )
                    }
                    .defaultScrollAnchor(.bottom)
                    .defaultScrollAnchor(keyboardVisible ? .bottom : .top, for: .alignment)
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
                        guard !keyboardVisible else { return }
                        keyboardVisible = true
                        // keyboardDidShow 与 SwiftUI safe-area 的最终布局提交不完全同步。
                        // 下一轮主线程再锚底，避免按过渡期高度计算出多余底部空白。
                        DispatchQueue.main.async {
                            scrollToBottomWithoutAnimation(proxy)
                        }
                    }
                    .onReceive(
                        NotificationCenter.default.publisher(
                            for: UIResponder.keyboardDidHideNotification
                        )
                    ) { _ in
                        guard keyboardVisible else { return }
                        keyboardVisible = false
                        // 键盘完全收起、Tab Bar 恢复最终高度后只锚一次，避免还要手动再滑一下。
                        DispatchQueue.main.async {
                            scrollToBottomWithoutAnimation(proxy)
                        }
                    }
                }

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
                            await viewModel.send(
                                companionTypeID: companionStore.current.rawValue,
                                senderParticipant: localParticipant
                            )
                        }
                    },
                    inputFocused: $inputFocused
                )
            }
            .background(chatBackdrop)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    chatNavigationTitle
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    PrivacyAvatar(size: 30, tappable: false, style: .thumbnail)
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                    chatOptionsMenu
                }
            }
        }
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

    private var chatNavigationTitle: some View {
        VStack(spacing: 1) {
            Text("小猫")
                .font(.headline)
                .foregroundStyle(Theme.v2Ink)
            HStack(spacing: 4) {
                Circle()
                    .fill(isMockMode ? visual.textTertiary : Theme.online)
                    .frame(width: 5, height: 5)
                Text(companionStore.current.displayName)
                if isMockMode {
                    Text("· 离线")
                        .accessibilityIdentifier("chat.mode.mock")
                }
            }
            .font(.caption2)
            .foregroundStyle(visual.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("小猫，\(companionStore.current.displayName)\(isMockMode ? "，离线" : "")")
        .accessibilityIdentifier("chat.header")
        .onTapGesture { inputFocused = false }
    }

    private var chatOptionsMenu: some View {
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
                .font(.system(size: 17, weight: .semibold))
        }
        .accessibilityLabel("聊天选项")
        .accessibilityIdentifier("chat.clear")
    }

    private func scrollToBottomWithoutAnimation(_ proxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo("chat.bottom", anchor: .bottom)
        }
    }

    private var messageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .bottom)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.97, anchor: .bottom)),
            removal: .opacity
        )
    }

    private var chatBackdrop: some View {
        ZStack {
            Theme.v2Paper
            LinearGradient(
                colors: [Theme.v2Lavender.opacity(0.18), .clear, Theme.v2CoralSoft.opacity(0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var stateContent: some View {
        if viewModel.isLoadingHistory {
            HStack(spacing: Theme.Spacing.xSmall) {
                ProgressView()
                Text("正在加载聊天记录…")
                    .font(Theme.subheadFont)
                    .foregroundStyle(visual.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .accessibilityIdentifier("chat.loading")
        } else if !viewModel.errorMessage.isEmpty {
            errorCard
        } else if viewModel.hasLoadedHistory && viewModel.messages.isEmpty {
            EmptyState(
                title: "还没有聊天记录",
                detail: "从一句轻松的话开始，开发者会在真实入口回复，小猫按当前模式参与。",
                systemImage: "message"
            )
            .accessibilityIdentifier("chat.empty")
        }
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Label(viewModel.errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.subheadFont)
                .foregroundStyle(visual.textPrimary)

            HStack(spacing: Theme.Spacing.small) {
                if viewModel.canRetryHistory {
                    Button("重试") {
                        Task { await viewModel.loadHistory() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(visual.primary)
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
        .background(visual.surface)
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
                    .foregroundStyle(visual.textPrimary)
                Text("已有消息已经保存，可以只重试小猫。")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(visual.textSecondary)
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
            .tint(visual.primary)
            .disabled(!viewModel.canRetryXiaomao(turnID: turnID))
        }
        .padding(12)
        .background(visual.surfaceSoft)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("chat.xiaomao.retry.\(turnID)")
    }

    private var degradedNotice: some View {
        Label("刚才的回复由服务端安全降级生成", systemImage: "shield.lefthalf.filled")
            .font(Theme.captionFont)
            .foregroundStyle(visual.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(visual.surfaceSoft)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("chat.degraded")
    }

    private func isGrouped(message: ChatMessage, direction: Int) -> Bool {
        guard let index = viewModel.messages.firstIndex(where: { $0.id == message.id }) else {
            return false
        }
        let otherIndex = index + direction
        guard viewModel.messages.indices.contains(otherIndex) else { return false }
        let other = viewModel.messages[otherIndex]
        return message.participant == other.participant
            && message.role == other.role
            && message.turnID == other.turnID
    }

    private func isLastMessageInTurn(_ message: ChatMessage) -> Bool {
        viewModel.messages.last(where: { $0.turnID == message.turnID })?.id == message.id
    }

    private func messageSpacingBefore(_ message: ChatMessage) -> CGFloat {
        guard let index = viewModel.messages.firstIndex(where: { $0.id == message.id }),
              index > viewModel.messages.startIndex else {
            return 4
        }
        let previous = viewModel.messages[index - 1]
        return previous.participant == message.participant ? 2 : 10
    }
}

#Preview {
    ChatView(
        viewModel: ChatViewModel(service: MockChatService(delays: .zero)),
        isMockMode: true
    )
    .environmentObject(CompanionModeStore())
}
