import Foundation

enum VoiceFrameProcessingMode: Sendable, Equatable {
    case inactive
    case listening
    case bargeIn
}

struct VoiceVADPresentation: Sendable, Equatable {
    let state: VoiceActivityState
    let normalizedRMS: Double
    let energyBand: String

    static let idle = VoiceVADPresentation(
        state: .idleListening,
        normalizedRMS: 0,
        energyBand: "silent"
    )
}

enum VoiceFrameControl: Sendable {
    case rejectedNoise
    case speechStarted(frames: [Data], bargeIn: Bool)
    case commit(speechDurationMilliseconds: Int, endingSilenceMilliseconds: Int)
}

struct VoiceFrameProcessingResult: Sendable {
    let intents: [AudioUploadIntent]
    let controls: [VoiceFrameControl]
    let presentation: VoiceVADPresentation?

    static let inactive = VoiceFrameProcessingResult(
        intents: [],
        controls: [],
        presentation: nil
    )
}

/// Owns the mutable VAD state away from MainActor.
///
/// The upload actor calls this once per 20 ms PCM frame. Continuous audio and
/// detector state therefore stay on the audio pipeline actor. MainActor only
/// receives semantic control transitions and a throttled presentation sample.
actor VoiceFrameProcessor {
    private var detector: VoiceActivityDetector
    private var mode: VoiceFrameProcessingMode = .inactive
    private let presentationIntervalMilliseconds: Int
    private var presentationElapsedMilliseconds = 0
    private var lastPresentedState: VoiceActivityState?

    init(
        configuration: VoiceActivityConfiguration,
        presentationIntervalMilliseconds: Int = 80
    ) {
        detector = VoiceActivityDetector(configuration: configuration)
        self.presentationIntervalMilliseconds = max(20, presentationIntervalMilliseconds)
    }

    func setMode(_ mode: VoiceFrameProcessingMode) {
        self.mode = mode
    }

    func resetForListening() {
        detector.resetForListening()
        resetPresentationCadence()
    }

    func suspend() {
        detector.suspend()
        mode = .inactive
        resetPresentationCadence()
    }

    func process(_ data: Data) -> VoiceFrameProcessingResult {
        guard mode != .inactive else { return .inactive }

        let activityMode: VoiceActivityMode = mode == .bargeIn ? .bargeIn : .listening
        let analysis = detector.process(data, mode: activityMode)
        var intents: [AudioUploadIntent] = mode == .listening ? [.audio(data)] : []
        var controls: [VoiceFrameControl] = []

        for action in analysis.actions {
            switch action {
            case .rejectedNoise:
                controls.append(.rejectedNoise)

            case .speechStarted(let frames, let bargeIn):
                controls.append(.speechStarted(frames: frames, bargeIn: bargeIn))
                if !bargeIn {
                    intents.append(.beginUtterance(interruptResponseID: nil))
                }

            case .audio(let frame):
                if mode == .bargeIn {
                    intents.append(.audio(frame))
                }

            case .commit(_, let speechDuration, let endingSilence):
                controls.append(.commit(
                    speechDurationMilliseconds: speechDuration,
                    endingSilenceMilliseconds: endingSilence
                ))
                intents.append(.commit)
            }
        }

        presentationElapsedMilliseconds += frameDurationMilliseconds(data)
        let shouldPublishPresentation = lastPresentedState == nil
            || lastPresentedState != analysis.state
            || presentationElapsedMilliseconds >= presentationIntervalMilliseconds
        let presentation: VoiceVADPresentation?
        if shouldPublishPresentation {
            presentation = VoiceVADPresentation(
                state: analysis.state,
                normalizedRMS: analysis.normalizedRMS,
                energyBand: analysis.energyBand
            )
            lastPresentedState = analysis.state
            presentationElapsedMilliseconds = 0
        } else {
            presentation = nil
        }

        return VoiceFrameProcessingResult(
            intents: intents,
            controls: controls,
            presentation: presentation
        )
    }

    private func resetPresentationCadence() {
        presentationElapsedMilliseconds = 0
        lastPresentedState = nil
    }

    private func frameDurationMilliseconds(_ data: Data) -> Int {
        let configuration = detector.configuration
        guard configuration.sampleRate > 0, configuration.bytesPerSample > 0 else { return 0 }
        let sampleCount = data.count / configuration.bytesPerSample
        return max(
            0,
            Int((Double(sampleCount) / Double(configuration.sampleRate) * 1_000).rounded())
        )
    }
}
