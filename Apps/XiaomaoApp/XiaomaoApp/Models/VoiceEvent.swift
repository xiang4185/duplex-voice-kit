import Foundation

struct VoiceEvent: Codable, Identifiable, Sendable {
    static let protocolVersion = "0.2"
    let version: String
    let eventID: String
    let traceID: String
    let sessionID: String
    let sequence: Int
    let timestamp: Int64
    let type: VoiceEventType
    let payload: [String: JSONValue]
    var id: String { eventID }

    enum CodingKeys: String, CodingKey {
        case version, sequence, timestamp, type, payload
        case eventID = "event_id"
        case traceID = "trace_id"
        case sessionID = "session_id"
    }
}

enum VoiceEventType: String, Codable, CaseIterable, Sendable {
    case sessionStart = "session.start"
    case sessionResume = "session.resume"
    case sessionEnd = "session.end"
    case audioAppend = "audio.append"
    case audioCommit = "audio.commit"
    case responseNext = "response.next"
    case responseCancel = "response.cancel"
    case interrupt = "interrupt"
    case mute = "mute"
    case unmute = "unmute"
    case routeChange = "route.change"
    case ping = "ping"
    case clientState = "client.state"
    case sessionReady = "session.ready"
    case sessionResumed = "session.resumed"
    case sessionClosed = "session.closed"
    case sessionEnded = "session.ended"
    case serverIdleWarning = "server.idle_warning"
    case listeningStarted = "listening.started"
    case listeningStopped = "listening.stopped"
    case transcriptPartial = "transcript.partial"
    case transcriptFinal = "transcript.final"
    case thinkingStarted = "thinking.started"
    case responseStarted = "response.started"
    case responseAudioDelta = "response.audio.delta"
    case responseAudioDone = "response.audio.done"
    case responseTextDelta = "response.text.delta"
    case responseTextDone = "response.text.done"
    case responseCancelled = "response.cancelled"
    case interrupted = "interrupted"
    case contextUpdated = "context.updated"
    case routeChanged = "route.changed"
    case degraded = "degraded"
    case error = "error"
    case pong = "pong"
    case serverState = "server.state"
}
