#if canImport(SwiftUI)
import SwiftUI
import DuplexVoiceKitCompanion

public struct DVKPlaybackAmplitudeView: View {
    private let amplitude: Float
    public init(amplitude: Float) { self.amplitude = min(1, max(0, amplitude)) }
    public var body: some View {
        HStack(spacing: 4) { ForEach(0..<7, id: \.self) { index in Capsule().fill(.tint).frame(width: 5, height: 8 + CGFloat(amplitude) * CGFloat(8 + index * 2)) } }
            .frame(height: 42).accessibilityLabel("Playback amplitude").accessibilityIdentifier("playback.amplitude")
    }
}
#endif
