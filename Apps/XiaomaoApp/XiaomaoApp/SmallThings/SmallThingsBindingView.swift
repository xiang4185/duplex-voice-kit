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
        .onDisappear {
            store.clearValidation()
        }
    }

    private var localCodeCard: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.primary)

            VStack(spacing: Theme.Spacing.xSmall) {
                Text("我的通用 Mock 绑定码")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.textPrimary)
                Text(Self.spacedCode(SmallThingsStore.localBindingCode))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                    .accessibilityLabel("绑定码 \(SmallThingsStore.localBindingCode)")
            }

            Text("把这个码给对方。本页面只演示离线 UI，不会生成真实邀请关系。")
                .font(Theme.footnoteFont)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

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
            UIPasteboard.general.string = SmallThingsStore.localBindingCode
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

    private var shareButton: some View {
        ShareLink(item: "小猫小事演示绑定码：\(SmallThingsStore.localBindingCode)") {
            Label("系统分享", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity, minHeight: Theme.buttonMinimumHeight)
        }
        .buttonStyle(.bordered)
        .tint(Theme.primary)
        .accessibilityLabel("分享 Mock 绑定码")
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
                        if digits != newValue {
                            code = digits
                        }
                        store.resetBindingFeedback()
                    }
                    .accessibilityIdentifier("smallThings.binding.codeInput")
                    .accessibilityLabel("对方六位绑定码")

                if !code.isEmpty {
                    Button {
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

            Button("提交演示绑定") {
                codeFocused = false
                _ = store.bindDemo(code: code)
                feedbackTrigger += 1
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.primary)
            .font(Theme.headlineFont)
            .frame(maxWidth: .infinity, minHeight: 50)
            .disabled(code.count != 6)
            .accessibilityIdentifier("smallThings.binding.submit")

            if let message = store.bindingFeedback.message,
               store.bindingFeedback != .success {
                Label(message, systemImage: feedbackSymbol)
                    .font(Theme.footnoteFont)
                    .foregroundStyle(feedbackColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("绑定结果：\(message)")
            }

            Text(
                "离线复现：\(SmallThingsStore.successfulPartnerCode) 绑定成功；"
                    + "\(SmallThingsStore.occupiedPartnerCode) 位置已占用；其他六位数字为无效码。"
            )
            .font(.caption2)
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
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
                Text("这是本地 Mock 成功状态，不代表真实账号或设备已经绑定。")
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
                store.unbindDemo()
                code = ""
                copied = false
                feedbackTrigger += 1
            } label: {
                Label("解除演示绑定", systemImage: "link.badge.minus")
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonMinimumHeight)
            }
            .buttonStyle(.bordered)
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
        .accessibilityLabel("演示关系已绑定")
    }

    private var privacyNote: some View {
        Label {
            Text("不会读取真实账号或设备信息，也不会连接生产服务；所有状态仅存在于当前内存。")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield.fill")
        }
        .font(Theme.footnoteFont)
        .foregroundStyle(Theme.textSecondary)
    }

    private var feedbackSymbol: String {
        switch store.bindingFeedback {
        case .occupied: return "person.crop.circle.badge.exclamationmark"
        case .invalidCode: return "xmark.circle.fill"
        case .alreadyBound: return "link.circle.fill"
        case .idle, .success: return "info.circle.fill"
        }
    }

    private var feedbackColor: Color {
        store.bindingFeedback == .occupied ? Theme.warning : Theme.danger
    }

    private static func spacedCode(_ code: String) -> String {
        code.map(String.init).joined(separator: " ")
    }
}
