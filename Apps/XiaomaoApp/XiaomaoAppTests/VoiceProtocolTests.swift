import XCTest
@testable import XiaomaoApp

final class VoiceProtocolTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let event = VoiceEvent(
            version: VoiceEvent.protocolVersion,
            eventID: "event",
            traceID: "trace",
            sessionID: "session",
            sequence: 1,
            timestamp: 1,
            type: .sessionStart,
            payload: ["route": .string("a")]
        )
        let decoded = try JSONDecoder().decode(VoiceEvent.self, from: JSONEncoder().encode(event))
        XCTAssertEqual(decoded.eventID, event.eventID)
        XCTAssertEqual(decoded.type, .sessionStart)
    }

    func testWebSocketEnvelopeUsesUTF8TextFrame() throws {
        let event = VoiceEvent(
            version: VoiceEvent.protocolVersion,
            eventID: "event",
            traceID: "trace",
            sessionID: "session",
            sequence: 1,
            timestamp: 1,
            type: .sessionStart,
            payload: ["route": .string("b")]
        )
        switch try VoiceWebSocketEnvelope.message(for: event) {
        case .string(let value):
            XCTAssertTrue(value.contains("session.start"))
        case .data:
            XCTFail("voice protocol JSON must use a text WebSocket frame")
        @unknown default:
            XCTFail("unexpected WebSocket message type")
        }
    }

    func testWebSocketResourceTimeoutSupportsPersistentCalls() {
        let configuration = VoiceWebSocketConfiguration.makeURLSessionConfiguration()
        let resourceTimeout = configuration.timeoutIntervalForResource
        let requestTimeout = configuration.timeoutIntervalForRequest
        let expectedRequestTimeout = VoiceWebSocketConfiguration.handshakeTimeoutSeconds

        XCTAssertGreaterThanOrEqual(resourceTimeout, 3_600)
        XCTAssertEqual(requestTimeout, expectedRequestTimeout)
        XCTAssertGreaterThan(resourceTimeout, 30)
    }

    func testAudioChunkLimit() {
        XCTAssertEqual(VoiceProtocolCodec.maximumChunkBytes, 32_000)
    }
}
