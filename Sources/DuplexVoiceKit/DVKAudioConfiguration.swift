import Foundation

/// Configures capture, playback, buffering, and upload queue defaults for realtime voice.
public struct DVKAudioConfiguration: Sendable, Equatable {
    public let captureSampleRate: Double
    public let playbackSampleRate: Double
    public let channels: Int
    public let captureBufferFrames: Int
    public let uploadQueueCapacity: Int

    public static let realtimeVoice = DVKAudioConfiguration(
        captureSampleRate: 48_000,
        playbackSampleRate: 24_000,
        channels: 1,
        captureBufferFrames: 960,
        uploadQueueCapacity: 100
    )

    public init(
        captureSampleRate: Double,
        playbackSampleRate: Double,
        channels: Int,
        captureBufferFrames: Int,
        uploadQueueCapacity: Int
    ) {
        self.captureSampleRate = captureSampleRate
        self.playbackSampleRate = playbackSampleRate
        self.channels = max(1, channels)
        self.captureBufferFrames = max(1, captureBufferFrames)
        self.uploadQueueCapacity = max(1, uploadQueueCapacity)
    }
}

/// Selects normal listening or higher-threshold barge-in detection.
public enum DVKVoiceActivityMode: Sendable, Equatable {
    case listening
    case bargeIn
}

/// Describes the current state of the deterministic voice activity detector.
public enum DVKVoiceActivityState: String, Sendable, Equatable {
    case idleListening = "idle_listening"
    case speechDetected = "speech_detected"
    case sendingSpeech = "sending_speech"
    case endpointing
}

/// Identifies why an utterance was automatically committed.
public enum DVKVoiceActivityCommitReason: String, Sendable, Equatable {
    case endSilence = "end_silence"
    case maximumDuration = "maximum_duration"
}

/// Immutable voice activity thresholds and timing windows.
public struct DVKVoiceActivityConfiguration: Sendable, Equatable {
    public let sampleRate: Int
    public let bytesPerSample: Int
    public let preRollMilliseconds: Int
    public let minimumSpeechMilliseconds: Int
    public let bargeInMinimumSpeechMilliseconds: Int
    public let candidateAbortSilenceMilliseconds: Int
    public let endSilenceMilliseconds: Int
    public let maximumUtteranceMilliseconds: Int
    public let speechRMSThreshold: Double
    public let bargeInRMSThreshold: Double

    /// The production-proven realtime voice defaults extracted without parameter changes.
    public static let realtimeDefault = DVKVoiceActivityConfiguration(
        sampleRate: 16_000,
        bytesPerSample: 2,
        preRollMilliseconds: 240,
        minimumSpeechMilliseconds: 200,
        bargeInMinimumSpeechMilliseconds: 280,
        candidateAbortSilenceMilliseconds: 180,
        endSilenceMilliseconds: 700,
        maximumUtteranceMilliseconds: 20_000,
        speechRMSThreshold: 0.025,
        bargeInRMSThreshold: 0.075
    )

    /// Creates a custom voice activity configuration.
    public init(
        sampleRate: Int,
        bytesPerSample: Int,
        preRollMilliseconds: Int,
        minimumSpeechMilliseconds: Int,
        bargeInMinimumSpeechMilliseconds: Int,
        candidateAbortSilenceMilliseconds: Int,
        endSilenceMilliseconds: Int,
        maximumUtteranceMilliseconds: Int,
        speechRMSThreshold: Double,
        bargeInRMSThreshold: Double
    ) {
        self.sampleRate = sampleRate
        self.bytesPerSample = bytesPerSample
        self.preRollMilliseconds = preRollMilliseconds
        self.minimumSpeechMilliseconds = minimumSpeechMilliseconds
        self.bargeInMinimumSpeechMilliseconds = bargeInMinimumSpeechMilliseconds
        self.candidateAbortSilenceMilliseconds = candidateAbortSilenceMilliseconds
        self.endSilenceMilliseconds = endSilenceMilliseconds
        self.maximumUtteranceMilliseconds = maximumUtteranceMilliseconds
        self.speechRMSThreshold = speechRMSThreshold
        self.bargeInRMSThreshold = bargeInRMSThreshold
    }
}

