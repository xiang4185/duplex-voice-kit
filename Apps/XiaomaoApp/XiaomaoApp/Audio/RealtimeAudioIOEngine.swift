import DuplexVoiceKit
import Foundation

struct RealtimeAudioIOHealthSnapshot: Sendable, Equatable {
    let captureEngineRunning: Bool
    let captureTapInstalled: Bool
    let captureCallbackCount: Int
    let lastCaptureCallbackAt: Date?
    let captureRestartCount: Int
    let audioEngineStartCount: Int
    let audioEngineStopCount: Int
    let playbackStartCount: Int
    let audioInterruptionCount: Int
    let engineConfigurationChangeCount: Int
    let isInterrupted: Bool

    static let unavailable = RealtimeAudioIOHealthSnapshot(
        captureEngineRunning: false,
        captureTapInstalled: false,
        captureCallbackCount: 0,
        lastCaptureCallbackAt: nil,
        captureRestartCount: 0,
        audioEngineStartCount: 0,
        audioEngineStopCount: 0,
        playbackStartCount: 0,
        audioInterruptionCount: 0,
        engineConfigurationChangeCount: 0,
        isInterrupted: false
    )

    init(
        captureEngineRunning: Bool,
        captureTapInstalled: Bool,
        captureCallbackCount: Int,
        lastCaptureCallbackAt: Date?,
        captureRestartCount: Int,
        audioEngineStartCount: Int,
        audioEngineStopCount: Int,
        playbackStartCount: Int,
        audioInterruptionCount: Int,
        engineConfigurationChangeCount: Int,
        isInterrupted: Bool
    ) {
        self.captureEngineRunning = captureEngineRunning
        self.captureTapInstalled = captureTapInstalled
        self.captureCallbackCount = captureCallbackCount
        self.lastCaptureCallbackAt = lastCaptureCallbackAt
        self.captureRestartCount = captureRestartCount
        self.audioEngineStartCount = audioEngineStartCount
        self.audioEngineStopCount = audioEngineStopCount
        self.playbackStartCount = playbackStartCount
        self.audioInterruptionCount = audioInterruptionCount
        self.engineConfigurationChangeCount = engineConfigurationChangeCount
        self.isInterrupted = isInterrupted
    }

    init(dvk snapshot: DVKRealtimeAudioIOHealthSnapshot) {
        self.init(
            captureEngineRunning: snapshot.captureEngineRunning,
            captureTapInstalled: snapshot.captureTapInstalled,
            captureCallbackCount: snapshot.captureCallbackCount,
            lastCaptureCallbackAt: snapshot.lastCaptureCallbackAt,
            captureRestartCount: snapshot.captureRestartCount,
            audioEngineStartCount: snapshot.audioEngineStartCount,
            audioEngineStopCount: snapshot.audioEngineStopCount,
            playbackStartCount: snapshot.playbackStartCount,
            audioInterruptionCount: snapshot.audioInterruptionCount,
            engineConfigurationChangeCount: snapshot.engineConfigurationChangeCount,
            isInterrupted: snapshot.isInterrupted
        )
    }
}

protocol RealtimeAudioIOHealthReporting: AnyObject {
    var healthSnapshot: RealtimeAudioIOHealthSnapshot { get }
    func recoverCapture() throws
    func shutdownAudioIO()
}

/// App-facing compatibility adapter. DVK owns the only Route B realtime audio graph,
/// capture/playback nodes, interruption handling, and recovery observers.
final class RealtimeAudioIOEngine: AudioCapturing, AudioPlaying, RealtimeAudioIOHealthReporting {
    private let captureBridge: XiaomaoDVKCaptureBridge
    private let core: DVKRealtimeAudioIO?

    var onPacket: ((CapturedAudioPacket) -> Void)? {
        get { captureBridge.handler }
        set { captureBridge.handler = newValue }
    }

    var captureGeneration: Int {
        core?.captureGeneration ?? 0
    }

    var healthSnapshot: RealtimeAudioIOHealthSnapshot {
        guard let core else { return .unavailable }
        return RealtimeAudioIOHealthSnapshot(dvk: core.healthSnapshot)
    }

    init(notificationCenter: NotificationCenter = .default) {
        let bridge = XiaomaoDVKCaptureBridge()
        captureBridge = bridge
        core = try? DVKRealtimeAudioIO(
            configuration: .realtimeVoice,
            captureSink: bridge,
            notificationCenter: notificationCenter
        )
    }

    func start() throws {
        guard let core else {
            throw AppError.audio("dvk_audio_initialization_failed")
        }
        try core.startCapture()
    }

    func stop() {
        core?.stopCapture()
    }

    func enqueue(_ data: Data, responseID: String, chunkIndex: Int) {
        core?.enqueuePlayback(data, responseID: responseID, chunkIndex: chunkIndex)
    }

    func cancel(responseID: String?) {
        core?.cancelPlayback(responseID: responseID)
    }

    func setMuted(_ muted: Bool) {
        core?.setPlaybackMuted(muted)
    }

    func recoverCapture() throws {
        guard let core else {
            throw AppError.audio("dvk_audio_initialization_failed")
        }
        try core.recoverCapture()
    }

    func shutdownAudioIO() {
        core?.shutdown()
    }
}

private final class XiaomaoDVKCaptureBridge: @unchecked Sendable, DVKAudioCaptureSink {
    private let lock = NSLock()
    private var packetHandler: ((CapturedAudioPacket) -> Void)?

    var handler: ((CapturedAudioPacket) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return packetHandler
        }
        set {
            lock.lock()
            packetHandler = newValue
            lock.unlock()
        }
    }

    @discardableResult
    func offer(_ packet: DVKCapturedAudioPacket) -> Bool {
        guard lock.try() else { return false }
        let handler = packetHandler
        lock.unlock()
        handler?(packet)
        return true
    }
}
