import XCTest
@testable import DuplexVoiceKit

final class DVKAudioConfigurationTests: XCTestCase {
    func testRealtimeVoiceKeepsSmallPlaybackStartupBuffer() {
        XCTAssertEqual(
            DVKAudioConfiguration.realtimeVoice.playbackStartupBufferMilliseconds,
            80
        )
    }

    func testPlaybackStartupBufferCanBeDisabledAndCannotBeNegative() {
        let configuration = DVKAudioConfiguration(
            captureSampleRate: 48_000,
            playbackSampleRate: 24_000,
            channels: 1,
            captureBufferFrames: 960,
            uploadQueueCapacity: 100,
            playbackStartupBufferMilliseconds: -1
        )

        XCTAssertEqual(configuration.playbackStartupBufferMilliseconds, 0)
    }
}
