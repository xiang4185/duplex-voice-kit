import Foundation
import XCTest
import DuplexVoiceKit

final class DVKAudioUploadPipelinePublicTests: XCTestCase {
    func testSendOnlyTransportCanUsePipelineWithContinuousChunkIndices() async throws {
        let transport = PublicRecordingOutboundTransport()
        let processor = PublicStreamingProcessor()
        let pipeline = DVKAudioUploadPipeline(outboundTransport: transport, queueCapacity: 16)
        await pipeline.configure(
            processor: { frame in await processor.process(frame) },
            notificationHandler: { _ in }
        )
        try await openAndActivate(pipeline, generation: 1)

        for _ in 0..<4 {
            XCTAssertTrue(pipeline.offer(.pcm16(frame(), captureGeneration: 1)))
        }
        await transport.waitForAudioCount(4)

        let audio = await transport.messages().filter { $0.type == "audio.append" }
        XCTAssertEqual(audio.compactMap(chunkIndex), [0, 1, 2, 3])
        XCTAssertEqual(pipeline.diagnosticsSnapshot.nextChunkIndex, 4)
        XCTAssertEqual(pipeline.diagnosticsSnapshot.maxActiveDrainTasks, 1)
    }

    func testNewConnectionRestartsChunkIndexAtZero() async throws {
        let transport = PublicRecordingOutboundTransport()
        let pipeline = makeSingleFramePipeline(transport: transport)
        await pipeline.configure(processor: Self.singleFrameProcessor, notificationHandler: { _ in })

        try await openAndActivate(pipeline, sessionID: "one", generation: 1)
        XCTAssertTrue(pipeline.offer(.pcm16(frame(), captureGeneration: 1)))
        await transport.waitForAudioCount(1)

        try await openAndActivate(pipeline, sessionID: "two", generation: 2)
        XCTAssertTrue(pipeline.offer(.pcm16(frame(), captureGeneration: 2)))
        await transport.waitForAudioCount(2)

        let audio = await transport.messages().filter { $0.type == "audio.append" }
        XCTAssertEqual(audio.compactMap(chunkIndex), [0, 0])
    }

    func testCaptureGenerationPromotesAndLowerGenerationDoesNotRollBack() async throws {
        let transport = PublicRecordingOutboundTransport()
        let pipeline = makeSingleFramePipeline(transport: transport)
        await pipeline.configure(processor: Self.singleFrameProcessor, notificationHandler: { _ in })
        try await openAndActivate(pipeline, generation: 1)

        XCTAssertTrue(pipeline.offer(.pcm16(frame(), captureGeneration: 3)))
        await transport.waitForAudioCount(1)
        XCTAssertTrue(pipeline.offer(.pcm16(frame(), captureGeneration: 1)))
        try await pipeline.ping()

        let snapshot = pipeline.diagnosticsSnapshot
        XCTAssertEqual(snapshot.captureGeneration, 3)
        XCTAssertEqual(snapshot.sentAudioChunks, 1)
        XCTAssertEqual(snapshot.droppedStaleGenerationChunks, 1)
    }

    func testGenerationPromotionClearsPartialPCM() async throws {
        let transport = PublicRecordingOutboundTransport()
        let pipeline = makeSingleFramePipeline(transport: transport)
        await pipeline.configure(processor: Self.singleFrameProcessor, notificationHandler: { _ in })
        try await openAndActivate(pipeline, generation: 1)

        XCTAssertTrue(pipeline.offer(.pcm16(Data(repeating: 7, count: 320), captureGeneration: 1)))
        XCTAssertTrue(pipeline.offer(.pcm16(frame(), captureGeneration: 2)))
        await transport.waitForAudioCount(1)

        let audio = await transport.messages().filter { $0.type == "audio.append" }
        XCTAssertEqual(audio.count, 1)
        XCTAssertEqual(pipeline.diagnosticsSnapshot.captureGeneration, 2)
    }

