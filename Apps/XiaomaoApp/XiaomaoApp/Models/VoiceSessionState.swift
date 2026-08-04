import Foundation

enum VoiceSessionState: String, Codable, CaseIterable, Sendable {
    case idle
    case connecting
    case ready
    case listening
    case endpointing
    case processing
    case speaking
    case interrupting
    case reconnecting
    case degraded
    case closing
    case closed
    case failed
}
