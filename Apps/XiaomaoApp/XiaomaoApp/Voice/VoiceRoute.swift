import Foundation

enum VoiceRoute: String, CaseIterable, Codable, Hashable, Sendable {
    case a, b, c

    var title: String {
        switch self {
        case .a: return "ASR + 小猫 + TTS"
        case .b: return "端到端语音"
        case .c: return "混合路线"
        }
    }
}
