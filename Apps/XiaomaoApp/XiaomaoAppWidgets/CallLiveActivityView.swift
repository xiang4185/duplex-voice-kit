import ActivityKit
import SwiftUI
import WidgetKit
import XiaomaoShared

// MARK: - 挂断 / 静音入口
// Widget Extension 不能调用应用单例；使用 Link 通过 URL scheme 打开主 App。

// MARK: - 锁屏大卡 (LockScreenView)
struct LockScreenView: View {
    let context: ActivityViewContext<CallLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                avatarCircle(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("小猫 · 通话中")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Text(timeString)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.white)
            }

            MiniIslandWave(active: context.state.isSpeaking, mode: .primary, barCount: 9)
                .frame(height: 18)
                .opacity(context.state.isMuted ? 0.3 : 0.9)

            // P2.6K: 删除无真实来源的固定目标与进度; 底部仅保留真实计时与静音状态
            HStack {
                Text(context.state.isMuted ? "已静音 · 通话继续" : statusText)
                Spacer()
                Text("本次陪伴 \(context.state.sessionMinutes) 分钟")
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(16)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func avatarCircle(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.9, green: 0.42, blue: 0.51), Color(red: 0.76, green: 0.25, blue: 0.37)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("猫")
                .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private var timeString: String {
        let s = context.state.elapsedSeconds
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0
            ? String(format: "%02d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }

    private var statusText: String {
        if context.state.isMuted { return "已静音" }
        switch context.state.phase {
        case .calling: return "通话中"
        case .listening: return "正在听"
        case .thinking: return "正在想"
        case .speaking: return "正在说"
        case .reconnecting: return "正在重连"
        }
    }
}

// MARK: - 灵动岛动态小波形 (西柚玫瑰)
struct MiniIslandWave: View {
    let active: Bool
    var mode: Mode = .primary
    var barCount: Int = 5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false
    // P2.6K: 持有 Timer, 视图消失释放, 避免重复 Timer 泄漏
    @State private var waveTimer: Timer?

    enum Mode {
        case primary, gold

        var color: Color {
            switch self {
            case .primary: return Color(red: 0.85, green: 0.28, blue: 0.42)
            case .gold: return Color(red: 0.85, green: 0.28, blue: 0.42) // 西柚玫瑰 #D9486B (v6.1 定稿, 与 primary 同色)
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width / CGFloat(barCount) * 0.42
            let spacing = (geo.size.width - barWidth * CGFloat(barCount)) / CGFloat(barCount - 1)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(mode.color.opacity(active ? 0.9 : 0.35))
                        .frame(width: barWidth, height: barHeight(i, geo: geo))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: phase)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        // P2.6K-FIX-1: Timer 随状态启停 (active / reduceMotion 变化即重建)
        .onAppear {
            updateWaveTimer(isActive: active)
        }
        .onChange(of: active) { isActive in
            updateWaveTimer(isActive: isActive)
        }
        .onChange(of: reduceMotion) { _ in
            updateWaveTimer(isActive: active)
        }
        .onDisappear {
            waveTimer?.invalidate()
            waveTimer = nil
        }
    }

    // P2.6K-FIX-1: 统一 Timer 生命周期 — 先清理旧 Timer, 非活跃/Reduce Motion 立即停止
    private func updateWaveTimer(isActive: Bool) {
        waveTimer?.invalidate()
        waveTimer = nil

        guard isActive, !reduceMotion else {
            phase = false
            return
        }

        withAnimation(.easeOut(duration: 0.12)) {
            phase = true
        }

        waveTimer = Timer.scheduledTimer(
            withTimeInterval: 0.14,
            repeats: true
        ) { _ in
            withAnimation(.easeOut(duration: 0.12)) {
                phase.toggle()
            }
        }
    }

    private func barHeight(_ i: Int, geo: GeometryProxy) -> CGFloat {
        guard active else { return geo.size.height * 0.3 }
        let maxH = geo.size.height
        let base: CGFloat = [0.55, 0.95, 0.4, 1.0, 0.7, 0.85, 0.5, 0.9, 0.62, 0.78][i % 10]
        let pulse = phase ? 1.0 : 0.65
        return maxH * base * pulse
    }
}
