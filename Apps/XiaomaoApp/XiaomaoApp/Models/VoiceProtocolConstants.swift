import Foundation

enum VoiceResponseTaskState: String, Codable, CaseIterable, Sendable {
    case created
    case streaming
    case completed
    case interrupted
    case failed
    case cancelled
}

enum VoiceProtocolErrorCode: String, Codable, CaseIterable, Sendable {
    case unsupportedProtocolVersion = "unsupported_protocol_version"
    case unknownEvent = "unknown_event"
    case messageTooLarge = "message_too_large"
    case audioTooLarge = "audio_too_large"
    case invalidAudio = "invalid_audio"
    case unsupportedAudioFormat = "unsupported_audio_format"
    case unsupportedSampleRate = "unsupported_sample_rate"
    case unsupportedChannels = "unsupported_channels"
    case duplicateEvent = "duplicate_event"
    case sequenceOutOfOrder = "sequence_out_of_order"
    case sessionNotFound = "session_not_found"
    case sessionClosed = "session_closed"
    case responseNotActive = "response_not_active"
    case invalidStateTransition = "invalid_state_transition"
    case unauthorized = "unauthorized"
    case sendQueueOverflow = "send_queue_overflow"
}

enum VoiceAudioContract {
    static let format = "pcm_s16le"
    static let sampleRate = 16_000
    static let channels = 1
    static let maxChunkBytes = 32_000
    static let preferredChunkBytes = 640
    static let maxEventBytes = 65_536
}
