import SwiftUI
import UIKit

struct SmallThingsBindingView: View {
    @ObservedObject var store: SmallThingsStore
    @State private var code = ""
    @State private var copied = false
    @State private var feedbackTrigger = 0
    @FocusState private var codeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.large) {
                if store.isDemoBound {
                    boundState
                } else {
                    localCodeCard
                    partnerCodeCard
                }

                if let error = store.operationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.footnoteFont)
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                privacyNote
            }
            .padding(Theme.Spacing.medium)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("一起记")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sensoryFeedback(.impact(weight: .light), trigger: feedbackTrigger)
        .onDisappear { store.clearValidation() }
    }

    private var localCode: String? {
        store.generatedBindingCode
            ?? (store.isProduction ? nil : SmallThingsStore.localBindingCode)
    }

    private var localCodeCard: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.primary)

            VStack(spacing: Theme.Spacing.xSmall) {
                Text(store.isProduction ? "我的绑定码" : "离线 Mock 绑定码")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.textPrimary)

                if let localCode {
                    Text(Self.spacedCode(localCode))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.75)
                        .accessibilityLabel("绑定码 \(localCode)")
                } else {
                    Text("生成后可复制或分享")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Text(
                store.isProduction
                    ? "生成一次性绑定码并交给对方。绑定成功后，双方可共同记录和审批小事。"
                    : "离线 Mock 只复现绑定交互，不连接生产服务。"
            )
            .font(Theme.footnoteFont)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            if localCode != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.small) {
                        copyButton
                        shareButton
                    }
                    VStack(spacing: Theme.Spacing.xSmall) {
                        copyButton
                        shareButton
                    }
                }
            }

            Button(store.generatedBindingCode == nil ? "生成绑定码" : "重新生成绑定码") {
                WarmHaptics.action()
                Task {
                    copied = false
                    if await store.createBindingCodePersisted() {
                        feedbackTrigger += 1
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.primary)
            .disabled(store.isLoading)
        }
        .padding(Theme.Spacing.large)
        .background(Theme.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        }
        .accessibilityIdentifier("smallThings.binding.localCode")
    }

    private var copyButton: some View {
        Button {
            WarmHaptics.action()
            guard let localCode else { return }
            UIPasteboard.general.string = localCode
            copied = true
            feedbackTrigger += 1
        } label: {
            Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                .frame(maxWidth: .infinity, minHeight: Theme.buttonMinimumHeight)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.primary)
        .accessibilityLabel(copied ? "绑定码已复制" : "复制绑定码")
    }

    @ViewBuilder
    private var shareButton: some View {
        if let localCode {
            ShareLink(item: "小猫小事绑定码：\(localCode)") {
                Label("系统分享", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonMinimumHeight)
            }
            .buttonStyle(.bordered)
            .tint(Theme.primary)
            .accessibilityLabel("分享绑定码")
        }
    }

    private var partnerCodeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxSmall) {
                Text("输入对方绑定码")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.textPrimary)
                Text("只允许六位数字")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: Theme.Spacing.xSmall) {
                TextField("000000", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($codeFocused)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.small)
                    .frame(minHeight: 52)
                    .background(Theme.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    }
                    .onChange(of: code) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(6))
                        if digits != newValue { code = digits }
                        store.resetBindingFeedback()
                    }
                    .accessibilityIdentifier("smallThings.binding.codeInput")
                    .accessibilityLabel("对方六位绑定码")

                if !code.isEmpty {
                    Button {
                        WarmHaptics.action()
                        code = ""
                        store.resetBindingFeedback()
                        codeFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("清空绑定码")
                }
            }

            Button(store.isProduction ? "提交绑定" : "提交离线绑定") {
                WarmHaptics.action()
                codeFocused = false
                Task {
                    if await store.bindPersisted(code: code) {
                        feedbackTrigger += 1
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.primary)
            .font(Theme.headlineFont)
            .frame(maxWidth: .infinity, minHeight: 50)
            .disabled(code.count != 6 || store.isLoading)
            .accessibilityIdentifier("smallThings.binding.submit")

            if let message = store.bindingFeedback.message,
               store.bindingFeedback != .success {
                Label(message, systemImage: feedbackSymbol)
                    .font(Theme.footnoteFont)
                    .foregroundStyle(feedbackColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("绑定结果：\(message)")
            }

            if !store.isProduction {
                Text(
                    "离线复现：\(SmallThingsStore.successfulPartnerCode) 绑定成功；"
                        + "\(SmallThingsStore.occupiedPartnerCode) 已占用；其他六位数字为无效码。"
                )
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.medium)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        }
    }

    private var boundState: some View {
        VStack(spacing: Theme.Spacing.large) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 58, weight: .semibold))
                .foregroundStyle(Theme.success)

            VStack(spacing: Theme.Spacing.xSmall) {
                Text("已经一起记啦")
                    .font(Theme.title2Font)
                    .foregroundStyle(Theme.textPrimary)
                Text(
                    store.isProduction
                        ? "当前关系已由服务端确认，小事记录会在双方设备间同步。"
                        : "这是离线 Mock 绑定状态。"
                )
                .font(Theme.footnoteFont)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            Label("已绑定", systemImage: "checkmark.seal.fill")
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.success)
                .padding(.horizontal, Theme.Spacing.medium)
                .padding(.vertical, Theme.Spacing.xSmall)
                .background(Theme.success.opacity(0.12), in: Capsule())

            Button(role: .destructive) {
                WarmHaptics.action()
                Task {
                    await store.unbindPersisted()
                    code = ""
                    copied = false
                    feedbackTrigger += 1
                }
            } label: {
                Label("解除绑定", systemImage: "link.badge.minus")
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonMinimumHeight)
            }
            .buttonStyle(.bordered)
            .disabled(store.isLoading)
            .accessibilityIdentifier("smallThings.binding.unbind")
        }
        .padding(Theme.Spacing.large)
        .frame(maxWidth: .infinity)
        .background(Theme.surfaceWarm)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.xLarge, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("关系已绑定")
    }

    private var privacyNote: some View {
        Label {
            Text(
                store.isProduction
                    ? "绑定和小事数据仅通过当前设备凭据访问，不会写入公共仓库或构建产物。"
                    : "离线 Mock 状态仅存在于当前 App 运行期间。"
            )
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield.fill")
        }
        .font(Theme.footnoteFont)
        .foregroundStyle(Theme.textSecondary)
    }

    private var feedbackSymbol: String {
        switch store.bindingFeedback {
        case .occupied: "person.crop.circle.badge.exclamationmark"
        case .invalidCode: "xmark.circle.fill"
        case .alreadyBound: "link.circle.fill"
        case .idle, .success: "info.circle.fill"
        }
    }

    private var feedbackColor: Color {
        store.bindingFeedback == .occupied ? Theme.warning : Theme.danger
    }

    private static func spacedCode(_ code: String) -> String {
        code.map(String.init).joined(separator: " ")
    }
}
