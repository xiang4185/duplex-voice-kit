import Foundation
import XCTest
@testable import DuplexVoiceKit

final class DVKAudioUploadActorTests: XCTestCase {
    func testAudioChunksAreSentSeriallyWithMonotonicChunkIndex() async throws {
        let transport = RecordingTransport()
        let processor = TwoFrameProcessor()
        let uploader = DVKAudioUploadActor(transport: transport, queueCapacity: 16)
        await uploader.configure(
            processor: { frame in await processor.process(frame) },
            notificationHandler: { _ in }
        )
        try await open(uploader)
        await uploader.markReady()
        await uploader.activateCaptureGeneration(1)

        XCTAssertTrue(uploader.offer(.pcm16(frame(), captureGeneration: 1)))
        XCTAssertTrue(uploader.offer(.pcm16(frame(), captureGeneration: 1)))
        await transport.waitForMessageCount(4)

        let messages = await transport.messagesSnapshot()
        let audio = messages.filter { $0.type == "audio.append" }
        XCTAssertEqual(audio.compactMap(chunkIndex), [0, 1])
        XCTAssertEqual(audio.map(\.sequence), audio.map(\.sequence).sorted())
        XCTAssertEqual(uploader.diagnostics.snapshot.maxActiveDrainTasks, 1)
    }

    func testNewConnectionResetsChunkIndexWithoutReplacingDrainTask() async throws {
        let transport = RecordingTransport()
        let processor = SingleFrameProcessor()
        let uploader = DVKAudioUploadActor(transport: transport, queueCapacity: 16)
        await uploader.configure(
            processor: { frame in await processor.process(frame) },
            notificationHandler: { _ in }
        )

        try await open(uploader, sessionID: "session-1")
        await uploader.markReady()
        await uploader.activateCaptureGeneration(1)
        XCTAssertTrue(uploader.offer(.pcm16(frame(), captureGeneration: 1)))
        await transport.waitForMessageCount(3)

        try await open(uploader, sessionID: "session-2")
        await uploader.markReady()
        await uploader.activateCaptureGeneration(2)
        XCTAssertTrue(uploader.offer(.pcm16(frame(), captureGeneration: 2)))
        await transport.waitForMessageCount(6)

        let messages = await transport.messagesSnapshot()
        XCTAssertEqual(
            messages.filter { $0.type == "audio.append" }.compactMap(chunkIndex),
            [0, 0]
        )
        XCTAssertEqual(uploader.diagnostics.snapshot.maxActiveDrainTasks, 1)
    }

    func testStaleCaptureGenerationIsDroppedAndPartialPCMIsCleared() async throws {
        let transport = RecordingTransport()
        let processor = SingleFrameProcessor()
        let uploader = DVKAudioUploadActor(transport: transport, queueCapacity: 16)
        await uploader.configure(
            processor: { frame in await processor.process(frame) },
            notificationHandler: { _ in }
        )
        try await open(uploader)
        await uploader.markReady()
        await uploader.activateCaptureGeneration(2)

        XCTAssertTrue(uploader.offer(.pcm16(frame(), captureGeneration: 1)))
        try await uploader.ping()

        let messages = await transport.messagesSnapshot()
        XCTAssertEqual(messages.map(\.type), ["session.start", "ping"])
        XCTAssertEqual(uploader.diagnostics.snapshot.droppedStaleGenerationChunks, 1)
    }

    func testSessionStartPayloadIsInjectedWithoutProviderKnowledge() async throws {
        let transport = RecordingTransport()
        let uploader = DVKAudioUploadActor(transport: transport)
        await uploader.configure(
            processor: { _ in [] },
            notificationHandler: { _ in }
        )

        try await uploader.openConnection(
            sessionID: "session",
            traceID: "trace",
            sessionStartPayload: ["profile": .string("example")]
        )

        let messages = await transport.messagesSnapshot()
        XCTAssertEqual(messages.first?.payload["profile"], .string("example"))
    }

