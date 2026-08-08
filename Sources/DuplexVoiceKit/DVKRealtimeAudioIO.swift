#if os(iOS)
import AVFoundation
import Foundation

/// A privacy-safe snapshot of realtime audio engine capture, playback, and recovery health.
public struct DVKRealtimeAudioIOHealthSnapshot: Sendable, Equatable {
    public let captureEngineRunning: Bool
    public let captureTapInstalled: Bool
    public let captureCallbackCount: Int
    public let lastCaptureCallbackAt: Date?
    public let captureRestartCount: Int
    public let audioEngineStartCount: Int
    public let audioEngineStopCount: Int
    public let playbackStartCount: Int
    public let audioInterruptionCount: Int
    public let engineConfigurationChangeCount: Int
    public let isInterrupted: Bool

    public static let unavailable = DVKRealtimeAudioIOHealthSnapshot(
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
}

private enum DVKRealtimeAudioIOError: Error {
    case invalidInputFormat
    case invalidPlaybackFormat
}

/// A single full-duplex AVAudioEngine owns Voice Processing input and assistant playback.
/// Muting capture removes only the input tap; it does not tear down playback.
public final class DVKRealtimeAudioIO: @unchecked Sendable {
    public var captureGeneration: Int {
        captureStateLock.lock()
        defer { captureStateLock.unlock() }
        return activeCaptureGeneration
    }

    public var healthSnapshot: DVKRealtimeAudioIOHealthSnapshot {
        healthLock.lock()
        defer { healthLock.unlock() }
        return DVKRealtimeAudioIOHealthSnapshot(
            captureEngineRunning: healthEngineRunning,
            captureTapInstalled: healthTapInstalled,
            captureCallbackCount: callbackCount,
            lastCaptureCallbackAt: lastCallbackAt,
            captureRestartCount: restartCount,
            audioEngineStartCount: engineStartCount,
            audioEngineStopCount: engineStopCount,
            playbackStartCount: playbackStartCount,
            audioInterruptionCount: interruptionCount,
            engineConfigurationChangeCount: configurationChangeCount,
            isInterrupted: healthInterrupted
        )
    }

    private let configuration: DVKAudioConfiguration
    private let graphQueue = DispatchQueue(label: "duplexvoicekit.audio.realtime.graph")
    private let handlerLock = NSLock()
    private let captureStateLock = NSLock()
    private let healthLock = NSLock()
    private let notificationCenter: NotificationCenter
    private let playbackFormat: AVAudioFormat

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var graphConfigured = false
    private var captureRequested = false
    private var tapInstalled = false
    private var interrupted = false
    private var rebuilding = false
    private var captureSink: (any DVKAudioCaptureSink)?
    private var amplitudeSink: (any DVKPlaybackAmplitudeSink)?
    private var activeCaptureGeneration = 0
    private var captureDeliveryEnabled = false
    private var currentResponseID = ""
    private var playbackPending: [Int: Data] = [:]
    private var nextPlaybackIndex = 0
    private var playbackMuted = false
    private var observers: [NSObjectProtocol] = []

    private var callbackCount = 0
    private var lastCallbackAt: Date?
    private var restartCount = 0
    private var engineStartCount = 0
    private var engineStopCount = 0
    private var playbackStartCount = 0
    private var interruptionCount = 0
    private var configurationChangeCount = 0
    private var healthEngineRunning = false
    private var healthTapInstalled = false
    private var healthInterrupted = false

    public init(
        configuration: DVKAudioConfiguration = .realtimeVoice,
        captureSink: (any DVKAudioCaptureSink)? = nil,
        playbackAmplitudeSink: (any DVKPlaybackAmplitudeSink)? = nil,
        notificationCenter: NotificationCenter = .default
    ) throws {
        guard let playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: configuration.playbackSampleRate,
            channels: AVAudioChannelCount(configuration.channels),
            interleaved: true
        ) else {
            throw DVKRealtimeAudioIOError.invalidPlaybackFormat
        }
        self.configuration = configuration
        self.captureSink = captureSink
        amplitudeSink = playbackAmplitudeSink
        self.notificationCenter = notificationCenter
        self.playbackFormat = playbackFormat
        installObservers(notificationCenter: notificationCenter)
    }

    deinit {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
    }

    public func setCaptureSink(_ sink: (any DVKAudioCaptureSink)?) {
        handlerLock.lock()
        captureSink = sink
        handlerLock.unlock()
    }

