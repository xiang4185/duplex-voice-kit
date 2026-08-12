import AVFoundation
import SwiftUI
import UIKit

// MARK: - 屏 7 设置 / 仪表盘 (SettingsView)
// v6.1: 记录卡(未接入) + 彩蛋卡 + 隐私分组(角色形象开关 + 实时语音静态说明) + 授权说明卡 + 关于
// P2.6J: 「显示角色形象」开关: 关闭后头像保持模糊

struct SettingsView: View {
    @StateObject var store: SettingsStore
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appVisualMode) private var visualMode
    @ObservedObject private var privacy = AvatarPrivacy.shared
    @State private var appeared = false
    // P2.6E: 彩蛋入口 (本地 SwiftUI Sheet)
    @State private var showProSheet = false
    @State private var showHelpSheet = false
    @State private var showPrivacySheet = false
    @State private var showAboutSheet = false

    private var visual: Theme.VisualTokens { Theme.visual(visualMode) }


    var body: some View {
        ZStack {
            settingsBackdrop

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // 用户行 (P2.6I: 中性小猫文案, 头像复用隐私头像, 不再显示旧品牌与假天数)
                    HStack(spacing: 14) {
                        PrivacyAvatar(size: 58, tappable: false)
                            .overlay(Circle().stroke(Theme.v2Line, lineWidth: 1))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PERSONAL SPACE")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(1.6)
                                .foregroundStyle(Theme.v2Coral)
                            Text("小猫在呢")
                                .font(.system(size: 28, weight: .semibold, design: .serif))
                                .foregroundStyle(Theme.v2Ink)
                            Text("随时回来和小猫说说话")
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.v2Ink.opacity(0.58))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)

                    sectionTitle("角色与外观")
                        .padding(.top, 22)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.22), value: appeared)

                    appearanceGroup
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(.easeOut(duration: 0.45).delay(0.28), value: appeared)

                    sectionTitle("隐私与权限")
                        .padding(.top, 24)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.36).delay(0.34), value: appeared)

                    privacyGroup
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(.easeOut(duration: 0.42).delay(0.38), value: appeared)

                    sectionTitle("高级设置")
                        .padding(.top, 24)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.36).delay(0.44), value: appeared)

                    advancedGroup
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(.easeOut(duration: 0.42).delay(0.48), value: appeared)

                    // 关于
                    sectionTitle("关于")
                        .padding(.top, 24)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.36).delay(0.54), value: appeared)

                    aboutGroup
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(.easeOut(duration: 0.42).delay(0.58), value: appeared)
                }
            }
        }
        .accessibilityIdentifier("settings.screen")
        // P2.6E: 本地彩蛋卡 Sheet (Pro / 帮助 / 隐私政策 / 关于)
        .sheet(isPresented: $showProSheet) {
            EasterEggCard(
                icon: "sparkles",
                title: "小猫 Pro",
                bodyText: "私人彩蛋，仅供我们查看。",
                footer: "私人版本 · 仅供我们查看",
                onClose: {}
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showHelpSheet) {
            EasterEggCard(
                icon: "questionmark.circle.fill",
                title: "帮助与反馈",
                bodyText: "遇到问题，先抱抱小猫。实在不行，再想别的办法。",
                footer: "小猫的悄悄话",
                onClose: {}
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showPrivacySheet) {
            EasterEggCard(
                icon: "hand.raised.fill",
                title: "隐私政策",
                bodyText: "本 App 只服务两位用户。语音处理方式以当前服务配置为准。",
                footer: "私人版本 · 仅供我们查看",
                onClose: {}
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showAboutSheet) {
            EasterEggCard(
                icon: "heart.fill",
                title: "关于小猫",
                bodyText: "版本 1.0 (0) · 纪念日 8.1 \n有些日子，值得被记住。",
                footer: "只属于我们的版本",
                onClose: {}
            )
            .presentationDetents([.medium])
        }
        .onAppear {
            appeared = true
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 21, weight: .semibold, design: .serif))
            .foregroundStyle(Theme.v2Ink)
            .padding(.horizontal, 20)
    }

    private var settingsBackdrop: some View {
        ZStack {
            Theme.v2Paper
            LinearGradient(
                colors: [Theme.v2Lavender.opacity(0.18), .clear, Theme.v2CoralSoft.opacity(0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    // MARK: 使用统计卡 (P2.6I: 无真实数据时诚实空状态, 不显示 0 分钟/0 天/0%/假进度)
    private var statsCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 20))
                .foregroundStyle(Theme.primary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("使用记录尚未接入")
                    .font(Theme.subheadFont)
                    .foregroundStyle(Theme.textPrimary)
                Text("当前版本暂不展示时长、连续天数或累计统计。")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(visual.glassTint, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: visual.shadow.opacity(0.55), radius: 10, x: 0, y: 3)
    }

    // MARK: 订阅卡
    private var subCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundStyle(visualMode == .mystery ? visual.textPrimary : .white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(
                        colors: visualMode == .mystery
                            ? [visual.primarySoft, visual.primary.opacity(0.72)]
                            : [Theme.roleGold, Theme.primary],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("小猫 Pro · 彩蛋")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.textPrimary)
                Text("私人版本的本地彩蛋入口")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)

            // P2.6E: Pro 直接展示彩蛋 Sheet, 不再 close(), 无竞争手势
            Button {
                WarmHaptics.action()
                showProSheet = true
            } label: {
                Text("打开彩蛋")
                    .font(Theme.captionFont)
                    .foregroundStyle(visualMode == .mystery ? visual.textPrimary : .white)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(visualMode == .mystery ? visual.primarySoft : Theme.primary, in: Capsule())
                    .overlay {
                        if visualMode == .mystery {
                            Capsule().stroke(visual.border.opacity(0.9), lineWidth: 0.7)
                        }
                    }
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("settings.pro")
        }
        .padding(16)
        .background(visual.glassTint, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: visual.shadow.opacity(0.5), radius: 9, x: 0, y: 3)
    }

    // MARK: 角色与外观
    private var appearanceGroup: some View {
        privacyRow(icon: "eye.slash.fill", title: "显示角色形象",
                   detail: "关闭后头像和场景会保持模糊",
                   isOn: Binding(
                       get: { privacy.showRealAvatar },
                       set: { privacy.showRealAvatar = $0 }
                   ))
        .background(Theme.v2Paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.v2Line, lineWidth: 0.8))
    }

    // MARK: 隐私与权限
    private var privacyGroup: some View {
        VStack(spacing: 0) {
            Button(action: openSystemSettings) {
                settingsRow(
                    icon: microphonePermissionIcon,
                    title: "麦克风权限",
                    detail: microphonePermissionText,
                    trailing: microphonePermissionAction
                )
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier("settings.microphone")
            Divider().overlay(Theme.v2Line).padding(.leading, 60)
            settingsRow(
                icon: "waveform.and.mic",
                title: "实时语音服务",
                detail: "通话时语音会发送到服务端用于实时对话"
            )
        }
        .background(Theme.v2Paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.v2Line, lineWidth: 0.8))
    }

    // MARK: 高级设置
    private var advancedGroup: some View {
        Button {
            NotificationCenter.default.post(name: .reconfigureConnection, object: nil)
        } label: {
            settingsRow(
                icon: "network.badge.shield.half.filled",
                title: "服务连接",
                detail: "服务器地址、设备和鉴权配置",
                trailing: "配置"
            )
        }
        .buttonStyle(PressableCardStyle())
        .background(Theme.v2Paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.v2Line, lineWidth: 0.8))
        .accessibilityIdentifier("settings.reconfigure")
    }

    private func settingsRow(
        icon: String,
        title: String,
        detail: String,
        trailing: String? = nil
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.v2Coral)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.v2Ink)
                Text(detail)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.v2Ink.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(Theme.captionFont.weight(.semibold))
                    .foregroundStyle(Theme.v2Coral)
            }
            if trailing != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.v2Ink.opacity(0.38))
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private var microphonePermissionText: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "已开启，可用于实时陪伴"
        case .denied, .restricted: return "未开启，通话时无法听到你"
        case .notDetermined: return "首次通话时会请求权限"
        @unknown default: return "状态暂不可用"
        }
    }

    private var microphonePermissionIcon: String {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            ? "mic.fill"
            : "mic.slash"
    }

    private var microphonePermissionAction: String {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            ? "已开启"
            : "去设置"
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func privacyRow(icon: String, title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.v2Coral)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.v2Ink)
                Text(detail)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.v2Ink.opacity(0.58))
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.v2Coral)
                .accessibilityLabel(title)
                .accessibilityIdentifier("settings.privacy.\(title)")
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 60)
    }

    // MARK: 授权说明卡
    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 18))
                .foregroundStyle(Theme.info)
            Text("关闭「显示角色形象」后，头像会保持模糊。语音处理方式以当前服务配置为准。")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(visual.surfaceSoft.opacity(0.78), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    // MARK: 关于组
    private var aboutGroup: some View {
        VStack(spacing: 0) {
            Button {
                WarmHaptics.action()
                showProSheet = true
            } label: {
                HStack {
                    Label("小猫 Pro · 彩蛋", systemImage: "sparkles")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.v2Ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.v2Ink.opacity(0.38))
                }
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier("settings.pro")
            Divider().overlay(Theme.v2Line).padding(.leading, 20)
            aboutRow(title: "关于小猫", detail: "版本 1.0 (0)")
            Divider().overlay(Theme.v2Line).padding(.leading, 20)
            aboutRow(title: "帮助与反馈", detail: nil)
            Divider().overlay(Theme.v2Line).padding(.leading, 20)
            aboutRow(title: "隐私政策", detail: nil)
        }
        .background(Theme.v2Paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.v2Line, lineWidth: 0.8))
    }

    private func aboutRow(title: String, detail: String?) -> some View {
        Button {
            WarmHaptics.action()
            // P2.6E: 关于/帮助/隐私政策 -> 本地彩蛋卡
            switch title {
            case "关于小猫": showAboutSheet = true
            case "帮助与反馈": showHelpSheet = true
            case "隐私政策": showPrivacySheet = true
            default: break
            }
        } label: {
            HStack {
                Text(title)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.v2Ink)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.v2Ink.opacity(0.42))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.v2Ink.opacity(0.38))
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 56)
        }
        // P2.6J+: 可点击行按压反馈
        .buttonStyle(PressableCardStyle())
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityIdentifier("settings.about.\(title)")
    }
}

// MARK: - 预览
#Preview {
    SettingsView(store: SettingsStore(environment: .fromBundle()), close: {})
}