    func testCaptureProcessingContinuesWhileTransportSendIsBlocked() async throws {
        let transport = BlockingRecordingTransport()
        let processor = CountingStreamingProcessor()
        let uploader = DVKAudioUploadActor(
            transport: transport,
            queueCapacity: 16,
            outboundBatchBytes: 640,
            allowsContinuousInput: true,
            outboundQueueCapacity: 16
        )
        await uploader.configure(
            processor: { frame in await processor.process(frame) },
            notificationHandler: { _ in }
        )
        try await open(uploader)
        await uploader.markReady()
        await uploader.activateCaptureGeneration(1)

        for _ in 0..<5 {
            XCTAssertTrue(uploader.offer(.pcm16(frame(), captureGeneration: 1)))
        }
        await transport.waitUntilAudioSendStarts()

        for _ in 0..<10_000 {
            if await processor.countValue() == 5 { break }
            await Task.yield()
        }
        let processedCount = await processor.countValue()
        XCTAssertEqual(processedCount, 5)
        XCTAssertGreaterThanOrEqual(uploader.diagnostics.snapshot.outboundQueueHighWater, 3)

        await transport.releaseAudio()
    }

    private func open(
        _ uploader: DVKAudioUploadActor,
        sessionID: String = "session"
    ) async throws {
        try await uploader.openConnection(sessionID: sessionID, traceID: "trace")
    }

    private func frame() -> Data {
        Data(repeating: 1, count: 640)
    }

    private func chunkIndex(_ message: DVKOutboundMessage) -> Int? {
        guard case .int(let value)? = message.payload["chunk_index"] else { return nil }
        return value
    }
}

private actor TwoFrameProcessor {
    private var count = 0

    func process(_ frame: Data) -> [DVKAudioUploadIntent] {
        count += 1
        if count == 1 {
            return [.beginUtterance(interruptResponseID: nil), .audio(frame)]
        }
        return [.audio(frame), .commit]
    }
}

private actor SingleFrameProcessor {
    func process(_ frame: Data) -> [DVKAudioUploadIntent] {
        [.beginUtterance(interruptResponseID: nil), .audio(frame), .commit]
    }
}

private actor CountingStreamingProcessor {
    private var count = 0

    func process(_ frame: Data) -> [DVKAudioUploadIntent] {
        count += 1
        return [.audio(frame)]
    }

    func countValue() -> Int { count }
}

private actor RecordingTransport: DVKTransport {
    nonisolated let inboundEvents: AsyncStream<DVKInboundEvent>
    private let inboundContinuation: AsyncStream<DVKInboundEvent>.Continuation
    private var messages: [DVKOutboundMessage] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init() {
        let pair = AsyncStream<DVKInboundEvent>.makeStream(bufferingPolicy: .bufferingNewest(16))
        inboundEvents = pair.stream
        inboundContinuation = pair.continuation
    }

    func connect() async throws {}

    func send(_ message: DVKOutboundMessage) async throws {
        messages.append(message)
        let ready = waiters.filter { messages.count >= $0.count }
        waiters.removeAll { messages.count >= $0.count }
        ready.forEach { $0.continuation.resume() }
    }

    nonisolated func events() -> AsyncStream<DVKInboundEvent> {
        inboundEvents
    }

    func disconnect() async {
        inboundContinuation.finish()
    }

    func waitForMessageCount(_ count: Int) async {
        if messages.count >= count { return }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    func messagesSnapshot() -> [DVKOutboundMessage] {
        messages
    }
}

private actor BlockingRecordingTransport: DVKTransport {
    nonisolated let inboundEvents: AsyncStream<DVKInboundEvent>
    private let inboundContinuation: AsyncStream<DVKInboundEvent>.Continuation
    private var audioStarted = false
    private var audioStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var audioReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    init() {
        let pair = AsyncStream<DVKInboundEvent>.makeStream(bufferingPolicy: .bufferingNewest(4))
        inboundEvents = pair.stream
        inboundContinuation = pair.continuation
    }

    func connect() async throws {}

    func send(_ message: DVKOutboundMessage) async throws {
        guard message.type == "audio.append", !released else { return }
        audioStarted = true
        let waiters = audioStartWaiters
        audioStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            audioReleaseWaiters.append(continuation)
        }
    }

    nonisolated func events() -> AsyncStream<DVKInboundEvent> { inboundEvents }

    func disconnect() async {
        inboundContinuation.finish()
    }

    func waitUntilAudioSendStarts() async {
        if audioStarted { return }
        await withCheckedContinuation { continuation in
            audioStartWaiters.append(continuation)
        }
    }

    func releaseAudio() {
        released = true
        let waiters = audioReleaseWaiters
        audioReleaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
