import Foundation
import XCTest
@testable import DuplexVoiceKit

final class DVKDiagnosticsTests: XCTestCase {
    func testDiagnosticsContainOnlyOrderAndHealthMetadata() {
        let snapshot = DVKDiagnosticsSnapshot(
            state: .ready,
            transportState: "connected",
            sessionHash: DVKDiagnosticsSnapshot.shortHash("session-123"),
            lastEventType: "response.audio.delta",
            lastEventSequence: 12,
            reconnectAttempt: 0,
            captureGeneration: 3,
            uploadConnectionGeneration: 2,
            uploadNextChunkIndex: 8,
            uploadNextClientSequence: 11,
            uploadQueueDepth: 1,
            uploadQueueHighWater: 4,
            droppedStaleGenerationChunks: 2,
            inputBackpressureCount: 0,
            lastFiveSentChunkIndices: [3, 4, 5, 6, 7],
            lastFailureCategory: "none",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        let text = snapshot.redactedText.lowercased()
        XCTAssertTrue(text.contains("upload_next_chunk_index=8"))
        XCTAssertFalse(text.contains("authorization="))
        XCTAssertFalse(text.contains("speaker_id="))
        XCTAssertFalse(text.contains("transcript="))
        XCTAssertFalse(text.contains("audio_base64="))
    }

    func testShortHashIsStableAndDoesNotExposeInput() {
        let first = DVKDiagnosticsSnapshot.shortHash("session-123")
        let second = DVKDiagnosticsSnapshot.shortHash("session-123")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 8)
        XCTAssertFalse(first.contains("session"))
    }
}
