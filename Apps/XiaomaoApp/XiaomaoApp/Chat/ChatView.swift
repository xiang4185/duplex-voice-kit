import SwiftUI
import UIKit

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var inputFocused: Bool
    @State private var showsClearConfirmation = false
    @State private var ambientMotion = false
    @State private var onlinePulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appVisualMode) private var visualMode
    @EnvironmentObject private var companionStore: CompanionModeStore

    private let isMockMode: Bool
    private let localParticipant: ChatParticipant
    @ObservedObject private var avatarStore: ChatAvatarStore
    private let onReconfigure: () -> Void

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }

    init(
        viewModel: @autoclosure @escaping () -> ChatViewModel,
        isMockMode: Bool,
        localParticipant: ChatParticipant = .user,
        avatarStore: ChatAvatarStore,
        onReconfigure: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.isMockMode = isMockMode
        self.localParticipant = localParticipant
        self.avatarStore = avatarStore
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
                                    avatarStore: avatarStore,
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
                    .defaultScrollAnchor(.top, for: .alignment)
                    .scrollDismissesKeyboard(.immediately)
                    .simultaneousGesture(
                        TapGesture().onEnded { _ in inputFocused = false }
                    )
                    .refreshable {
                        await viewModel.refreshHistorySilently()
                        await avatarStore.load()
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
                            for: UIResponder.keyboardWillChangeFrameNotification
                        )
                    ) { notification in
                        followKeyboardTransition(notification, proxy: proxy)
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
                        .characterAlive(
                            phase: viewModel.isSending ? .thinking : .idle,
                            style: .compact
                        )
                        .accessibilityHidden(true)
                    chatOptionsMenu
                }
            }
        }
        .accessibilityIdentifier("chat.root")
        .onAppear {
            ambientMotion = true
            onlinePulse = true
        }
        .task {
            await avatarStore.load()
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
                WarmHaptics.action()
                Task { await viewModel.clear() }
            }
            Button("取消", role: .cancel) {
                WarmHaptics.action()
            }
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
                    .overlay {
                        if !isMockMode {
                            Circle()
                                .stroke(Theme.online.opacity(0.50), lineWidth: 1)
                                .scaleEffect(onlinePulse && !reduceMotion ? 2.5 : 1)
                                .opacity(onlinePulse && !reduceMotion ? 0 : 0.7)
                        }
                    }
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeOut(duration: 2).repeatForever(autoreverses: false),
                        value: onlinePulse
                    )
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
                        WarmHaptics.action()
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
                    WarmHaptics.action()
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

    private func followKeyboardTransition(
        _ notification: Notification,
        proxy: ScrollViewProxy
    ) {
        // 短聊天始终保持顶部对齐。只有输入框仍处于焦点时，才让最新消息
        // 跟随键盘 frame 变化一起让位；收起键盘或浏览历史时不强制锚底。
        guard inputFocused else { return }

        let duration = (
            notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber
        )?.doubleValue ?? 0.25
        let curveRawValue = (
            notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber
        )?.intValue ?? UIView.AnimationCurve.easeInOut.rawValue

        let scroll = {
            proxy.scrollTo("chat.bottom", anchor: .bottom)
        }

        guard !reduceMotion, duration > 0 else {
            scroll()
            return
        }

        withAnimation(keyboardAnimation(duration: duration, curveRawValue: curveRawValue)) {
            scroll()
        }
    }

    private func keyboardAnimation(duration: Double, curveRawValue: Int) -> Animation {
        switch curveRawValue {
        case UIView.AnimationCurve.easeIn.rawValue:
            return .easeIn(duration: duration)
        case UIView.AnimationCurve.easeOut.rawValue:
            return .easeOut(duration: duration)
        case UIView.AnimationCurve.linear.rawValue:
            return .linear(duration: duration)
        default:
            // iOS 键盘有时返回私有 curve 值；退回系统常用的 easeInOut，
            // 但仍严格复用同一 duration，避免消息区晚于键盘结束。
            return .easeInOut(duration: duration)
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

            Circle()
                .fill(Theme.v2Lavender.opacity(0.18))
                .frame(width: 260, height: 260)
                .blur(radius: 48)
                .offset(
                    x: ambientMotion && !reduceMotion ? -92 : -142,
                    y: ambientMotion && !reduceMotion ? -210 : -150
                )
                .scaleEffect(ambientMotion && !reduceMotion ? 1.10 : 0.92)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 11).repeatForever(autoreverses: true),
                    value: ambientMotion
                )

            Circle()
                .fill(Theme.v2CoralSoft.opacity(0.24))
                .frame(width: 230, height: 230)
                .blur(radius: 52)
                .offset(
                    x: ambientMotion && !reduceMotion ? 130 : 92,
                    y: ambientMotion && !reduceMotion ? 250 : 310
                )
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: 14).repeatForever(autoreverses: true),
                    value: ambientMotion
                )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
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
                        WarmHaptics.action()
                        Task { await viewModel.loadHistory() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(visual.primary)
                    .accessibilityIdentifier("chat.retry")
                }
                if viewModel.requiresReconfiguration {
                    Button("重新配置连接") {
                        WarmHaptics.action()
                        onReconfigure()
                    }
                        .buttonStyle(.bordered)
                }
                if !viewModel.canRetryHistory && !viewModel.requiresReconfiguration {
                    Button("关闭") {
                        WarmHaptics.action()
                        viewModel.clearError()
                    }
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
                WarmHaptics.action()
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
        isMockMode: true,
        avatarStore: ChatAvatarStore(
            service: ChatAvatarService(backend: MockBackendAdapter(), targetDeviceID: nil),
            localParticipant: .user
        )
    )
    .environmentObject(CompanionModeStore())
}
