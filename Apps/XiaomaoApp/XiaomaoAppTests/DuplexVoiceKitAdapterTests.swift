import DuplexVoiceKit
import Foundation
import XCTest
@testable import XiaomaoApp

final class DuplexVoiceKitAdapterTests: XCTestCase {
    func testOutboundAdapterPreservesProtocolEnvelopeWithoutManagingLifecycle() async throws {
        let socket = AdapterRecordingSocket()
        let adapter = XiaomaoDVKOutboundTransport(socket: socket)
        let message = DVKOutboundMessage(
            version: "0.2",
            eventID: "event-id",
            traceID: "trace-id",
            sessionID: "session-id",
            sequence: 17,
            timestamp: 1_785_427_200_123,
            type: "audio.append",
            payload: [
                "chunk_index": .int(3),
                "nested": .object(["ready": .bool(true)]),
                "items": .array([.string("a"), .null])
            ]
        )

        try await adapter.send(message)

        let sentEvents = await socket.sentEvents()
        let event = try XCTUnwrap(sentEvents.first)
        XCTAssertEqual(event.version, message.version)
        XCTAssertEqual(event.eventID, message.eventID)
        XCTAssertEqual(event.traceID, message.traceID)
        XCTAssertEqual(event.sessionID, message.sessionID)
        XCTAssertEqual(event.sequence, message.sequence)
        XCTAssertEqual(event.timestamp, message.timestamp)
        XCTAssertEqual(event.type.rawValue, message.type)
        XCTAssertEqual(event.payload["chunk_index"], .int(3))
        XCTAssertEqual(event.payload["nested"], .object(["ready": .bool(true)]))
        XCTAssertEqual(event.payload["items"], .array([.string("a"), .null]))
        let connectCount = await socket.connectCount()
        let disconnectCount = await socket.disconnectCount()
        XCTAssertEqual(connectCount, 0)
        XCTAssertEqual(disconnectCount, 0)
    }

    func testProjectUsesLocalRepositoryPackage() throws {
        let project = try String(
            contentsOf: projectRoot().appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        XCTAssertTrue(project.contains("path: ../.."))
        XCTAssertFalse(project.contains("url: https://github.com/xiang4185/duplex-voice-kit.git"))
        XCTAssertFalse(project.contains("revision:"))
        XCTAssertFalse(project.contains("branch: main"))
        XCTAssertFalse(project.contains("git@github.com:xiang4185/duplex-voice-kit"))
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private actor AdapterRecordingSocket: VoiceWebSocketClient {
    nonisolated let lifecycleEvents: AsyncStream<VoiceWebSocketLifecycleEvent>
    private let lifecycleContinuation: AsyncStream<VoiceWebSocketLifecycleEvent>.Continuation
    private var recorded: [VoiceEvent] = []
    private var connects = 0
    private var disconnects = 0

    init() {
        let pair = AsyncStream<VoiceWebSocketLifecycleEvent>.makeStream(bufferingPolicy: .bufferingNewest(4))
        lifecycleEvents = pair.stream
        lifecycleContinuation = pair.continuation
    }

    nonisolated func makeEventStream() -> AsyncStream<VoiceEvent> {
        AsyncStream { $0.finish() }
    }

    func connect(url: URL, token: String, deviceID: String) async throws {
        _ = url
        _ = token
        _ = deviceID
        connects += 1
    }

    func send(_ event: VoiceEvent) async throws {
        recorded.append(event)
    }

    func ping() async throws {}

    func disconnect() async {
        disconnects += 1
        lifecycleContinuation.finish()
    }

    func isConnected() async -> Bool { true }
    func sentEvents() -> [VoiceEvent] { recorded }
    func connectCount() -> Int { connects }
    func disconnectCount() -> Int { disconnects }
}