/// An action emitted by the voice activity detector for the host upload pipeline.
public enum DVKVoiceActivityAction: Sendable {
    case speechStarted(frames: [Data], bargeIn: Bool)
    case audio(Data)
    case commit(
        reason: DVKVoiceActivityCommitReason,
        speechDurationMilliseconds: Int,
        endingSilenceMilliseconds: Int
    )
    case rejectedNoise
}

/// The immutable result of processing one PCM16 frame.
public struct DVKVoiceActivityAnalysis: Sendable {
    public let state: DVKVoiceActivityState
    public let normalizedRMS: Double
    public let energyBand: String
    public let actions: [DVKVoiceActivityAction]
}

/// A deterministic PCM16 voice activity detector with pre-roll, endpointing, and barge-in support.
public struct DVKVoiceActivityDetector: Sendable {
    public let configuration: DVKVoiceActivityConfiguration

    private struct Frame: Sendable {
        let data: Data
        let durationMilliseconds: Int
        let normalizedRMS: Double
    }

    public private(set) var state: DVKVoiceActivityState = .idleListening
    private var preRoll: [Frame] = []
    private var preRollDurationMilliseconds = 0
    private var candidate: [Frame] = []
    private var candidateVoicedMilliseconds = 0
    private var candidateSilenceMilliseconds = 0
    private var utteranceDurationMilliseconds = 0
    private var utteranceVoicedMilliseconds = 0
    private var endingSilenceMilliseconds = 0

    /// Creates a detector using the realtime defaults unless a custom configuration is supplied.
    public init(configuration: DVKVoiceActivityConfiguration = .realtimeDefault) {
        self.configuration = configuration
    }

    /// Processes one PCM16 frame and returns state plus generated actions.
    public mutating func process(_ data: Data, mode: DVKVoiceActivityMode) -> DVKVoiceActivityAnalysis {
        let frame = Frame(
            data: data,
            durationMilliseconds: frameDurationMilliseconds(data),
            normalizedRMS: normalizedRMS(data)
        )
        guard frame.durationMilliseconds > 0 else {
            return DVKVoiceActivityAnalysis(
                state: state,
                normalizedRMS: 0,
                energyBand: "silent",
                actions: []
            )
        }

        let threshold = mode == .bargeIn
            ? configuration.bargeInRMSThreshold
            : configuration.speechRMSThreshold
        let minimumSpeech = mode == .bargeIn
            ? configuration.bargeInMinimumSpeechMilliseconds
            : configuration.minimumSpeechMilliseconds
        let voiced = frame.normalizedRMS >= threshold
        var actions: [DVKVoiceActivityAction] = []

        switch state {
        case .idleListening:
            appendPreRoll(frame)
            if voiced {
                candidate = preRoll
                candidateVoicedMilliseconds = frame.durationMilliseconds
                candidateSilenceMilliseconds = 0
                state = .speechDetected
            }

        case .speechDetected:
            candidate.append(frame)
            if voiced {
                candidateVoicedMilliseconds += frame.durationMilliseconds
                candidateSilenceMilliseconds = 0
            } else {
                candidateSilenceMilliseconds += frame.durationMilliseconds
            }

            if candidateVoicedMilliseconds >= minimumSpeech {
                utteranceDurationMilliseconds = candidate.reduce(0) {
                    $0 + $1.durationMilliseconds
                }
                utteranceVoicedMilliseconds = candidateVoicedMilliseconds
                endingSilenceMilliseconds = candidateSilenceMilliseconds
                actions.append(.speechStarted(
                    frames: candidate.map(\.data),
                    bargeIn: mode == .bargeIn
                ))
                candidate.removeAll(keepingCapacity: false)
                preRoll.removeAll(keepingCapacity: false)
                preRollDurationMilliseconds = 0
                state = .sendingSpeech
            } else if candidateSilenceMilliseconds >= configuration.candidateAbortSilenceMilliseconds {
                actions.append(.rejectedNoise)
                restoreCandidateTailToPreRoll()
                resetCandidate()
                state = .idleListening
            }

        case .sendingSpeech:
            actions.append(.audio(frame.data))
            utteranceDurationMilliseconds += frame.durationMilliseconds
            if voiced {
                utteranceVoicedMilliseconds += frame.durationMilliseconds
                endingSilenceMilliseconds = 0
            } else {
                endingSilenceMilliseconds += frame.durationMilliseconds
            }

            if utteranceDurationMilliseconds >= configuration.maximumUtteranceMilliseconds {
                actions.append(.commit(
                    reason: .maximumDuration,
                    speechDurationMilliseconds: utteranceVoicedMilliseconds,
                    endingSilenceMilliseconds: endingSilenceMilliseconds
                ))
                state = .endpointing
            } else if endingSilenceMilliseconds >= configuration.endSilenceMilliseconds {
                actions.append(.commit(
                    reason: .endSilence,
                    speechDurationMilliseconds: utteranceVoicedMilliseconds,
                    endingSilenceMilliseconds: endingSilenceMilliseconds
                ))
                state = .endpointing
            }

        case .endpointing:
            break
        }

        return DVKVoiceActivityAnalysis(
            state: state,
            normalizedRMS: frame.normalizedRMS,
            energyBand: energyBand(frame.normalizedRMS, threshold: threshold),
            actions: actions
        )
    }

