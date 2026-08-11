import Foundation

/// Keeps PCM/VAD work off the SwiftUI/MainActor hot path.
///
/// The upload pipeline calls this synchronously from its own actor. UI-facing VAD
/// values are sampled at a low rate while speech/commit events are still emitted
/// immediately so endpointing semantics remain unchanged.
final class RealtimeVoiceProcessor: @unchecked Sendable {
    enum Event: Sendable {
        case none
        case rejectedNoise
        case speechStarted(bargeIn: Bool)
        case commit(speechDuration: Int, endingSilence: Int)
    }

    struct UISnapshot: Sendable {
        let state: VoiceActivityState
        let normalizedRMS: Double
        let energyBand: String
    }

    struct Result: Sendable {
        var intents: [AudioUploadIntent]
        var bargeInFrames: [Data]?
        var event: Event
        var uiSnapshot: UISnapshot?

        var needsMainActorUpdate: Bool {
            uiSnapshot != nil || event.isMeaningful
        }
    }

    let configuration: VoiceActivityConfiguration

    private let lock = NSLock()
    private var detector: VoiceActivityDetector
    private var lastUIPublishAt: TimeInterval = 0
    private var lastPublishedState: VoiceActivityState = .idleListening
    private var lastPublishedEnergyBand = "silent"
    private var sessionState: VoiceSessionState = .idle
    private var responseID = ""

    init(configuration: VoiceActivityConfiguration) {
        self.configuration = configuration
        detector = VoiceActivityDetector(configuration: configuration)
    }

    func updateSession(state: VoiceSessionState, responseID: String) {
        lock.lock()
        sessionState = state
        self.responseID = responseID
        lock.unlock()
    }

    func process(_ data: Data) -> Result {
        lock.lock()
        defer { lock.unlock() }

        let mode: VoiceActivityMode
        if sessionState == .speaking, !responseID.isEmpty {
            mode = .bargeIn
        } else if sessionState == .ready || sessionState == .listening {
            mode = .listening
        } else {
            return Result(intents: [], bargeInFrames: nil, event: .none, uiSnapshot: nil)
        }

        // Once endpointing has fired, do not keep accepting post-commit microphone
        // frames while MainActor catches up to the `.processing` state transition.
        if detector.state == .endpointing {
            return Result(intents: [], bargeInFrames: nil, event: .none, uiSnapshot: nil)
        }

        let analysis = detector.process(data, mode: mode)
        var intents: [AudioUploadIntent] = mode == .listening ? [.audio(data)] : []
        var bargeInFrames: [Data]?
        var event: Event = .none

        for action in analysis.actions {
            switch action {
            case .rejectedNoise:
                event = .rejectedNoise

            case .speechStarted(let frames, let bargeIn):
                event = .speechStarted(bargeIn: bargeIn)
                if bargeIn {
                    bargeInFrames = frames
                } else {
                    intents.append(.beginUtterance(interruptResponseID: nil))
                }

            case .audio(let frame):
                if mode == .bargeIn {
                    intents.append(.audio(frame))
                }

            case .commit(_, let speechDuration, let endingSilence):
                event = .commit(
                    speechDuration: speechDuration,
                    endingSilence: endingSilence
                )
                intents.append(.commit)
            }
        }

        let now = ProcessInfo.processInfo.systemUptime
        let stateChanged = analysis.state != lastPublishedState
        let energyChanged = analysis.energyBand != lastPublishedEnergyBand
        let shouldPublishUI = stateChanged
            || energyChanged
            || event.isMeaningful
            || (now - lastUIPublishAt) >= 0.10

        let uiSnapshot: UISnapshot?
        if shouldPublishUI {
            lastUIPublishAt = now
            lastPublishedState = analysis.state
            lastPublishedEnergyBand = analysis.energyBand
            uiSnapshot = UISnapshot(
                state: analysis.state,
                normalizedRMS: analysis.normalizedRMS,
                energyBand: analysis.energyBand
            )
        } else {
            uiSnapshot = nil
        }

        return Result(
            intents: intents,
            bargeInFrames: bargeInFrames,
            event: event,
            uiSnapshot: uiSnapshot
        )
    }

    func resetForListening() {
        lock.lock()
        detector.resetForListening()
        lastPublishedState = .idleListening
        lastPublishedEnergyBand = "silent"
        lastUIPublishAt = 0
        lock.unlock()
    }

    func suspend() {
        lock.lock()
        detector.suspend()
        lastPublishedState = .idleListening
        lastPublishedEnergyBand = "silent"
        lastUIPublishAt = 0
        lock.unlock()
    }
}

private extension RealtimeVoiceProcessor.Event {
    var isMeaningful: Bool {
        if case .none = self { return false }
        return true
    }
}
