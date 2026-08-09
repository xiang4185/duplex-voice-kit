import SwiftUI

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
            visual.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // 用户行 (P2.6I: 中性小猫文案, 头像复用隐私头像, 不再显示旧品牌与假天数)
                    HStack(spacing: 14) {
                        PrivacyAvatar(size: 56, tappable: false)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("小猫在呢")
                                .font(Theme.title3Font)
                                .foregroundStyle(Theme.textPrimary)
                            Text("随时回来和小猫说说话")
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)

                    // 使用统计卡 (数字滚动)
                    statsCard
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(.easeOut(duration: 0.45).delay(0.22), value: appeared)

                    // 订阅卡
                    subCard
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(.easeOut(duration: 0.45).delay(0.3), value: appeared)

                    // 隐私与授权
                    Text("隐私与授权")
                        .font(Theme.title3Font)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.36), value: appeared)

                    privacyGroup
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(.easeOut(duration: 0.45).delay(0.42), value: appeared)

                    Button {
                        NotificationCenter.default.post(name: .reconfigureConnection, object: nil)
                    } label: {
                        Label("重新配置连接", systemImage: "network.badge.shield.half.filled")
                            .font(Theme.bodyFont)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.primary)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .accessibilityIdentifier("settings.reconfigure")

                    // 授权说明卡
                    privacyNote
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(.easeOut(duration: 0.45).delay(0.48), value: appeared)

                    // 关于
                    Text("关于")
                        .font(Theme.title3Font)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.54), value: appeared)

                    aboutGroup
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 14)
                        .animation(.easeOut(duration: 0.45).delay(0.6), value: appeared)
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .background(visual.glassTint, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: visual.shadow.opacity(0.55), radius: 10, x: 0, y: 3)
    }

    // MARK: 订阅卡
    private var subCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(colors: [Theme.roleGold, Theme.primary],
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
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Theme.primary, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("settings.pro")
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .background(visual.glassTint, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: visual.shadow.opacity(0.5), radius: 9, x: 0, y: 3)
    }

    // MARK: 隐私组 (P2.6J: 仅保留真实生效的开关与静态说明, 删除本地无效开关)
    private var privacyGroup: some View {
        VStack(spacing: 0) {
            privacyRow(icon: "eye.slash.fill", title: "显示角色形象",
                       detail: "关闭后头像会保持模糊",
                       isOn: Binding(
                           get: { privacy.showRealAvatar },
                           set: { privacy.showRealAvatar = $0 }
                       ))
            Divider().overlay(Theme.border).padding(.leading, 60)
            // 静态说明行: 不提供无法改变真实行为的 Toggle
            HStack(spacing: 14) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.info)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("实时语音服务")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textPrimary)
                    Text("通话时语音会发送到服务端用于实时对话")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 60)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .background(visual.glassTint, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: visual.shadow.opacity(0.5), radius: 9, x: 0, y: 3)
    }

    private func privacyRow(icon: String, title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.info)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.primary)
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
            aboutRow(title: "关于小猫", detail: "版本 1.0 (0)")
            Divider().overlay(Theme.border).padding(.leading, 20)
            aboutRow(title: "帮助与反馈", detail: nil)
            Divider().overlay(Theme.border).padding(.leading, 20)
            aboutRow(title: "隐私政策", detail: nil)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .background(visual.glassTint, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: visual.shadow.opacity(0.5), radius: 9, x: 0, y: 3)
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
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
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