    func testPauseRejectsCaptureUntilExplicitReactivation() async throws {
        let transport = PublicRecordingOutboundTransport()
        let pipeline = makeSingleFramePipeline(transport: transport)
        await pipeline.configure(processor: Self.singleFrameProcessor, notificationHandler: { _ in })
        try await openAndActivate(pipeline, generation: 1)

        await pipeline.pauseCapture()
        XCTAssertTrue(pipeline.offer(.pcm16(frame(), captureGeneration: 1)))
        try await pipeline.ping()
        XCTAssertEqual(pipeline.diagnosticsSnapshot.sentAudioChunks, 0)

        await pipeline.activateCaptureGeneration(2)
        XCTAssertTrue(pipeline.offer(.pcm16(frame(), captureGeneration: 2)))
        await transport.waitForAudioCount(1)
        XCTAssertEqual(pipeline.diagnosticsSnapshot.sentAudioChunks, 1)
    }

    func testInterruptCommitMuteUnmutePingAndEndUseSingleSender() async throws {
        let transport = PublicRecordingOutboundTransport()
        let pipeline = DVKAudioUploadPipeline(outboundTransport: transport)
        await pipeline.configure(processor: { _ in [] }, notificationHandler: { _ in })
        try await pipeline.openConnection(sessionID: "session", traceID: "trace")
        await pipeline.markReady()

        try await pipeline.interrupt(responseID: "response")
        try await pipeline.commit()
        try await pipeline.setMuted(true)
        try await pipeline.setMuted(false)
        try await pipeline.ping()
        try await pipeline.endSession()

        let types = await transport.messages().map(\.type)
        XCTAssertEqual(
            types,
            ["session.start", "interrupt", "audio.commit", "mute", "unmute", "ping", "session.end"]
        )
        let maximumConcurrentSends = await transport.maximumConcurrentSends()
        XCTAssertEqual(maximumConcurrentSends, 1)
    }

    func testAbortRejectsOldGenerationAndSnapshotIsAValueCopy() async throws {
        let transport = PublicRecordingOutboundTransport()
        let pipeline = makeSingleFramePipeline(transport: transport)
        await pipeline.configure(processor: Self.singleFrameProcessor, notificationHandler: { _ in })
        try await openAndActivate(pipeline, generation: 1)
        let beforeAbort = pipeline.diagnosticsSnapshot

        await pipeline.abortConnection()
        XCTAssertTrue(pipeline.offer(.pcm16(frame(), captureGeneration: 1)))
        await waitUntil { pipeline.diagnosticsSnapshot.rejectedAfterCloseCommands > 0 }

        XCTAssertTrue(beforeAbort.active)
        XCTAssertFalse(pipeline.diagnosticsSnapshot.active)
        await XCTAssertThrowsErrorAsync(try await pipeline.ping()) { error in
            XCTAssertEqual(error as? DVKAudioUploadError, .inactiveConnection)
        }
    }

    func testBoundedQueueReportsBackpressureWithoutBlockingOffer() async throws {
        let transport = BlockingAudioOutboundTransport()
        let pipeline = DVKAudioUploadPipeline(outboundTransport: transport, queueCapacity: 1)
        await pipeline.configure(
            processor: { frame in [.beginUtterance(interruptResponseID: nil), .audio(frame)] },
            notificationHandler: { _ in }
        )
        try await openAndActivate(pipeline, generation: 1)

        XCTAssertTrue(pipeline.offer(.pcm16(frame(), captureGeneration: 1)))
        await transport.waitUntilAudioSendStarts()
        let acceptedSecond = pipeline.offer(.pcm16(frame(), captureGeneration: 1))
        let acceptedThird = pipeline.offer(.pcm16(frame(), captureGeneration: 1))

        XCTAssertTrue(acceptedSecond)
        XCTAssertFalse(acceptedThird)
        await transport.releaseAudio()
        await waitUntil {
            let snapshot = pipeline.diagnosticsSnapshot
            return snapshot.inputBackpressureCount == 1 && !snapshot.active
        }
        XCTAssertFalse(pipeline.diagnosticsSnapshot.active)
    }

