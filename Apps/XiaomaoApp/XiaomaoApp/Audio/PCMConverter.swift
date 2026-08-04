import AVFoundation
import Foundation

struct PCMConverter {
    let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    func convert(_ buffer: AVAudioPCMBuffer) throws -> Data {
        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            throw AppError.audio("converter_unavailable")
        }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            throw AppError.audio("buffer_allocation_failed")
        }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        guard let channel = output.int16ChannelData else { throw AppError.audio("missing_pcm_data") }
        return Data(bytes: channel[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }
}
