import AVFoundation
import Foundation

protocol AudioCapturing: AnyObject {
    var onPacket: ((CapturedAudioPacket) -> Void)? { get set }
    var captureGeneration: Int { get }
    func start() throws
    func stop()
}

final class AudioCaptureEngine: AudioCapturing {
    var onPacket: ((CapturedAudioPacket) -> Void)?
    private let engine = AVAudioEngine()
    private let converter = PCMConverter()
    private let queue = DispatchQueue(label: "xiaomao.audio.capture")
    private let preferredChunkBytes = 640
    private var pending = Data()
    private var installed = false
    private(set) var captureGeneration = 0

    func start() throws {
        guard !installed else { return }
        let input = engine.inputNode
        if !input.isVoiceProcessingEnabled {
            try input.setVoiceProcessingEnabled(true)
        }
        let format = input.inputFormat(forBus: 0)
        captureGeneration &+= 1
        let generation = captureGeneration
        input.installTap(onBus: 0, bufferSize: 960, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.queue.async {
                guard let data = try? self.converter.convert(buffer) else { return }
                self.pending.append(data)
                while self.pending.count >= self.preferredChunkBytes {
                    let chunk = Data(self.pending.prefix(self.preferredChunkBytes))
                    self.pending.removeFirst(self.preferredChunkBytes)
                    self.onPacket?(.pcm16(chunk, captureGeneration: generation))
                }
            }
        }
        engine.prepare()
        try engine.start()
        installed = true
    }

    func stop() {
        guard installed else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        pending.removeAll(keepingCapacity: false)
        captureGeneration &+= 1
        installed = false
    }
}

final class MockAudioCapture: AudioCapturing {
    var onPacket: ((CapturedAudioPacket) -> Void)?
    private(set) var captureGeneration = 0
    func start() throws {
        captureGeneration &+= 1
        onPacket?(.pcm16(Data(repeating: 0, count: 640), captureGeneration: captureGeneration))
    }
    func stop() { captureGeneration &+= 1 }
}
