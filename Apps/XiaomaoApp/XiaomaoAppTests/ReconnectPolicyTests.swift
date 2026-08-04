import XCTest
@testable import XiaomaoApp

final class ReconnectPolicyTests: XCTestCase {
    func testBackoffIsBounded() async {
        let controller = VoiceReconnectController()
        var delays: [Duration] = []
        for _ in 0..<5 {
            if let delay = await controller.nextDelay() { delays.append(delay) }
        }
        XCTAssertEqual(delays, [
            .milliseconds(400),
            .milliseconds(800),
            .milliseconds(1_600),
            .milliseconds(3_200),
            .milliseconds(6_400)
        ])
        let exhaustedDelay = await controller.nextDelay()
        XCTAssertNil(exhaustedDelay)
    }

    func testMockWebSocketRoundTrip() async throws {
        let socket = MockWebSocketClient()
        try await socket.connect(
            url: URL(string: "ws://127.0.0.1")!,
            token: "synthetic",
            deviceID: "test-device"
        )
        let event = makeSessionStartEvent(id: "event", sessionID: "session", sequence: 1)
        var iterator = socket.makeEventStream().makeAsyncIterator()
        try await socket.send(event)
        let response = await iterator.next()
        XCTAssertEqual(response?.type, .sessionReady)
    }

    func testMockWebSocketSupportsSequentialEventSubscriptions() async throws {
        let socket = MockWebSocketClient()
        try await socket.connect(
            url: URL(string: "ws://127.0.0.1")!,
            token: "synthetic",
            deviceID: "test-device"
        )

        do {
            var firstIterator = socket.makeEventStream().makeAsyncIterator()
            try await socket.send(
                makeSessionStartEvent(id: "first", sessionID: "session-one", sequence: 1)
            )
            let firstResponse = await firstIterator.next()
            XCTAssertEqual(firstResponse?.sessionID, "session-one")
        }

        do {
            var secondIterator = socket.makeEventStream().makeAsyncIterator()
            try await socket.send(
                makeSessionStartEvent(id: "second", sessionID: "session-two", sequence: 2)
            )
            let secondResponse = await secondIterator.next()
            XCTAssertEqual(secondResponse?.sessionID, "session-two")
        }
    }

    private func makeSessionStartEvent(
        id: String,
        sessionID: String,
        sequence: Int
    ) -> VoiceEvent {
        VoiceEvent(
            version: VoiceEvent.protocolVersion,
            eventID: id,
            traceID: "trace",
            sessionID: sessionID,
            sequence: sequence,
            timestamp: 1,
            type: .sessionStart,
            payload: [:]
        )
    }
}
