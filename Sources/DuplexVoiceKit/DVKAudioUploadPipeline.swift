import Foundation

/// A minimal public facade over DuplexVoiceKit's serial audio upload actor.
///
/// The facade exposes host integration operations while keeping the bounded queue,
/// drain task, generation bookkeeping, PCM buffering, locks, and continuations internal.
public final class DVKAudioUploadPipeline: @unchecked Sendable, DVKAudioCaptureSink {
    /// Processes one normalized 20 ms PCM16 frame into upload intents.
    public typealias FrameProcessor = @Sendable (Data) async -> [DVKAudioUploadIntent]

    /// Receives upload notifications without access to mutable internal state.
    public typealias NotificationHandler = @Sendable (DVKAudioUploadNotification) async -> Void

    private let actor: DVKAudioUploadActor

    /// Creates a serial upload pipeline that sends through the host application's existing transport.
    public init(
        outboundTransport: any DVKOutboundTransport,
        queueCapacity: Int = DVKAudioConfiguration.realtimeVoice.uploadQueueCapacity,
        outboundAudioBatchBytes: Int = 640,
        allowsContinuousInput: Bool = false
    ) {
        actor = DVKAudioUploadActor(
            transport: outboundTransport,
            queueCapacity: queueCapacity,
            outboundBatchBytes: outboundAudioBatchBytes,
            allowsContinuousInput: allowsContinuousInput
        )
    }

    /// Offers one captured packet without blocking the realtime capture callback.
    @discardableResult
    public func offer(_ packet: DVKCapturedAudioPacket) -> Bool {
        actor.offer(packet)
    }

    /// Installs the frame processor and notification callback and starts the single drain task.
    public func configure(
        processor: @escaping FrameProcessor,
        notificationHandler: @escaping NotificationHandler
    ) async {
        await actor.configure(
            processor: processor,
            notificationHandler: notificationHandler
        )
    }

    /// Opens a fresh protocol generation or resumes from a known server sequence.
    public func openConnection(
        sessionID: String,
        traceID: String,
        sessionStartPayload: [String: DVKJSONValue] = [:],
        resumeFrom lastReceivedServerSequence: Int? = nil
    ) async throws {
        try await actor.openConnection(
            sessionID: sessionID,
            traceID: traceID,
            sessionStartPayload: sessionStartPayload,
            resumeFrom: lastReceivedServerSequence
        )
    }

    /// Marks the active connection generation ready to accept capture.
    public func markReady() async {
        await actor.markReady()
    }

    /// Activates the host audio engine's current capture generation.
    public func activateCaptureGeneration(_ generation: Int) async {
        await actor.activateCaptureGeneration(generation)
    }

    /// Stops accepting capture and invalidates partial PCM according to the extracted semantics.
    public func pauseCapture() async {
        await actor.pauseCapture()
    }

    /// Commits the current utterance through the serial outbound boundary.
    public func commit() async throws {
        try await actor.commit()
    }

    /// Interrupts the specified active response through the serial outbound boundary.
    public func interrupt(responseID: String) async throws {
        try await actor.interrupt(responseID: responseID)
    }

    /// Sends the host mute or unmute state.
    public func setMuted(_ muted: Bool) async throws {
        try await actor.setMuted(muted)
    }

    /// Sends provider-neutral client state metadata.
    public func sendClientState(_ payload: [String: DVKJSONValue]) async throws {
        try await actor.sendClientState(payload)
    }

    /// Sends a protocol ping.
    public func ping() async throws {
        try await actor.ping()
    }

    /// Ends the active protocol session.
    public func endSession() async throws {
        try await actor.endSession()
    }

    /// Aborts the active generation and rejects pending work from that generation.
    public func abortConnection() async {
        await actor.abortConnection()
    }

    /// Returns a value snapshot that cannot mutate pipeline internals.
    public var diagnosticsSnapshot: DVKAudioUploadDiagnosticsSnapshot {
        actor.diagnostics.snapshot
    }
}
