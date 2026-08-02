import Foundation
import DuplexVoiceKit

public final class DVKPlaybackAmplitudeRelay: DVKPlaybackAmplitudeSink, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0
    private var onChange: (@Sendable (Float) -> Void)?

    public init(onChange: (@Sendable (Float) -> Void)? = nil) { self.onChange = onChange }

    public func setOnChange(_ onChange: (@Sendable (Float) -> Void)?) {
        lock.lock()
        self.onChange = onChange
        lock.unlock()
    }

    public func playbackAmplitudeDidChange(_ amplitude: Float) {
        let clamped = min(1, max(0, amplitude))
        lock.lock()
        value = clamped
        let callback = onChange
        lock.unlock()
        callback?(clamped)
    }

    public var currentAmplitude: Float {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

#if canImport(SwiftUI)
import SwiftUI

public struct DVKPlaybackAmplitudeView: View {
    public let amplitude: Float
    public let reduceMotion: Bool

    public init(amplitude: Float, reduceMotion: Bool = false) {
        self.amplitude = min(1, max(0, amplitude))
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(0..<9, id: \.self) { index in
                Capsule()
                    .fill(.tint)
                    .frame(width: 6, height: barHeight(index: index))
            }
        }
        .frame(height: 48)
        .accessibilityLabel("Assistant playback energy")
        .accessibilityValue("\(Int(amplitude * 100)) percent")
    }

    private func barHeight(index: Int) -> CGFloat {
        if reduceMotion { return 9 + CGFloat(amplitude) * 14 }
        let profile: [CGFloat] = [0.35, 0.62, 0.86, 1.0, 0.72, 0.92, 0.64, 0.48, 0.3]
        return 9 + CGFloat(amplitude) * 30 * profile[index]
    }
}
#endif
