import AVFoundation
import Foundation

protocol AudioPlaying: AnyObject {
    func enqueue(_ data: Data, responseID: String, chunkIndex: Int)
    func cancel(responseID: String?)
}

final class AudioPlaybackEngine: AudioPlaying {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!
    private let queue = DispatchQueue(label: "xiaomao.audio.playback")
    private var currentResponseID = ""
    private var pending: [Int: Data] = [:]
    private var nextIndex = 0

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    func enqueue(_ data: Data, responseID: String, chunkIndex: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.currentResponseID != responseID {
                self.player.stop()
                self.pending.removeAll()
                self.currentResponseID = responseID
                self.nextIndex = 0
            }
            if !self.engine.isRunning {
                try? self.engine.start()
            }
            self.pending[chunkIndex] = data
            self.scheduleReadyChunks()
        }
    }

    func cancel(responseID: String?) {
        queue.async { [weak self] in
            guard let self else { return }
            if responseID == nil || responseID == self.currentResponseID {
                self.player.stop()
                self.pending.removeAll()
                self.currentResponseID = ""
                self.nextIndex = 0
            }
        }
    }

    private func scheduleReadyChunks() {
        while let data = pending.removeValue(forKey: nextIndex) {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                               frameCapacity: AVAudioFrameCount(data.count / 2)),
                  let channel = buffer.int16ChannelData else { return }
            buffer.frameLength = buffer.frameCapacity
            data.copyBytes(to: UnsafeMutableBufferPointer(start: channel[0], count: data.count / 2))
            player.scheduleBuffer(buffer)
            nextIndex += 1
        }
        if !player.isPlaying { player.play() }
    }
}

final class MockAudioPlayback: AudioPlaying {
    private(set) var chunks: [(String, Int)] = []
    func enqueue(_ data: Data, responseID: String, chunkIndex: Int) {
        _ = data
        chunks.append((responseID, chunkIndex))
    }
    func cancel(responseID: String?) {
        chunks.removeAll { responseID == nil || $0.0 == responseID }
    }
}
