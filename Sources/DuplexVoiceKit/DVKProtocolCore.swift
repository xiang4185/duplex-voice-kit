import Foundation

enum DVKProtocolEventType: String, Sendable {
    case sessionStart = "session.start"
    case sessionResume = "session.resume"
    case sessionEnd = "session.end"
    case audioAppend = "audio.append"
    case audioCommit = "audio.commit"
    case interrupt = "interrupt"
    case mute = "mute"
    case unmute = "unmute"
    case ping = "ping"
    case clientState = "client.state"
}

struct DVKProtocolCodec: Sendable {
    static let protocolVersion = "0.2"
    static let sampleRate = 16_000
    static let channels = 1
    static let format = "pcm_s16le"
    static let maximumChunkBytes = 32_000

    private(set) var clientSequence = 0

    mutating func makeMessage(
        type: DVKProtocolEventType,
        sessionID: String,
        traceID: String,
        payload: [String: DVKJSONValue] = [:]
    ) -> DVKOutboundMessage {
        clientSequence += 1
        return DVKOutboundMessage(
            version: Self.protocolVersion,
            eventID: UUID().uuidString,
            traceID: traceID,
            sessionID: sessionID,
            sequence: clientSequence,
            timestamp: Int64(Date().timeIntervalSince1970 * 1_000),
            type: type.rawValue,
            payload: payload
        )
    }
}

/// Filters server-push audio and completion events by response identity and server sequence.
public struct DVKResponseFilter: Sendable, Equatable {
    public private(set) var responseID: String
    public private(set) var lastServerSequence: Int

    public init(responseID: String = "", lastServerSequence: Int = 0) {
        self.responseID = responseID
        self.lastServerSequence = max(0, lastServerSequence)
    }

    public mutating func begin(responseID: String, serverSequence: Int) {
        self.responseID = responseID
        lastServerSequence = max(lastServerSequence, serverSequence)
    }

    public mutating func acceptAudio(responseID: String, serverSequence: Int) -> Bool {
        guard serverSequence > lastServerSequence else { return false }
        lastServerSequence = serverSequence
        return !self.responseID.isEmpty && self.responseID == responseID
    }

    public mutating func finish(responseID: String, serverSequence: Int) -> Bool {
        guard serverSequence > lastServerSequence else { return false }
        lastServerSequence = serverSequence
        guard self.responseID == responseID else { return false }
        self.responseID = ""
        return true
    }

    public mutating func clear() {
        responseID = ""
    }
}

/// Defines bounded exponential reconnect delays for host-managed connection lifecycles.
public struct DVKReconnectPolicy: Sendable, Equatable {
    public let maximumAttempts: Int
    public let baseDelay: Duration
    public let maximumDelay: Duration

    public static let realtimeDefault = DVKReconnectPolicy(
        maximumAttempts: 5,
        baseDelay: .milliseconds(400),
        maximumDelay: .milliseconds(6_400)
    )

    public init(
        maximumAttempts: Int,
        baseDelay: Duration,
        maximumDelay: Duration
    ) {
        self.maximumAttempts = max(0, maximumAttempts)
        self.baseDelay = baseDelay
        self.maximumDelay = maximumDelay
    }

    public func delay(for attempt: Int) -> Duration {
        let normalizedAttempt = max(1, attempt)
        let exponent = min(max(0, normalizedAttempt - 1), 4)
        let factor = 1 << exponent
        let baseMilliseconds = Self.milliseconds(baseDelay)
        let maximumMilliseconds = Self.milliseconds(maximumDelay)
        return .milliseconds(min(maximumMilliseconds, baseMilliseconds * Int64(factor)))
    }

    private static func milliseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        let seconds = components.seconds * 1_000
        let attoseconds = components.attoseconds / 1_000_000_000_000_000
        return max(0, seconds + attoseconds)
    }
}

actor DVKReconnectController {
    private(set) var attempt = 0
    let policy: DVKReconnectPolicy

    init(policy: DVKReconnectPolicy = .realtimeDefault) {
        self.policy = policy
    }

    func reset() {
        attempt = 0
    }

    func nextDelay() -> Duration? {
        guard attempt < policy.maximumAttempts else { return nil }
        attempt += 1
        return policy.delay(for: attempt)
    }
}
