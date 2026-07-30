import Foundation
import XCTest
@testable import DuplexVoiceKit

final class DVKProtocolTests: XCTestCase {
    func testOutboundMessageRoundTripPreservesEnvelope() throws {
        let message = DVKOutboundMessage(
            version: "0.2",
            eventID: "event-1",
            traceID: "trace-1",
            sessionID: "session-1",
            sequence: 7,
            timestamp: 123,
            type: "audio.append",
            payload: [
                "chunk_index": .int(3),
                "audio": .string("AA==")
            ]
        )

        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(DVKOutboundMessage.self, from: encoded)

        XCTAssertEqual(decoded, message)
    }

    func testCodecOwnsMonotonicClientSequence() {
        var codec = DVKProtocolCodec()
        let first = codec.makeMessage(
            type: .sessionStart,
            sessionID: "session",
            traceID: "trace"
        )
        let second = codec.makeMessage(
            type: .ping,
            sessionID: "session",
            traceID: "trace"
        )

        XCTAssertEqual(first.sequence, 1)
        XCTAssertEqual(second.sequence, 2)
        XCTAssertEqual(codec.clientSequence, 2)
    }

    func testResponseFilterRejectsStaleAndMismatchedAudio() {
        var filter = DVKResponseFilter()
        filter.begin(responseID: "response-a", serverSequence: 10)

        XCTAssertFalse(filter.acceptAudio(responseID: "response-a", serverSequence: 10))
        XCTAssertFalse(filter.acceptAudio(responseID: "response-b", serverSequence: 11))
        XCTAssertTrue(filter.acceptAudio(responseID: "response-a", serverSequence: 12))
        XCTAssertTrue(filter.finish(responseID: "response-a", serverSequence: 13))
        XCTAssertEqual(filter.responseID, "")
    }
}
