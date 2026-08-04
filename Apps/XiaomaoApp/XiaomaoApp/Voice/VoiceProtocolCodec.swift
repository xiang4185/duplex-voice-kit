import Foundation

struct VoiceProtocolCodec: Sendable {
    static let sampleRate = 16_000
    static let channels = 1
    static let format = "pcm_s16le"
    static let maximumChunkBytes = 32_000

    private(set) var clientSequence = 0

    mutating func makeEvent(
        type: VoiceEventType,
        sessionID: String,
        traceID: String,
        payload: [String: JSONValue] = [:]
    ) -> VoiceEvent {
        clientSequence += 1
        return VoiceEvent(
            version: VoiceEvent.protocolVersion,
            eventID: UUID().uuidString,
            traceID: traceID,
            sessionID: sessionID,
            sequence: clientSequence,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            type: type,
            payload: payload
        )
    }
}