    /// Resets the detector to idle listening after an utterance completes.
    public mutating func resetForListening() {
        resetAll(state: .idleListening)
    }

    /// Clears all buffered audio and suspends the current candidate or utterance.
    public mutating func suspend() {
        resetAll(state: .idleListening)
    }

    private mutating func appendPreRoll(_ frame: Frame) {
        preRoll.append(frame)
        preRollDurationMilliseconds += frame.durationMilliseconds
        while preRollDurationMilliseconds > configuration.preRollMilliseconds,
              let first = preRoll.first {
            preRoll.removeFirst()
            preRollDurationMilliseconds -= first.durationMilliseconds
        }
    }

    private mutating func restoreCandidateTailToPreRoll() {
        preRoll.removeAll(keepingCapacity: false)
        preRollDurationMilliseconds = 0
        for frame in candidate.reversed() {
            guard preRollDurationMilliseconds < configuration.preRollMilliseconds else { break }
            preRoll.insert(frame, at: 0)
            preRollDurationMilliseconds += frame.durationMilliseconds
        }
    }

    private mutating func resetCandidate() {
        candidate.removeAll(keepingCapacity: false)
        candidateVoicedMilliseconds = 0
        candidateSilenceMilliseconds = 0
    }

    private mutating func resetAll(state target: DVKVoiceActivityState) {
        state = target
        preRoll.removeAll(keepingCapacity: false)
        preRollDurationMilliseconds = 0
        resetCandidate()
        utteranceDurationMilliseconds = 0
        utteranceVoicedMilliseconds = 0
        endingSilenceMilliseconds = 0
    }

    private func frameDurationMilliseconds(_ data: Data) -> Int {
        guard configuration.sampleRate > 0, configuration.bytesPerSample > 0 else { return 0 }
        let samples = data.count / configuration.bytesPerSample
        return max(0, Int((Double(samples) / Double(configuration.sampleRate) * 1_000).rounded()))
    }

    private func normalizedRMS(_ data: Data) -> Double {
        guard data.count >= 2 else { return 0 }
        var squareSum = 0.0
        var sampleCount = 0
        var index = data.startIndex
        while index < data.endIndex {
            let next = data.index(after: index)
            guard next < data.endIndex else { break }
            let low = UInt16(data[index])
            let high = UInt16(data[next]) << 8
            let sample = Double(Int16(bitPattern: low | high)) / 32_768.0
            squareSum += sample * sample
            sampleCount += 1
            index = data.index(after: next)
        }
        guard sampleCount > 0 else { return 0 }
        return min(1, sqrt(squareSum / Double(sampleCount)))
    }

    private func energyBand(_ rms: Double, threshold: Double) -> String {
        if rms < 0.005 { return "silent" }
        if rms < threshold { return "low" }
        if rms < threshold * 2 { return "speech" }
        return "high"
    }
}
