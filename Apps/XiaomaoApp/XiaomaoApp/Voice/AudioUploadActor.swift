import DuplexVoiceKit
import Foundation

typealias CapturedAudioSampleFormat = DVKCapturedAudioSampleFormat
typealias CapturedAudioPacket = DVKCapturedAudioPacket
typealias AudioUploadIntent = DVKAudioUploadIntent
typealias AudioUploadNotification = DVKAudioUploadNotification
typealias AudioUploadActorError = DVKAudioUploadError
typealias AudioUploadDiagnosticsSnapshot = DVKAudioUploadDiagnosticsSnapshot

/// Compatibility view used by existing App diagnostics and tests.
/// The snapshot is copied from DVK and cannot mutate the pipeline's internal state.
final class AudioUploadDiagnosticsStore: @unchecked Sendable {
    private let compatibilityLock = NSLock()
    private let snapshotProvider: @Sendable () -> AudioUploadDiagnosticsSnapshot

    init(snapshotProvider: @escaping @Sendable () -> AudioUploadDiagnosticsSnapshot) {
        self.snapshotProvider = snapshotProvider
    }

    var snapshot: AudioUploadDiagnosticsSnapshot {
        snapshotProvider()
    }

    func update(_ body: (inout AudioUploadDiagnosticsSnapshot) -> Void) {
        compatibilityLock.lock()
        var copy = snapshotProvider()
        body(&copy)
        compatibilityLock.unlock()
    }
}

/// Thin App compatibility layer over the public DVK upload pipeline.
/// Queueing, drain, PCM buffering, generations, backpressure, and chunk allocation live only in DVK.
final class AudioUploadActor: @unchecked Sendable {
    typealias FrameProcessor = @Sendable (Data) async -> [AudioUploadIntent]
    typealias NotificationHandler = @Sendable (AudioUploadNotification) async -> Void

    let diagnostics: AudioUploadDiagnosticsStore
    private let pipeline: DVKAudioUploadPipeline

    init(
        socket: any VoiceWebSocketClient,
        queueCapacity: Int = 100,
        outboundAudioBatchBytes: Int = 640,
        allowsContinuousInput: Bool = false,
        outboundQueueCapacity: Int? = nil
    ) {
        let pipeline = DVKAudioUploadPipeline(
            outboundTransport: XiaomaoDVKOutboundTransport(socket: socket),
            queueCapacity: queueCapacity,
            outboundAudioBatchBytes: outboundAudioBatchBytes,
            allowsContinuousInput: allowsContinuousInput,
            outboundQueueCapacity: outboundQueueCapacity
        )
        self.pipeline = pipeline
        diagnostics = AudioUploadDiagnosticsStore {
            pipeline.diagnosticsSnapshot
        }
    }

    @discardableResult
    func offer(_ packet: CapturedAudioPacket) -> Bool {
        pipeline.offer(packet)
    }

    func configure(
        processor: @escaping FrameProcessor,
        notificationHandler: @escaping NotificationHandler
    ) async {
        await pipeline.configure(
            processor: processor,
            notificationHandler: notificationHandler
        )
    }

    func openConnection(
        sessionID: String,
        traceID: String,
        resumeFrom lastReceivedServerSequence: Int? = nil
    ) async throws {
        try await pipeline.openConnection(
            sessionID: sessionID,
            traceID: traceID,
            sessionStartPayload: ["route": .string(VoiceRoute.b.rawValue)],
            resumeFrom: lastReceivedServerSequence
        )
    }

    func markReady() async {
        await pipeline.markReady()
    }

    func activateCaptureGeneration(_ generation: Int) async {
        await pipeline.activateCaptureGeneration(generation)
    }

    func pauseCapture() async {
        await pipeline.pauseCapture()
    }

    func commit() async throws {
        try await pipeline.commit()
    }

    func interrupt(responseID: String) async throws {
        try await pipeline.interrupt(responseID: responseID)
    }

    func setMuted(_ muted: Bool) async throws {
        try await pipeline.setMuted(muted)
    }

    func sendClientState(_ payload: [String: JSONValue]) async throws {
        try await pipeline.sendClientState(payload.mapValues(DVKJSONValue.init(appValue:)))
    }

    func ping() async throws {
        try await pipeline.ping()
    }

    func endSession() async throws {
        try await pipeline.endSession()
    }

    func abortConnection() async {
        await pipeline.abortConnection()
    }
}
