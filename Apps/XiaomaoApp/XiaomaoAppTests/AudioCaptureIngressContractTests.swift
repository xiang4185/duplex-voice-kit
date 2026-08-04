import DuplexVoiceKit
import Foundation
import XCTest
@testable import XiaomaoApp

final class AudioCaptureIngressContractTests: XCTestCase {
    func testRouteBRealtimeAdapterDelegatesCaptureToDVK() throws {
        let source = try realtimeAudioSource()
        XCTAssertTrue(source.contains("DVKRealtimeAudioIO"))
        XCTAssertTrue(source.contains("DVKAudioCaptureSink"))
        XCTAssertTrue(source.contains("core.startCapture()"))
        XCTAssertTrue(source.contains("core?.stopCapture()"))
    }

    func testCapturedPacketOwnsItsMemory() {
        var source = Data(repeating: 1, count: 640)
        let packet = CapturedAudioPacket.pcm16(
            source,
            captureGeneration: 7,
            capturedAt: Date(timeIntervalSince1970: 123)
        )
        source[0] = 9

        XCTAssertEqual(packet.data[0], 1)
        XCTAssertEqual(packet.captureGeneration, 7)
        XCTAssertEqual(packet.capturedAt, Date(timeIntervalSince1970: 123))
    }

    func testPrivateUploadAdapterContainsNoDuplicateIngress() throws {
        let source = try uploadActorSource()
        XCTAssertTrue(source.contains("DVKAudioUploadPipeline"))
        XCTAssertFalse(source.contains("AudioUploadIngress"))
        XCTAssertFalse(source.contains("DispatchSemaphore"))
        XCTAssertFalse(source.contains("drainTask"))
        XCTAssertFalse(source.contains("pendingPCM16"))
    }

    func testCaptureBridgeDoesNotCreatePerFrameTasks() throws {
        let source = try realtimeAudioSource()
        let bridge = try sourcePath(
            in: source,
            from: "private final class XiaomaoDVKCaptureBridge",
            to: "handler?(packet)"
        )
        XCTAssertFalse(bridge.contains("Task"))
        XCTAssertFalse(bridge.contains("DispatchQueue"))
        XCTAssertFalse(bridge.contains("await"))
    }

    func testRouteBAdapterDoesNotPerformProtocolEncoding() throws {
        let source = try realtimeAudioSource()
        let captureBridge = try sourcePath(
            in: source,
            from: "private final class XiaomaoDVKCaptureBridge",
            to: "handler?(packet)"
        )
        for forbidden in [
            "JSONEncoder",
            "base64EncodedString",
            "VoiceEvent",
            "chunkIndex",
            "WebSocket",
            "socket"
        ] {
            XCTAssertFalse(captureBridge.contains(forbidden), forbidden)
        }

        let playbackAdapter = try sourcePath(
            in: source,
            from: "func enqueue(_ data: Data, responseID: String, chunkIndex: Int)",
            to: "core?.enqueuePlayback(data, responseID: responseID, chunkIndex: chunkIndex)"
        )
        XCTAssertTrue(
            playbackAdapter.contains(
                "core?.enqueuePlayback(data, responseID: responseID, chunkIndex: chunkIndex)"
            )
        )
        XCTAssertFalse(playbackAdapter.contains("chunk_index"))
        XCTAssertFalse(playbackAdapter.contains("chunkIndex +"))
        XCTAssertFalse(playbackAdapter.contains("chunkIndex &+"))
    }

    func testRouteBAdapterDoesNotCallWebSocket() throws {
        let source = try realtimeAudioSource()
        XCTAssertFalse(source.contains("socket"))
        XCTAssertFalse(source.contains("WebSocket"))
    }

    func testSystemRecoveryDelegatesToSingleDVKAudioGraph() throws {
        let source = try realtimeAudioSource()
        XCTAssertTrue(source.contains("try core.recoverCapture()"))
        XCTAssertTrue(source.contains("core?.shutdown()"))
        XCTAssertFalse(source.contains("AVAudioEngine"))
        XCTAssertFalse(source.contains("AVAudioPlayerNode"))
        XCTAssertFalse(source.contains("installTap"))
        XCTAssertFalse(source.contains("mediaServicesWereResetNotification"))
        XCTAssertFalse(source.contains("AVAudioEngineConfigurationChange"))
    }

    func testCapturedPacketIncludesRequiredMetadata() {
        let capturedAt = Date()
        let packet = CapturedAudioPacket.pcm16(
            Data(repeating: 0, count: 640),
            captureGeneration: 11,
            capturedAt: capturedAt
        )
        XCTAssertEqual(packet.sampleRate, 16_000)
        XCTAssertEqual(packet.channels, 1)
        XCTAssertEqual(packet.frameCount, 320)
        XCTAssertEqual(packet.captureGeneration, 11)
        XCTAssertEqual(packet.capturedAt, capturedAt)
    }

    private func sourcePath(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker))
        let end = try XCTUnwrap(
            source.range(of: endMarker, range: start.upperBound..<source.endIndex)
        )
        return String(source[start.lowerBound..<end.upperBound])
    }

    private func realtimeAudioSource() throws -> String {
        try sourceFile("XiaomaoApp/Audio/RealtimeAudioIOEngine.swift")
    }

    private func uploadActorSource() throws -> String {
        try sourceFile("XiaomaoApp/Voice/AudioUploadActor.swift")
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
