import Foundation

public enum DVKSessionState: String, Codable, CaseIterable, Sendable {
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

public enum DVKJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: DVKJSONValue])
    case array([DVKJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: DVKJSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([DVKJSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct DVKInboundEvent: Codable, Identifiable, Equatable, Sendable {
    public let version: String
    public let eventID: String
    public let traceID: String
    public let sessionID: String
    public let sequence: Int
    public let timestamp: Int64
    public let type: String
    public let payload: [String: DVKJSONValue]

    public var id: String { eventID }

    public init(
        version: String,
        eventID: String,
        traceID: String,
        sessionID: String,
        sequence: Int,
        timestamp: Int64,
        type: String,
        payload: [String: DVKJSONValue] = [:]
    ) {
        self.version = version
        self.eventID = eventID
        self.traceID = traceID
        self.sessionID = sessionID
        self.sequence = sequence
        self.timestamp = timestamp
        self.type = type
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case version, sequence, timestamp, type, payload
        case eventID = "event_id"
        case traceID = "trace_id"
        case sessionID = "session_id"
    }
}

public struct DVKOutboundMessage: Codable, Identifiable, Equatable, Sendable {
    public let version: String
    public let eventID: String
    public let traceID: String
    public let sessionID: String
    public let sequence: Int
    public let timestamp: Int64
    public let type: String
    public let payload: [String: DVKJSONValue]

    public var id: String { eventID }

    public init(
        version: String,
        eventID: String,
        traceID: String,
        sessionID: String,
        sequence: Int,
        timestamp: Int64,
        type: String,
        payload: [String: DVKJSONValue] = [:]
    ) {
        self.version = version
        self.eventID = eventID
        self.traceID = traceID
        self.sessionID = sessionID
        self.sequence = sequence
        self.timestamp = timestamp
        self.type = type
        self.payload = payload
    }

    enum CodingKeys: String, CodingKey {
        case version, sequence, timestamp, type, payload
        case eventID = "event_id"
        case traceID = "trace_id"
        case sessionID = "session_id"
    }
}

public protocol DVKTransport: Sendable {
    func connect() async throws
    func send(_ message: DVKOutboundMessage) async throws
    func events() -> AsyncStream<DVKInboundEvent>
    func disconnect() async
}

public protocol DVKTransportFactory: Sendable {
    func makeTransport() -> any DVKTransport
}

public enum DVKCapturedAudioSampleFormat: Sendable, Equatable {
    case float32Planar
    case float32Interleaved
    case int16Planar
    case int16Interleaved
}

public struct DVKCapturedAudioPacket: Sendable, Equatable {
    public let data: Data
    public let sampleRate: Int
    public let channels: Int
    public let frameCount: Int
    public let format: DVKCapturedAudioSampleFormat
    public let captureGeneration: Int
    public let capturedAt: Date

    public init(
        data: Data,
        sampleRate: Int,
        channels: Int,
        frameCount: Int,
        format: DVKCapturedAudioSampleFormat,
        captureGeneration: Int,
        capturedAt: Date = Date()
    ) {
        self.data = data
        self.sampleRate = sampleRate
        self.channels = channels
        self.frameCount = frameCount
        self.format = format
        self.captureGeneration = captureGeneration
        self.capturedAt = capturedAt
    }

    public static func pcm16(
        _ data: Data,
        captureGeneration: Int,
        capturedAt: Date = Date()
    ) -> DVKCapturedAudioPacket {
        DVKCapturedAudioPacket(
            data: data,
            sampleRate: 16_000,
            channels: 1,
            frameCount: data.count / 2,
            format: .int16Interleaved,
            captureGeneration: captureGeneration,
            capturedAt: capturedAt
        )
    }
}

public protocol DVKAudioCaptureSink: Sendable {
    @discardableResult
    func offer(_ packet: DVKCapturedAudioPacket) -> Bool
}

public protocol DVKPlaybackAmplitudeSink: Sendable {
    func playbackAmplitudeDidChange(_ amplitude: Float)
}
