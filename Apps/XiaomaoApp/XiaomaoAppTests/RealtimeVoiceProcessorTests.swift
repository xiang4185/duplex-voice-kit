import XCTest
@testable import XiaomaoApp

final class RealtimeVoiceProcessorTests: XCTestCase {
    func testOrdinaryFramesStayOffMainActorContractAndThrottleUIUpdates() {
        let processor = RealtimeVoiceProcessor(configuration: .xiaomaoRealtime)
        processor.updateSession(state: .ready, responseID: "")

        let silentFrame = pcm16Frame(amplitude: 0, milliseconds: 20)
        var uiUpdateCount = 0

        for _ in 0..<20 {
            let result = processor.process(silentFrame)
            XCTAssertEqual(result.intents.count, 1)
            if result.uiSnapshot != nil { uiUpdateCount += 1 }
        }

        // A tight burst must not publish one SwiftUI update per 20 ms audio frame.
        XCTAssertLessThanOrEqual(uiUpdateCount, 2)
    }

    func testCommitStopsPostEndpointAudioUntilReset() {
        let processor = RealtimeVoiceProcessor(configuration: .xiaomaoRealtime)
        processor.updateSession(state: .ready, responseID: "")

        let speech = pcm16Frame(amplitude: 0.20, milliseconds: 20)
        let silence = pcm16Frame(amplitude: 0, milliseconds: 20)

        var sawCommit = false
        for _ in 0..<20 {
            _ = processor.process(speech)
        }
        for _ in 0..<30 {
            let result = processor.process(silence)
            if result.intents.contains(where: isCommit) {
                sawCommit = true
                break
            }
        }

        XCTAssertTrue(sawCommit)
        XCTAssertTrue(processor.process(silence).intents.isEmpty)

        processor.resetForListening()
        processor.updateSession(state: .ready, responseID: "")
        XCTAssertFalse(processor.process(silence).intents.isEmpty)
    }

    private func isCommit(_ intent: AudioUploadIntent) -> Bool {
        if case .commit = intent { return true }
        return false
    }

    private func pcm16Frame(amplitude: Double, milliseconds: Int) -> Data {
        let sampleCount = 16_000 * milliseconds / 1_000
        let sample = Int16(max(-1, min(1, amplitude)) * Double(Int16.max))
        var samples = Array(repeating: sample, count: sampleCount)
        return samples.withUnsafeMutableBytes { Data($0) }
    }
}
