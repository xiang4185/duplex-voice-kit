import SwiftUI

// MARK: - 屏 2 角色页 (P2.8A: 1.0 收口)
// v6.1: 角色选择
// P2.6D: 多角色预览彩蛋 (已移除 — 1.0 只展示生产角色"小猫")
// P2.8A: 页面只展示 CompanionPreviewRole.xiaomao, 不遍历 allCases;
// 删除占位角色卡/吃醋彩蛋/旧预览与围观入口; 通用多角色能力留给 1.1/DVK.

struct CharacterSelectView: View {
    var startCall: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var privacy = AvatarPrivacy.shared
    @ObservedObject private var roleStore = CompanionRoleStore.shared
    @State private var appeared = false
    @State private var showPrivacyConfirm = false

    // P2.8A: 1.0 只展示生产角色"小猫"
    private let productionRole = CompanionPreviewRole.xiaomao

    var body: some View {
        ZStack {
            Theme.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("当前陪伴角色")
                            .font(Theme.title1Font)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.top, 20)
                            .padding(.horizontal, 20)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)
                            .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)

                        Text("目前仅小猫支持实时语音，更多角色正在准备中。")
                            .font(Theme.subheadFont)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 6)
                            .padding(.horizontal, 20)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)
                            .animation(.easeOut(duration: 0.4).delay(0.18), value: appeared)

                        // P2.8A: 单张正式角色卡 (大尺寸人物, 非 96pt 小头像)
                        productionCard
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 14)
                            .animation(.easeOut(duration: 0.45).delay(0.28), value: appeared)

                        // P2.8A: 底部开始聊天 (始终可点, 隐私只控制人物显示不控制语音资格)
                        startBar
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 24)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 14)
                            .animation(.easeOut(duration: 0.4).delay(0.5), value: appeared)
                    }
                }
            }
        }
        .accessibilityIdentifier("characters.screen")
        .sheet(isPresented: $showPrivacyConfirm) {
            AvatarPrivacyConfirmView(
                onAgree: { privacy.unlock() },
                onDecline: { privacy.keepLocked() }
            )
            .presentationDetents([.medium])
        }
        .onAppear {
            appeared = true
            // P2.8A: 进入角色页确保预览角色回到小猫 (占位角色状态不残留)
            if roleStore.previewRole != .xiaomao {
                withAnimation(.easeOut(duration: 0.3)) {
                    roleStore.previewRole = .xiaomao
                }
            }
        }
    }

    // MARK: 单张正式角色卡 (P2.8A)
    private var productionCard: some View {
        let role = productionRole

        return VStack(spacing: 12) {
            // 当前角色 Badge
            Text("当前角色")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.primary700)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Theme.primary100, in: Capsule())
                .padding(.top, 14)

            // 大尺寸人物 (portrait 完整形象; 点击: 未解锁→隐私确认, 已解锁→无操作)
            ZStack {
                // 角色渐变背景 (上半, 保持原有角色视觉语言)
                role.gradient
                    .opacity(0.16)
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.characterCard, style: .continuous))

                // 角色卡 halo 光晕
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [role.themeColor.opacity(0.28), Theme.primarySoft.opacity(0.12), .clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: 110
                        )
                    )
                    .frame(width: 240, height: 240)

                PrivacyAvatar(
                    size: 190,
                    tappable: true,
                    variant: role.avatarVariant
                ) {
                    // 未解锁 → 隐私确认; 已解锁后正常显示 (仅人物显示控制)
                    if !privacy.effectiveReveal() {
                        showPrivacyConfirm = true
                    }
                }
            }
            .padding(.top, 4)

            Text(role.displayName)
                .font(Theme.title2Font)
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 6) {
                ForEach(role.chips, id: \.self) { chip in
                    Text(chip)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.primary700)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.primary100, in: Capsule())
                }
            }

            Text(role.tagline)
                .font(Theme.subheadFont)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 2)

            // 支持实时通话
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                    .font(.system(size: 11))
                Text("支持实时通话")
                    .font(Theme.captionFont)
            }
            .foregroundStyle(Theme.primary700)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Theme.primary100.opacity(0.7), in: Capsule())
            .padding(.bottom, 16)
        }
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.characterCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.characterCard, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        )
        .cardTopHighlight()
        .shadow(color: Theme.shadowFloating, radius: 20, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("小猫，元气、话痨，支持实时通话")
    }

    // MARK: 底部开始聊天 (P2.8A: 单击 startCall, 隐私模糊不阻止语音)
    private var startBar: some View {
        HStack(spacing: 14) {
            PrivacyAvatar(
                size: 52,
                tappable: false,
                variant: roleStore.previewRole.avatarVariant
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(roleStore.previewRole.displayName)
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    ForEach(roleStore.previewRole.chips, id: \.self) { chip in
                        Text(chip)
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.primary700)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.primary100, in: Capsule())
                    }
                }
            }
            Spacer(minLength: 0)

            Button(action: {
                WarmHaptics.action()
                startCall()
            }) {
                Text("开始聊天")
                    .font(Theme.headlineFont)
                    .foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                    .background(Theme.primary, in: Capsule())
                    .shadow(color: Theme.ctaShadow, radius: 10, x: 0, y: 5)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("characters.start")
        }
        .padding(14)
        .glassEffect(
            .regular
                .tint(Theme.primarySoft.opacity(0.18)),
            in: .rect(cornerRadius: Theme.Radius.card)
        )
        .shadow(color: Theme.shadowRaised, radius: 12, x: 0, y: 4)
    }
}

// MARK: - 预览
#Preview {
    CharacterSelectView(startCall: {})
}
