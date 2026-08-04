import SwiftUI

extension VoiceSessionState {
    var chineseDescription: String {
        switch self {
        case .idle: return "等待开始"
        case .connecting: return "正在连接"
        case .ready: return "已连接，可以直接说话"
        case .listening: return "检测到说话"
        case .endpointing, .processing: return "正在处理"
        case .speaking: return "正在回复"
        case .interrupting: return "已自动打断"
        case .reconnecting: return "正在重连"
        case .degraded: return "服务降级"
        case .closing: return "正在关闭"
        case .closed: return "连接已关闭"
        case .failed: return "连接失败"
        }
    }
}

struct VoiceStateIndicator: View {
    let state: VoiceSessionState
    let vadState: VoiceActivityState

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 72, height: 72)
                .overlay(Image(systemName: indicatorIcon).foregroundStyle(.white))
            Text(displayText).font(.headline)
        }
        .accessibilityLabel("语音状态：\(displayText)")
    }

    private var displayText: String {
        if state == .ready, vadState == .speechDetected {
            return "检测到说话"
        }
        return state.chineseDescription
    }

    private var indicatorColor: Color {
        switch state {
        case .ready, .listening, .speaking: return .green
        case .failed, .closed: return .red
        case .reconnecting, .connecting: return .orange
        default: return .blue
        }
    }

    private var indicatorIcon: String {
        switch state {
        case .speaking: return "waveform"
        case .reconnecting, .connecting: return "arrow.triangle.2.circlepath"
        case .failed, .closed: return "exclamationmark.triangle.fill"
        default: return "mic.fill"
        }
    }
}
