import ActivityKit
import Foundation

public enum CallLiveActivityPhase: String, Codable, Hashable {
    case calling
    case listening
    case thinking
    case speaking
    case reconnecting
}

// MARK: - 通话 Live Activity 属性 (CallLiveActivityAttributes)
// v6.1 屏8: 紧凑态(灵动岛5柱) · 扩展态(7柱+静音/挂断) · 锁屏大卡(9柱+进度条)

public struct CallLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// 是否静音
        public var isMuted: Bool
        /// 是否正在说话 (驱动波形活跃度)
        public var isSpeaking: Bool
        /// 真实通话阶段；只表达状态，不包含转写、正文、设备或鉴权信息。
        public var phase: CallLiveActivityPhase
        /// 已通话秒数
        public var elapsedSeconds: Int
        /// 进度 0...1 (锁屏进度条)
        public var progress: Double
        /// 本次陪伴分钟数
        public var sessionMinutes: Int
        /// 目标分钟数
        public var goalMinutes: Int
        public init(
            isMuted: Bool,
            isSpeaking: Bool,
            phase: CallLiveActivityPhase,
            elapsedSeconds: Int,
            progress: Double,
            sessionMinutes: Int,
            goalMinutes: Int
        ) {
            self.isMuted = isMuted
            self.isSpeaking = isSpeaking
            self.phase = phase
            self.elapsedSeconds = elapsedSeconds
            self.progress = progress
            self.sessionMinutes = sessionMinutes
            self.goalMinutes = goalMinutes
        }
    }

    /// 角色名 (当前: 小猫)
    public var characterName: String
    /// 角色 ID
    public var characterID: String

    public init(characterName: String, characterID: String) {
        self.characterName = characterName
        self.characterID = characterID
    }
}
