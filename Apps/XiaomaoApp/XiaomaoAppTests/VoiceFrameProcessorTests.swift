import Foundation
import XCTest
@testable import XiaomaoApp

final class VoiceFrameProcessorTests: XCTestCase {
    func testSilentRealtimeFramesPublishPresentationAtMostFifteenTimesPerSecond() async {
        let processor = VoiceFrameProcessor(
            configuration: .xiaomaoRealtime,
            presentationIntervalMilliseconds: 80
        )
        await processor.setMode(.listening)

        var presentationCount = 0
        for _ in 0..<50 {
            let result = await processor.process(pcmFrame(amplitude: 0))
            if result.presentation != nil {
                presentationCount += 1
            }
            XCTAssertEqual(result.intents.count, 1)
            guard case .audio = result.intents[0] else {
                return XCTFail("listening mode must preserve continuous audio upload")
            }
        }

        XCTAssertEqual(presentationCount, 13)
    }

    func testVADStateTransitionPublishesImmediatelyBetweenMeterTicks() async {
        let processor = VoiceFrameProcessor(
            configuration: .xiaomaoRealtime,
            presentationIntervalMilliseconds: 80
        )
        await processor.setMode(.listening)

        _ = await processor.process(pcmFrame(amplitude: 0))
        let result = await processor.process(pcmFrame(amplitude: 6_000))

        XCTAssertEqual(result.presentation?.state, .speechDetected)
        XCTAssertEqual(result.presentation?.energyBand, "high")
    }

    func testListeningIntentOrderAndCommitSemanticsRemainUnchanged() async {
        let processor = VoiceFrameProcessor(
            configuration: .xiaomaoRealtime,
            presentationIntervalMilliseconds: 80
        )
        await processor.setMode(.listening)

        var speechStartResult: VoiceFrameProcessingResult?
        for _ in 0..<10 {
            let result = await processor.process(pcmFrame(amplitude: 6_000))
            if result.controls.contains(where: { control in
                if case .speechStarted = control { return true }
                return false
            }) {
                speechStartResult = result
            }
        }

        let started = try? XCTUnwrap(speechStartResult)
        XCTAssertEqual(started?.intents.count, 2)
        if let intents = started?.intents, intents.count == 2 {
            guard case .audio = intents[0] else {
                return XCTFail("continuous audio must precede beginUtterance")
            }
            guard case .beginUtterance(let responseID) = intents[1] else {
                return XCTFail("speech confirmation must begin the utterance")
            }
            XCTAssertNil(responseID)
        }

        var commitResult: VoiceFrameProcessingResult?
        for _ in 0..<20 {
            let result = await processor.process(pcmFrame(amplitude: 0))
            if result.controls.contains(where: { control in
                if case .commit = control { return true }
                return false
            }) {
                commitResult = result
                break
            }
        }

        let committed = try? XCTUnwrap(commitResult)
        XCTAssertEqual(committed?.intents.count, 2)
        if let intents = committed?.intents, intents.count == 2 {
            guard case .audio = intents[0] else {
                return XCTFail("final silence audio must remain before commit")
            }
            guard case .commit = intents[1] else {
                return XCTFail("endpointing must preserve commit intent")
            }
        }
    }

    func testInactiveModeDoesNotAdvanceVADOrUploadFrames() async {
        let processor = VoiceFrameProcessor(
            configuration: .xiaomaoRealtime,
            presentationIntervalMilliseconds: 80
        )

        for _ in 0..<20 {
            let result = await processor.process(pcmFrame(amplitude: 6_000))
            XCTAssertTrue(result.intents.isEmpty)
            XCTAssertTrue(result.controls.isEmpty)
            XCTAssertNil(result.presentation)
        }

        await processor.setMode(.listening)
        let firstActiveFrame = await processor.process(pcmFrame(amplitude: 6_000))
        XCTAssertEqual(firstActiveFrame.presentation?.state, .speechDetected)
    }

    private func pcmFrame(amplitude: Int16) -> Data {
        var samples = Array(repeating: amplitude, count: 320)
        return samples.withUnsafeBytes { Data($0) }
    }
}