    func testPublicVADDefaultsMatchExtractedParameters() {
        let configuration = DVKVoiceActivityConfiguration.realtimeDefault
        XCTAssertEqual(configuration.sampleRate, 16_000)
        XCTAssertEqual(configuration.bytesPerSample, 2)
        XCTAssertEqual(configuration.preRollMilliseconds, 240)
        XCTAssertEqual(configuration.minimumSpeechMilliseconds, 200)
        XCTAssertEqual(configuration.bargeInMinimumSpeechMilliseconds, 280)
        XCTAssertEqual(configuration.candidateAbortSilenceMilliseconds, 180)
        XCTAssertEqual(configuration.endSilenceMilliseconds, 700)
        XCTAssertEqual(configuration.maximumUtteranceMilliseconds, 20_000)
        XCTAssertEqual(configuration.speechRMSThreshold, 0.025)
        XCTAssertEqual(configuration.bargeInRMSThreshold, 0.075)

        var detector = DVKVoiceActivityDetector()
        let analysis = detector.process(frame(), mode: .listening)
        XCTAssertEqual(analysis.state, detector.state)
        detector.suspend()
        XCTAssertEqual(detector.state, .idleListening)
    }

    private func makeSingleFramePipeline(
        transport: some DVKOutboundTransport
    ) -> DVKAudioUploadPipeline {
        DVKAudioUploadPipeline(outboundTransport: transport, queueCapacity: 16)
    }

    private func openAndActivate(
        _ pipeline: DVKAudioUploadPipeline,
        sessionID: String = "session",
        generation: Int
    ) async throws {
        try await pipeline.openConnection(sessionID: sessionID, traceID: "trace")
        await pipeline.markReady()
        await pipeline.activateCaptureGeneration(generation)
    }

    private func frame() -> Data {
        Data(repeating: 1, count: 640)
    }

    private func chunkIndex(_ message: DVKOutboundMessage) -> Int? {
        guard case .int(let value)? = message.payload["chunk_index"] else { return nil }
        return value
    }

    private static let singleFrameProcessor: DVKAudioUploadPipeline.FrameProcessor = { frame in
        [.beginUtterance(interruptResponseID: nil), .audio(frame), .commit]
    }

    private func waitUntil(
        attempts: Int = 20_000,
        _ predicate: @escaping @Sendable () -> Bool
    ) async {
        for _ in 0..<attempts {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("condition was not reached")
    }

    private func XCTAssertThrowsErrorAsync(
        _ expression: @autoclosure () async throws -> Void,
        _ handler: (Error) -> Void
    ) async {
        do {
            try await expression()
            XCTFail("expected error")
        } catch {
            handler(error)
        }
    }
}

private actor PublicStreamingProcessor {
    private var started = false

    func process(_ frame: Data) -> [DVKAudioUploadIntent] {
        if !started {
            started = true
            return [.beginUtterance(interruptResponseID: nil), .audio(frame)]
        }
        return [.audio(frame)]
    }
}

private actor PublicRecordingOutboundTransport: DVKOutboundTransport {
    private var recorded: [DVKOutboundMessage] = []
    private var audioWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var concurrentSends = 0
    private var maxConcurrentSends = 0

    func send(_ message: DVKOutboundMessage) async throws {
        concurrentSends += 1
        maxConcurrentSends = max(maxConcurrentSends, concurrentSends)
        recorded.append(message)
        concurrentSends -= 1
        let audioCount = recorded.filter { $0.type == "audio.append" }.count
        let ready = audioWaiters.filter { audioCount >= $0.0 }
        audioWaiters.removeAll { audioCount >= $0.0 }
        ready.forEach { $0.1.resume() }
    }

    func waitForAudioCount(_ count: Int) async {
        if recorded.filter({ $0.type == "audio.append" }).count >= count { return }
        await withCheckedContinuation { continuation in
            audioWaiters.append((count, continuation))
        }
    }

    func messages() -> [DVKOutboundMessage] {
        recorded
    }

    func maximumConcurrentSends() -> Int {
        maxConcurrentSends
    }
}

private actor BlockingAudioOutboundTransport: DVKOutboundTransport {
    private var audioStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func send(_ message: DVKOutboundMessage) async throws {
        guard message.type == "audio.append" else { return }
        audioStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if !released {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
    }

    func waitUntilAudioSendStarts() async {
        if audioStarted { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseAudio() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
