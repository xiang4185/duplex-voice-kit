import DuplexVoiceKit
import Foundation

/// Bridges DVK's serial outbound messages to the App-owned WebSocket connection.
/// This adapter never connects, receives, disconnects, stores credentials, or creates a second sender.
struct XiaomaoDVKOutboundTransport: DVKOutboundTransport {
    private let socket: any VoiceWebSocketClient

    init(socket: any VoiceWebSocketClient) {
        self.socket = socket
    }

    func send(_ message: DVKOutboundMessage) async throws {
        guard let type = VoiceEventType(rawValue: message.type) else {
            throw AppError.protocolError("unsupported_dvk_outbound_type")
        }
        try await socket.send(VoiceEvent(
            version: message.version,
            eventID: message.eventID,
            traceID: message.traceID,
            sessionID: message.sessionID,
            sequence: message.sequence,
            timestamp: message.timestamp,
            type: type,
            payload: message.payload.mapValues(JSONValue.init(dvkValue:))
        ))
    }
}

private extension JSONValue {
    init(dvkValue: DVKJSONValue) {
        switch dvkValue {
        case .string(let value): self = .string(value)
        case .int(let value): self = .int(value)
        case .double(let value): self = .double(value)
        case .bool(let value): self = .bool(value)
        case .object(let value):
            self = .object(value.mapValues(JSONValue.init(dvkValue:)))
        case .array(let value):
            self = .array(value.map(JSONValue.init(dvkValue:)))
        case .null: self = .null
        }
    }
}

extension DVKJSONValue {
    init(appValue: JSONValue) {
        switch appValue {
        case .string(let value): self = .string(value)
        case .int(let value): self = .int(value)
        case .double(let value): self = .double(value)
        case .bool(let value): self = .bool(value)
        case .object(let value):
            self = .object(value.mapValues(DVKJSONValue.init(appValue:)))
        case .array(let value):
            self = .array(value.map(DVKJSONValue.init(appValue:)))
        case .null: self = .null
        }
    }
}
