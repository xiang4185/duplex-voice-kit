import Foundation
import XCTest
@testable import XiaomaoApp

final class VoiceActivityDetectorTests: XCTestCase {
    private let configuration = VoiceActivityConfiguration(
        sampleRate: 16_000,
        bytesPerSample: 2,
        preRollMilliseconds: 40,
        minimumSpeechMilliseconds: 40,
        bargeInMinimumSpeechMilliseconds: 60,
        candidateAbortSilenceMilliseconds: 40,
        endSilenceMilliseconds: 40,
        maximumUtteranceMilliseconds: 100,
        speechRMSThreshold: 0.02,
        bargeInRMSThreshold: 0.08
    )

    func testPureSilenceProducesNoNetworkActions() {
        var detector = VoiceActivityDetector(configuration: configuration)
        let actions = (0..<20).flatMap { _ in
            detector.process(frame(amplitude: 0), mode: .listening).actions
        }
        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(detector.state, .idleListening)
    }

    func testShortNoiseIsRejected() {
        var detector = VoiceActivityDetector(configuration: configuration)
        var actions: [VoiceActivityAction] = []
        actions += detector.process(frame(amplitude: 3_000), mode: .listening).actions
        actions += detector.process(frame(amplitude: 0), mode: .listening).actions
        actions += detector.process(frame(amplitude: 0), mode: .listening).actions
        XCTAssertEqual(rejectedCount(actions), 1)
        XCTAssertEqual(speechStartCount(actions), 0)
        XCTAssertEqual(commitCount(actions), 0)
    }

    func testValidSpeechStartsExactlyOnceAndIncludesPreRoll() {
        var detector = VoiceActivityDetector(configuration: configuration)
        _ = detector.process(frame(amplitude: 0), mode: .listening)
        _ = detector.process(frame(amplitude: 0), mode: .listening)
        var actions: [VoiceActivityAction] = []
        actions += detector.process(frame(amplitude: 3_000), mode: .listening).actions
        actions += detector.process(frame(amplitude: 3_000), mode: .listening).actions
        XCTAssertEqual(speechStartCount(actions), 1)
        let frames = speechStartFrames(actions)
        XCTAssertGreaterThanOrEqual(frames.count, 3)
    }

    func testEndSilenceCommitsOnlyOnce() {
        var detector = VoiceActivityDetector(configuration: configuration)
        _ = detector.process(frame(amplitude: 3_000), mode: .listening)
        _ = detector.process(frame(amplitude: 3_000), mode: .listening)
        var actions: [VoiceActivityAction] = []
        actions += detector.process(frame(amplitude: 0), mode: .listening).actions
        actions += detector.process(frame(amplitude: 0), mode: .listening).actions
        actions += detector.process(frame(amplitude: 0), mode: .listening).actions
        XCTAssertEqual(commitCount(actions), 1)
        XCTAssertTrue(actions.containsCommit(reason: .endSilence))
    }

    func testMaximumDurationTriggersSafeCommit() {
        var detector = VoiceActivityDetector(configuration: configuration)
        var actions: [VoiceActivityAction] = []
        for _ in 0..<8 {
            actions += detector.process(frame(amplitude: 3_000), mode: .listening).actions
        }
        XCTAssertEqual(commitCount(actions), 1)
        XCTAssertTrue(actions.containsCommit(reason: .maximumDuration))
    }

    func testBargeInThresholdRejectsPlaybackLikeLowEnergy() {
        var detector = VoiceActivityDetector(configuration: configuration)
        var actions: [VoiceActivityAction] = []
        for _ in 0..<8 {
            actions += detector.process(frame(amplitude: 1_500), mode: .bargeIn).actions
        }
        XCTAssertEqual(speechStartCount(actions), 0)
        XCTAssertEqual(commitCount(actions), 0)
    }

    func testXiaomaoRealtimePreservesCoreThresholdsAndShortensOnlyEndSilence() {
        let xiaomao = VoiceActivityConfiguration.xiaomaoRealtime
        let core = VoiceActivityConfiguration.realtimeDefault

        XCTAssertEqual(xiaomao.sampleRate, core.sampleRate)
        XCTAssertEqual(xiaomao.bytesPerSample, core.bytesPerSample)
        XCTAssertEqual(xiaomao.preRollMilliseconds, core.preRollMilliseconds)
        XCTAssertEqual(xiaomao.minimumSpeechMilliseconds, core.minimumSpeechMilliseconds)
        XCTAssertEqual(xiaomao.bargeInMinimumSpeechMilliseconds, core.bargeInMinimumSpeechMilliseconds)
        XCTAssertEqual(xiaomao.candidateAbortSilenceMilliseconds, core.candidateAbortSilenceMilliseconds)
        XCTAssertEqual(xiaomao.maximumUtteranceMilliseconds, core.maximumUtteranceMilliseconds)
        XCTAssertEqual(xiaomao.speechRMSThreshold, core.speechRMSThreshold)
        XCTAssertEqual(xiaomao.bargeInRMSThreshold, core.bargeInRMSThreshold)
        XCTAssertEqual(xiaomao.endSilenceMilliseconds, 400)
        XCTAssertLessThan(xiaomao.endSilenceMilliseconds, core.endSilenceMilliseconds)
    }

    private func frame(amplitude: Int16) -> Data {
        var samples = Array(repeating: amplitude, count: 320)
        return samples.withUnsafeBytes { Data($0) }
    }

    private func speechStartCount(_ actions: [VoiceActivityAction]) -> Int {
        actions.reduce(0) { count, action in
            if case .speechStarted = action { return count + 1 }
            return count
        }
    }

    private func speechStartFrames(_ actions: [VoiceActivityAction]) -> [Data] {
        for action in actions {
            if case .speechStarted(let frames, _) = action { return frames }
        }
        return []
    }

    private func rejectedCount(_ actions: [VoiceActivityAction]) -> Int {
        actions.reduce(0) { count, action in
            if case .rejectedNoise = action { return count + 1 }
            return count
        }
    }

    private func commitCount(_ actions: [VoiceActivityAction]) -> Int {
        actions.reduce(0) { count, action in
            if case .commit = action { return count + 1 }
            return count
        }
    }
}

private extension Array where Element == VoiceActivityAction {
    func containsCommit(reason expected: VoiceActivityCommitReason) -> Bool {
        contains { action in
            if case .commit(let reason, _, _) = action { return reason == expected }
            return false
        }
    }
}
