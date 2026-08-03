import XCTest
@testable import DuplexVoiceKitUI
import DuplexVoiceKit

final class DVKVoiceTransportTests: XCTestCase {

    private func wssURL() -> URL {
        URL(string: "wss" + "://" + "voice.example.test/v1/voice/ws")!
    }

    private func credentials() -> DVKVoiceCredentials {
        DVKVoiceCredentials(url: wssURL(), token: "synthetic-token", deviceID: "dvk-demo-device")
    }

    private func message(type: String, sessionID: String = "session-1") -> DVKOutboundMessage {
        DVKOutboundMessage(
            version: "0.2",
            eventID: UUID().uuidString,
            traceID: "trace-1",
            sessionID: sessionID,
            sequence: 1,
            timestamp: Int64(Date().timeIntervalSince1970 * 1_000),
            type: type,
            payload: [:]
        )
    }

    private func drainEvents(_ stream: AsyncStream<DVKInboundEvent>, count: Int) async -> [DVKInboundEvent] {
        var iterator = stream.makeAsyncIterator()
        var collected: [DVKInboundEvent] = []
        while collected.count < count, let event = await iterator.next() {
            collected.append(event)
        }
        return collected
    }

    // 14.4: the transport handshake carries Bearer, X-Device-ID and protocol 0.2
    // (Darwin-only: the live WebSocket transport exists only on Apple platforms)
    #if canImport(Darwin)
    func testHandshakeRequestHeaders() {
        let request = DVKVoiceWebSocketTransport.makeHandshakeRequest(credentials: credentials())
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Device-ID"), "dvk-demo-device")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Protocol-Version"), "0.2")
    }
    #endif

    // 14.4: the protocol version constant mirrors the frozen 0.2 contract
    #if canImport(Darwin)
    func testProtocolVersionIsZeroTwo() {
        XCTAssertEqual(DVKVoiceWebSocketTransport.protocolVersion, "0.2")
    }
    #endif

    // 14.4: mock transport turns session.start into session.ready
    func testMockTransportSessionStartProducesReady() async throws {
        let transport = DVKVoiceMockTransport()
        let events = transport.events()
        try await transport.connect()
        try await transport.send(message(type: "session.start"))
        let received = await drainEvents(events, count: 1)
        XCTAssertEqual(received.first?.type, "session.ready")
        XCTAssertEqual(received.first?.sessionID, "session-1")
    }

    // 14.4: mock transport turns session.resume into session.resumed
    func testMockTransportSessionResumeProducesResumed() async throws {
        let transport = DVKVoiceMockTransport()
        let events = transport.events()
        try await transport.connect()
        try await transport.send(message(type: "session.resume"))
        let received = await drainEvents(events, count: 1)
        XCTAssertEqual(received.first?.type, "session.resumed")
    }

    // 14.4: mock transport answers ping with pong
    func testMockTransportPingProducesPong() async throws {
        let transport = DVKVoiceMockTransport()
        let events = transport.events()
        try await transport.connect()
        try await transport.send(message(type: "ping"))
        let received = await drainEvents(events, count: 1)
        XCTAssertEqual(received.first?.type, "pong")
    }

    // 14.4: mock transport confirms interrupts
    func testMockTransportInterruptProducesInterrupted() async throws {
        let transport = DVKVoiceMockTransport()
        let events = transport.events()
        try await transport.connect()
        try await transport.send(message(type: "interrupt"))
        let received = await drainEvents(events, count: 1)
        XCTAssertEqual(received.first?.type, "interrupted")
    }

    // 14.4: mock transport closes on session.end
    func testMockTransportEndProducesClosed() async throws {
        let transport = DVKVoiceMockTransport()
        let events = transport.events()
        try await transport.connect()
        try await transport.send(message(type: "session.end"))
        let received = await drainEvents(events, count: 1)
        XCTAssertEqual(received.first?.type, "session.closed")
    }

    // 14.4: unauthorized handshake is not recoverable
    func testClassifierUnauthorizedIsNotRecoverable() {
        let info = DVKVoiceTransportErrorClassifier.classify(error: nil, closeCode: nil, httpStatus: 401)
        XCTAssertEqual(info.errorCategory, "unauthorized")
        XCTAssertFalse(info.recoverable)
    }

    // 14.4: abnormal close is recoverable
    func testClassifierAbnormalCloseIsRecoverable() {
        let info = DVKVoiceTransportErrorClassifier.classify(error: nil, closeCode: 1006)
        XCTAssertEqual(info.errorCategory, "connection_lost")
        XCTAssertTrue(info.recoverable)
    }

    // 14.4: normal server close is not recoverable
    func testClassifierNormalCloseIsNotRecoverable() {
        let info = DVKVoiceTransportErrorClassifier.classify(error: nil, closeCode: 1000)
        XCTAssertEqual(info.errorCategory, "server_closed")
        XCTAssertFalse(info.recoverable)
    }

    // 14.4: timeouts are recoverable
    func testClassifierTimeoutIsRecoverable() {
        let info = DVKVoiceTransportErrorClassifier.classify(error: URLError(.timedOut), closeCode: nil)
        XCTAssertEqual(info.errorCategory, "timed_out")
        XCTAssertTrue(info.recoverable)
    }

    // 14.4: decode failures are protocol errors
    func testClassifierDecodingErrorIsProtocolError() {
        let decoding = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad"))
        let info = DVKVoiceTransportErrorClassifier.classify(error: decoding, closeCode: nil)
        XCTAssertEqual(info.errorCategory, "protocol_error")
        XCTAssertFalse(info.recoverable)
    }

    // 14.4: intentional closes are classified as cancelled
    func testClassifierIntentionalCloseIsCancelled() {
        let info = DVKVoiceTransportErrorClassifier.classify(error: URLError(.cancelled), closeCode: 1000, intentional: true)
        XCTAssertEqual(info.errorCategory, "cancelled")
        XCTAssertFalse(info.recoverable)
    }

    // 14.4: the factory creates mock and live transports per platform
    func testTransportFactoryCreatesBothPaths() {
        let mock = DVKVoiceTransportFactory(credentials: credentials(), useMock: true)
        XCTAssertTrue(mock.makeCompanionTransport() is DVKVoiceMockTransport)
        let live = DVKVoiceTransportFactory(credentials: credentials(), useMock: false)
        #if canImport(Darwin)
        XCTAssertTrue(live.makeCompanionTransport() is DVKVoiceWebSocketTransport)
        #else
        XCTAssertTrue(live.makeCompanionTransport() is DVKVoiceMockTransport)
        #endif
    }
}
