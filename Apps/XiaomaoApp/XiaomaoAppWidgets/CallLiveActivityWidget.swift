import ActivityKit
import Foundation
import SwiftUI
import WidgetKit
import XiaomaoShared

// MARK: - Live Activity Widget (CallLiveActivityWidget)
// v6.1 屏8: ActivityKit + WidgetKit, 时间轴更新 ≤ 1s
// 注意: iOS 17.0 需用 DynamicIsland 无参构造 + 各 region 分支 (不用 context.state 分类)

struct CallLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CallLiveActivityAttributes.self) { context in
            // 锁屏 / 横幅
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // 扩展态
                DynamicIslandExpandedRegion(.leading) {
                    avatarDot(size: 40)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text("\(context.attributes.characterName) 正在陪你")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                        MiniIslandWave(active: context.state.isSpeaking, mode: .primary, barCount: 7)
                            .frame(width: 80, height: 14)
                            .opacity(context.state.isMuted ? 0.3 : 0.9)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timeString(context))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 16) {
                        Link(destination: URL(string: "xiaomao://call/mute")!) {
                            Image(systemName: context.state.isMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 16))
                                .frame(width: 32, height: 32)
                                .background(.white.opacity(0.15), in: Circle())
                        }
                        Link(destination: URL(string: "xiaomao://call/hangup")!) {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.red.opacity(0.85), in: Circle())
                        }
                    }
                }
            } compactLeading: {
                avatarDot(size: 20)
            } compactTrailing: {
                HStack(spacing: 6) {
                    MiniIslandWave(active: context.state.isSpeaking, mode: .gold, barCount: 5)
                        .frame(width: 34, height: 12)
                    Text(timeString(context))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
            } minimal: {
                MiniIslandWave(active: context.state.isSpeaking, mode: .gold, barCount: 5)
                    .frame(width: 30, height: 12)
            }
        }
    }

    private func avatarDot(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.85, green: 0.28, blue: 0.42)) // 西柚玫瑰
                .frame(width: size, height: size)
            Circle()
                .fill(.white.opacity(0.9))
                .frame(width: size * 0.5, height: size * 0.5)
            Text("暖")
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.85, green: 0.28, blue: 0.42))
        }
    }

    private func timeString(_ context: ActivityViewContext<CallLiveActivityAttributes>) -> String {
        let s = context.state.elapsedSeconds
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0
            ? String(format: "%02d:%02d:%02d", h, m, sec)
            : String(format: "%02d:%02d", m, sec)
    }
}

// MARK: - Widget Bundle
@main
struct XiaomaoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CallLiveActivityWidget()
    }
}