    public func setPlaybackAmplitudeSink(_ sink: (any DVKPlaybackAmplitudeSink)?) {
        handlerLock.lock()
        amplitudeSink = sink
        handlerLock.unlock()
    }

    public func startCapture() throws {
        try graphQueue.sync {
            captureRequested = true
            do {
                try configureGraphIfNeeded()
                try installInputTapIfNeeded()
                try startEngineIfNeeded()
            } catch {
                captureRequested = false
                removeInputTapIfNeeded()
                throw error
            }
        }
    }

    /// Stops microphone delivery only. The shared engine and playback remain available.
    public func stopCapture() {
        graphQueue.sync {
            captureRequested = false
            removeInputTapIfNeeded()
        }
        clearCapturePending()
    }

    public func enqueuePlayback(_ data: Data, responseID: String, chunkIndex: Int) {
        graphQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureGraphIfNeeded()
                try self.startEngineIfNeeded()
                if self.currentResponseID != responseID {
                    self.player.stop()
                    self.playbackPending.removeAll(keepingCapacity: false)
                    self.currentResponseID = responseID
                    self.nextPlaybackIndex = 0
                }
                self.playbackPending[chunkIndex] = data
                self.scheduleReadyPlaybackChunks()
            } catch {
                self.updateEngineHealth()
            }
        }
    }

    public func cancelPlayback(responseID: String? = nil) {
        graphQueue.async { [weak self] in
            guard let self else { return }
            guard responseID == nil || responseID == self.currentResponseID else { return }
            self.player.stop()
            self.playbackPending.removeAll(keepingCapacity: false)
            self.currentResponseID = ""
            self.nextPlaybackIndex = 0
            self.publishPlaybackAmplitude(0)
        }
    }

    /// Mutes only local assistant playback. Capture and the realtime session continue normally.
    public func setPlaybackMuted(_ muted: Bool) {
        graphQueue.async { [weak self] in
            guard let self else { return }
            self.playbackMuted = muted
            self.player.volume = muted ? 0 : 1
        }
    }

    public func recoverCapture() throws {
        try graphQueue.sync {
            guard captureRequested, !interrupted else { return }
            try restartGraph(startAfterRestart: true)
            incrementRestartCount()
        }
    }

    public func shutdown() {
        graphQueue.sync {
            captureRequested = false
            removeInputTapIfNeeded()
            player.stop()
            playbackPending.removeAll(keepingCapacity: false)
            currentResponseID = ""
            nextPlaybackIndex = 0
            if engine.isRunning {
                engine.stop()
                incrementEngineStopCount()
            }
            updateEngineHealth()
        }
        clearCapturePending()
        publishPlaybackAmplitude(0)
    }

    private func configureGraphIfNeeded() throws {
        guard !graphConfigured else { return }
        let input = engine.inputNode
        if !input.isVoiceProcessingEnabled {
            try input.setVoiceProcessingEnabled(true)
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        player.volume = playbackMuted ? 0 : 1
        engine.prepare()
        graphConfigured = true
        updateEngineHealth()
    }

    private func installInputTapIfNeeded() throws {
        guard captureRequested, !tapInstalled else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw DVKRealtimeAudioIOError.invalidInputFormat
        }
        let generation = beginCaptureGeneration()
        input.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(configuration.captureBufferFrames),
            format: format
        ) { [weak self] buffer, _ in
            self?.handleCaptureBuffer(buffer, generation: generation)
        }
        tapInstalled = true
        updateEngineHealth()
    }

    private func removeInputTapIfNeeded() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        endCaptureGeneration()
        tapInstalled = false
        updateEngineHealth()
    }

    private func startEngineIfNeeded() throws {
        guard !interrupted else { return }
        if captureRequested {
            try installInputTapIfNeeded()
        }
        guard !engine.isRunning else {
            updateEngineHealth()
            return
        }
        engine.prepare()
        try engine.start()
        incrementEngineStartCount()
        updateEngineHealth()
    }

    private func handleCaptureBuffer(_ buffer: AVAudioPCMBuffer, generation: Int) {
        guard isCaptureGenerationActive(generation) else { return }
        let capturedAt = Date()
        guard let packet = copyCapturedPacket(
            buffer,
            generation: generation,
            capturedAt: capturedAt
        ) else { return }
        recordCaptureCallback(at: capturedAt)
        guard handlerLock.try() else { return }
        let sink = captureSink
        handlerLock.unlock()
        guard isCaptureGenerationActive(generation) else { return }
        _ = sink?.offer(packet)
    }

    private func copyCapturedPacket(
        _ buffer: AVAudioPCMBuffer,
        generation: Int,
        capturedAt: Date
    ) -> DVKCapturedAudioPacket? {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return nil }
        if let source = buffer.floatChannelData {
            let isInterleaved = buffer.format.isInterleaved
            var data = Data(capacity: frames * channels * MemoryLayout<Float>.size)
            if isInterleaved {
                data.append(contentsOf: UnsafeRawBufferPointer(
                    start: UnsafeRawPointer(source[0]),
                    count: frames * channels * MemoryLayout<Float>.size
                ))
            } else {
                for channel in 0..<channels {
                    data.append(contentsOf: UnsafeRawBufferPointer(
                        start: UnsafeRawPointer(source[channel]),
                        count: frames * MemoryLayout<Float>.size
                    ))
                }
            }
            return DVKCapturedAudioPacket(
                data: data,
                sampleRate: Int(buffer.format.sampleRate),
                channels: channels,
                frameCount: frames,
                format: isInterleaved ? .float32Interleaved : .float32Planar,
                captureGeneration: generation,
                capturedAt: capturedAt
            )
        }
        if let source = buffer.int16ChannelData {
            let isInterleaved = buffer.format.isInterleaved
            var data = Data(capacity: frames * channels * MemoryLayout<Int16>.size)
            if isInterleaved {
                data.append(contentsOf: UnsafeRawBufferPointer(
                    start: UnsafeRawPointer(source[0]),
                    count: frames * channels * MemoryLayout<Int16>.size
                ))
            } else {
                for channel in 0..<channels {
                    data.append(contentsOf: UnsafeRawBufferPointer(
                        start: UnsafeRawPointer(source[channel]),
                        count: frames * MemoryLayout<Int16>.size
                    ))
                }
            }
            return DVKCapturedAudioPacket(
                data: data,
                sampleRate: Int(buffer.format.sampleRate),
                channels: channels,
                frameCount: frames,
                format: isInterleaved ? .int16Interleaved : .int16Planar,
                captureGeneration: generation,
                capturedAt: capturedAt
            )
        }
        return nil
    }

    private func scheduleReadyPlaybackChunks() {
        while let data = playbackPending.removeValue(forKey: nextPlaybackIndex) {
            let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: playbackFormat,
                frameCapacity: frameCount
            ), let channel = buffer.int16ChannelData else { return }
            buffer.frameLength = frameCount
            data.copyBytes(
                to: UnsafeMutableBufferPointer(start: channel[0], count: Int(frameCount))
            )
            player.scheduleBuffer(buffer)
            nextPlaybackIndex += 1
            publishPlaybackAmplitude(normalizedAmplitude(data))
        }
        if !player.isPlaying, !currentResponseID.isEmpty {
            player.play()
            incrementPlaybackStartCount()
        }
    }

    private func restartGraph(startAfterRestart: Bool) throws {
        guard !rebuilding else { return }
        rebuilding = true
        defer { rebuilding = false }

        removeInputTapIfNeeded()
        clearCapturePending()
        player.stop()
        if engine.isRunning {
            engine.stop()
            incrementEngineStopCount()
        }
        engine.reset()
        if captureRequested {
            try installInputTapIfNeeded()
        }
        if startAfterRestart {
            try startEngineIfNeeded()
        }
        updateEngineHealth()
    }

    private func rebuildGraph(startAfterRebuild: Bool) throws {
        guard !rebuilding else { return }
        rebuilding = true
        defer { rebuilding = false }

        removeInputTapIfNeeded()
        clearCapturePending()
        player.stop()
        if engine.isRunning {
            engine.stop()
            incrementEngineStopCount()
        }
        engine.reset()
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        graphConfigured = false
        try configureGraphIfNeeded()
        if captureRequested {
            try installInputTapIfNeeded()
        }
        if startAfterRebuild {
            try startEngineIfNeeded()
        }
        updateEngineHealth()
    }

    private func installObservers(notificationCenter: NotificationCenter) {
        observers.append(notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        })
        observers.append(notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] _ in
            self?.graphQueue.async { self?.ensureHealthyGraphAfterSystemChange() }
        })
        observers.append(notificationCenter.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] _ in
            self?.graphQueue.async {
                guard let self else { return }
                try? AVAudioSession.sharedInstance().setActive(true)
                if self.captureRequested,
                   (try? self.rebuildGraph(startAfterRebuild: true)) != nil {
                    self.incrementRestartCount()
                } else if !self.captureRequested {
                    try? self.rebuildGraph(startAfterRebuild: false)
                }
            }
        })
        observers.append(notificationCenter.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.graphQueue.async {
                guard let self else { return }
                if let changedEngine = notification.object as? AVAudioEngine,
                   changedEngine !== self.engine {
                    return
                }
                self.incrementConfigurationChangeCount()
                self.ensureHealthyGraphAfterSystemChange()
            }
        })
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        graphQueue.async { [weak self] in
            guard let self else { return }
            switch type {
            case .began:
                self.interrupted = true
                self.incrementInterruptionCount()
                self.player.pause()
                self.removeInputTapIfNeeded()
                self.clearCapturePending()
                self.engine.pause()
                self.updateEngineHealth()
            case .ended:
                self.interrupted = false
                try? AVAudioSession.sharedInstance().setActive(true)
                do {
                    try self.configureGraphIfNeeded()
                    if self.captureRequested {
                        try self.installInputTapIfNeeded()
                    }
                    try self.startEngineIfNeeded()
                    if !self.currentResponseID.isEmpty, !self.player.isPlaying {
                        self.player.play()
                        self.incrementPlaybackStartCount()
                    }
                } catch {
                    if self.captureRequested,
                       (try? self.restartGraph(startAfterRestart: true)) != nil {
                        self.incrementRestartCount()
                    }
                }
                self.updateEngineHealth()
            @unknown default:
                break
            }
        }
    }

    private func ensureHealthyGraphAfterSystemChange() {
        guard captureRequested, !interrupted else {
            updateEngineHealth()
            return
        }
        if !engine.isRunning || !tapInstalled {
            if (try? restartGraph(startAfterRestart: true)) != nil {
                incrementRestartCount()
            }
        } else {
            updateEngineHealth()
        }
    }

    private func clearCapturePending() {}

    private func beginCaptureGeneration() -> Int {
        captureStateLock.lock()
        activeCaptureGeneration &+= 1
        captureDeliveryEnabled = true
        let generation = activeCaptureGeneration
        captureStateLock.unlock()
        return generation
    }

    private func endCaptureGeneration() {
        captureStateLock.lock()
        captureDeliveryEnabled = false
        activeCaptureGeneration &+= 1
        captureStateLock.unlock()
    }

    private func isCaptureGenerationActive(_ generation: Int) -> Bool {
        guard captureStateLock.try() else { return false }
        defer { captureStateLock.unlock() }
        return captureDeliveryEnabled && activeCaptureGeneration == generation
    }

    private func recordCaptureCallback(at capturedAt: Date) {
        guard healthLock.try() else { return }
        callbackCount += 1
        lastCallbackAt = capturedAt
        healthLock.unlock()
    }

    private func publishPlaybackAmplitude(_ amplitude: Float) {
        handlerLock.lock()
        let sink = amplitudeSink
        handlerLock.unlock()
        sink?.playbackAmplitudeDidChange(amplitude)
    }

    private func normalizedAmplitude(_ data: Data) -> Float {
        guard data.count >= MemoryLayout<Int16>.size else { return 0 }
        return data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            guard !samples.isEmpty else { return 0 }
            var squareSum: Double = 0
            for sample in samples {
                let normalized = Double(sample) / Double(Int16.max)
                squareSum += normalized * normalized
            }
            return Float(min(1, sqrt(squareSum / Double(samples.count))))
        }
    }

    private func updateEngineHealth() {
        healthLock.lock()
        healthEngineRunning = engine.isRunning && !interrupted
        healthTapInstalled = tapInstalled
        healthInterrupted = interrupted
        healthLock.unlock()
    }

    private func incrementRestartCount() {
        healthLock.lock()
        restartCount += 1
        healthLock.unlock()
    }

    private func incrementEngineStartCount() {
        healthLock.lock()
        engineStartCount += 1
        healthLock.unlock()
    }

    private func incrementEngineStopCount() {
        healthLock.lock()
        engineStopCount += 1
        healthLock.unlock()
    }

    private func incrementPlaybackStartCount() {
        healthLock.lock()
        playbackStartCount += 1
        healthLock.unlock()
    }

    private func incrementInterruptionCount() {
        healthLock.lock()
        interruptionCount += 1
        healthLock.unlock()
    }

    private func incrementConfigurationChangeCount() {
        healthLock.lock()
        configurationChangeCount += 1
        healthLock.unlock()
    }
}
#endif
