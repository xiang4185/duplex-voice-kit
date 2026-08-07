import Foundation
import XCTest
@testable import DuplexVoiceKit

final class DVKVoiceActivityDetectorTests: XCTestCase {
    func testDefaultParametersRemainStable() {
        let configuration = DVKVoiceActivityConfiguration.realtimeDefault

        XCTAssertEqual(configuration.preRollMilliseconds, 240)
        XCTAssertEqual(configuration.minimumSpeechMilliseconds, 200)
        XCTAssertEqual(configuration.bargeInMinimumSpeechMilliseconds, 280)
        XCTAssertEqual(configuration.candidateAbortSilenceMilliseconds, 180)
        XCTAssertEqual(configuration.endSilenceMilliseconds, 700)
        XCTAssertEqual(configuration.maximumUtteranceMilliseconds, 20_000)
        XCTAssertEqual(configuration.speechRMSThreshold, 0.025)
        XCTAssertEqual(configuration.bargeInRMSThreshold, 0.075)
    }

    func testReplacingEndSilencePreservesAllOtherCoreParameters() {
        let base = DVKVoiceActivityConfiguration.realtimeDefault
        let tuned = base.replacingEndSilence(milliseconds: 480)

        XCTAssertEqual(tuned.sampleRate, base.sampleRate)
        XCTAssertEqual(tuned.bytesPerSample, base.bytesPerSample)
        XCTAssertEqual(tuned.preRollMilliseconds, base.preRollMilliseconds)
        XCTAssertEqual(tuned.minimumSpeechMilliseconds, base.minimumSpeechMilliseconds)
        XCTAssertEqual(tuned.bargeInMinimumSpeechMilliseconds, base.bargeInMinimumSpeechMilliseconds)
        XCTAssertEqual(tuned.candidateAbortSilenceMilliseconds, base.candidateAbortSilenceMilliseconds)
        XCTAssertEqual(tuned.maximumUtteranceMilliseconds, base.maximumUtteranceMilliseconds)
        XCTAssertEqual(tuned.speechRMSThreshold, base.speechRMSThreshold)
        XCTAssertEqual(tuned.bargeInRMSThreshold, base.bargeInRMSThreshold)
        XCTAssertEqual(tuned.endSilenceMilliseconds, 480)
        XCTAssertEqual(base.endSilenceMilliseconds, 700)
    }

    func testSpeechStartsAfterMinimumSpeechAndCommitsAfterEndSilence() {
        var detector = DVKVoiceActivityDetector()
        var started = false

        for _ in 0..<10 {
            let analysis = detector.process(pcmFrame(amplitude: 2_000), mode: .listening)
            if analysis.actions.contains(where: isSpeechStarted) {
                started = true
            }
        }

        XCTAssertTrue(started)
        XCTAssertEqual(detector.state, .sendingSpeech)

        var commitReason: DVKVoiceActivityCommitReason?
        for _ in 0..<35 {
            let analysis = detector.process(pcmFrame(amplitude: 0), mode: .listening)
            for action in analysis.actions {
                if case .commit(let reason, _, _) = action {
                    commitReason = reason
                }
            }
        }

        XCTAssertEqual(commitReason, .endSilence)
        XCTAssertEqual(detector.state, .endpointing)
    }

    func testBargeInUsesHigherThreshold() {
        var detector = DVKVoiceActivityDetector()

        for _ in 0..<20 {
            _ = detector.process(pcmFrame(amplitude: 1_500), mode: .bargeIn)
        }

        XCTAssertEqual(detector.state, .idleListening)
    }

    private func isSpeechStarted(_ action: DVKVoiceActivityAction) -> Bool {
        if case .speechStarted = action { return true }
        return false
    }

    private func pcmFrame(amplitude: Int16, milliseconds: Int = 20) -> Data {
        let sampleCount = 16_000 * milliseconds / 1_000
        let samples = [Int16](repeating: amplitude, count: sampleCount)
        return samples.withUnsafeBytes { Data($0) }
    }
}
