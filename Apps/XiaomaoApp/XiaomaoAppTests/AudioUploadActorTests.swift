import Foundation
import XCTest
@testable import XiaomaoApp

final class AudioUploadActorTests: XCTestCase {
    func testRealtimeOfferDoesNotWaitForDiagnosticsLock() async throws {
        let uploader = AudioUploadActor(socket: SerialUploadSocket())
        await configure(uploader)
        try await open(uploader)

        let clock = ContinuousClock()
        let startedAt = clock.now
        var accepted = false
        uploader.diagnostics.update { _ in
            accepted = uploader.offer(
                .pcm16(Data(repeating: 1, count: 640), captureGeneration: 1)
            )
        }
        let elapsed = startedAt.duration(to: clock.now)
        await waitUntil {
            uploader.diagnostics.snapshot.sentAudioChunks == 1
        }

        XCTAssertTrue(accepted)
        XCTAssertLessThan(elapsed, .milliseconds(200))
    }

    func testThousandAudioFramesSendStrictlyInOrder() async throws {
        let fixture = try await makeFixture(queueCapacity: 1_200)
        for _ in 0..<1_000 {
            XCTAssertTrue(fixture.uploader.offer(packet(generation: 1)))
        }
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 1_000 }
        try await fixture.uploader.commit()

        let events = await fixture.socket.eventsValue()
        let indices = audioIndices(events)
        XCTAssertEqual(indices, Array(0..<1_000))
        XCTAssertEqual(Set(indices).count, 1_000)
        XCTAssertTrue(strictlyIncreasing(events.map(\.sequence)))
    }

    func testNoPerFrameTaskIsRequired() async throws {
        let fixture = try await makeFixture(queueCapacity: 256)
        for _ in 0..<200 { _ = fixture.uploader.offer(packet(generation: 1)) }
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 200 }
        XCTAssertEqual(fixture.uploader.diagnostics.snapshot.maxActiveDrainTasks, 1)
    }

    func testCommitWaitsForAllPriorAudio() async throws {
        let fixture = try await makeFixture(queueCapacity: 128)
        for _ in 0..<100 { _ = fixture.uploader.offer(packet(generation: 1)) }
        try await fixture.uploader.commit()
        let events = await fixture.socket.eventsValue()
        let types = events.map(\.type)
        let commitIndex = try XCTUnwrap(types.lastIndex(of: .audioCommit))
        let lastAudioIndex = try XCTUnwrap(types.lastIndex(of: .audioAppend))
        XCTAssertGreaterThan(commitIndex, lastAudioIndex)
        XCTAssertEqual(types.filter { $0 == .audioAppend }.count, 100)
    }

    func testAudioAfterCommittedUtteranceIsRejected() async throws {
        let socket = SerialUploadSocket()
        let uploader = AudioUploadActor(socket: socket, queueCapacity: 16)
        let plan = LockedPlan(mode: .commitThenLateAudio)
        await configure(uploader, plan: plan)
        try await open(uploader)

        _ = uploader.offer(packet(generation: 1))
        _ = uploader.offer(packet(generation: 1))
        await waitUntil {
            uploader.diagnostics.snapshot.rejectedAfterCloseCommands == 1
        }
        let indices = audioIndices(await socket.eventsValue())
        XCTAssertEqual(indices, [0])
    }

    func testInterruptPrecedesBargeInAudio() async throws {
        let socket = SerialUploadSocket()
        let uploader = AudioUploadActor(socket: socket)
        let plan = LockedPlan(mode: .bargeIn)
        await configure(uploader, plan: plan)
        try await open(uploader)

        _ = uploader.offer(packet(generation: 1))
        await waitUntil { uploader.diagnostics.snapshot.sentAudioChunks == 1 }
        let events = await socket.eventsValue()
        let types = events.map(\.type)
        let interruptIndex = try XCTUnwrap(types.firstIndex(of: .interrupt))
        let audioIndex = try XCTUnwrap(types.firstIndex(of: .audioAppend))
        XCTAssertLessThan(interruptIndex, audioIndex)
    }

    func testCaptureRestartKeepsChunkIndex() async throws {
        let fixture = try await makeFixture()
        for _ in 0..<3 { _ = fixture.uploader.offer(packet(generation: 1)) }
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 3 }
        await fixture.uploader.activateCaptureGeneration(2)
        for _ in 0..<3 { _ = fixture.uploader.offer(packet(generation: 2)) }
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 6 }
        let events = await fixture.socket.eventsValue()
        XCTAssertEqual(audioIndices(events), Array(0..<6))
    }

    func testEngineRebuildAutomaticallyAdvancesCaptureGeneration() async throws {
        let fixture = try await makeFixture()
        _ = fixture.uploader.offer(packet(generation: 1))
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 1 }

        // Removing the old tap increments once and installing the replacement increments again.
        _ = fixture.uploader.offer(packet(generation: 3))
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 2 }

        _ = fixture.uploader.offer(packet(generation: 1))
        _ = fixture.uploader.offer(packet(generation: 3))
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 3 }
        await waitUntil {
            fixture.uploader.diagnostics.snapshot.droppedStaleGenerationChunks == 1
        }

        let snapshot = fixture.uploader.diagnostics.snapshot
        XCTAssertEqual(snapshot.captureGeneration, 3)
        XCTAssertEqual(snapshot.droppedStaleGenerationChunks, 1)
        let events = await fixture.socket.eventsValue()
        XCTAssertEqual(audioIndices(events), [0, 1, 2])
    }

    func testStaleCaptureGenerationIsDroppedBeforeIndexAllocation() async throws {
        let fixture = try await makeFixture()
        await fixture.uploader.activateCaptureGeneration(2)
        _ = fixture.uploader.offer(packet(generation: 1))
        _ = fixture.uploader.offer(packet(generation: 2))
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 1 }
        let snapshot = fixture.uploader.diagnostics.snapshot
        XCTAssertEqual(snapshot.droppedStaleGenerationChunks, 1)
        XCTAssertEqual(snapshot.nextChunkIndex, 1)
        let events = await fixture.socket.eventsValue()
        XCTAssertEqual(audioIndices(events), [0])
    }

    func testOldCaptureGenerationDroppedBeforeResampling() async throws {
        let socket = SerialUploadSocket()
        let uploader = AudioUploadActor(socket: socket)
        let plan = LockedPlan(mode: .continuous)
        await configure(uploader, plan: plan)
        try await open(uploader)
        await uploader.activateCaptureGeneration(2)

        _ = uploader.offer(packet(generation: 1))
        _ = uploader.offer(packet(generation: 2))
        await waitUntil { uploader.diagnostics.snapshot.sentAudioChunks == 1 }

        let events = await socket.eventsValue()
        XCTAssertEqual(plan.callCount, 1)
        XCTAssertEqual(uploader.diagnostics.snapshot.droppedStaleGenerationChunks, 1)
        XCTAssertEqual(audioIndices(events), [0])
    }

    func testNewWebSocketGenerationResetsChunkIndex() async throws {
        let fixture = try await makeFixture()
        for _ in 0..<2 { _ = fixture.uploader.offer(packet(generation: 1)) }
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 2 }
        await fixture.uploader.abortConnection()
        try await fixture.uploader.openConnection(
            sessionID: "session-two",
            traceID: "trace-two",
            resumeFrom: 9
        )
        await fixture.uploader.markReady()
        await fixture.uploader.activateCaptureGeneration(2)
        _ = fixture.uploader.offer(packet(generation: 2))
        await waitUntil { fixture.uploader.diagnostics.snapshot.nextChunkIndex == 1 }

        let events = await fixture.socket.eventsValue()
        let resumedIndex = try XCTUnwrap(events.lastIndex { $0.type == .sessionResume })
        let firstNewAudio = try XCTUnwrap(events[(resumedIndex + 1)...].first { $0.type == .audioAppend })
        XCTAssertEqual(payloadInt(firstNewAudio, "chunk_index"), 0)
        XCTAssertEqual(fixture.uploader.diagnostics.snapshot.connectionGeneration, 2)
    }

    func testFailedSendStopsCurrentGeneration() async throws {
        let socket = SerialUploadSocket(failAtAudioNumber: 2)
        let uploader = AudioUploadActor(socket: socket, queueCapacity: 32)
        let notifications = NotificationRecorder()
        await configure(uploader, notifications: notifications)
        try await open(uploader)
        for _ in 0..<10 { _ = uploader.offer(packet(generation: 1)) }
        await waitUntil { notifications.containsSendFailure }

        let indices = audioIndices(await socket.eventsValue())
        XCTAssertEqual(indices, [0])
        XCTAssertFalse(uploader.diagnostics.snapshot.active)
        XCTAssertEqual(uploader.diagnostics.snapshot.nextChunkIndex, 1)
    }

    func testOutboundBackpressureIsBoundedWithoutFillingCaptureIngress() async throws {
        let socket = SerialUploadSocket(sendDelay: .milliseconds(50))
        let uploader = AudioUploadActor(
            socket: socket,
            queueCapacity: 64,
            outboundQueueCapacity: 2
        )
        let notifications = NotificationRecorder()
        await configure(uploader, notifications: notifications)
        try await open(uploader)
        for _ in 0..<50 { _ = uploader.offer(packet(generation: 1)) }
        await waitUntil { notifications.containsBackpressure }

        let snapshot = uploader.diagnostics.snapshot
        let events = await socket.eventsValue()
        XCTAssertLessThanOrEqual(snapshot.queueHighWater, 64)
        XCTAssertEqual(snapshot.inputBackpressureCount, 0)
        XCTAssertEqual(snapshot.outboundBackpressureCount, 1)
        XCTAssertLessThanOrEqual(snapshot.outboundQueueHighWater, 2)
        XCTAssertEqual(audioIndices(events), Array(0..<snapshot.nextChunkIndex))
    }

    func testBackpressureFailsBeforeChunkIndexAllocation() async throws {
        let socket = SerialUploadSocket(sendDelay: .milliseconds(50))
        let uploader = AudioUploadActor(
            socket: socket,
            queueCapacity: 64,
            outboundQueueCapacity: 2
        )
        let notifications = NotificationRecorder()
        await configure(uploader, notifications: notifications)
        try await open(uploader)
        for _ in 0..<50 { _ = uploader.offer(packet(generation: 1)) }
        await waitUntil { notifications.containsBackpressure }

        let indices = audioIndices(await socket.eventsValue())
        XCTAssertEqual(indices, Array(0..<indices.count))
        XCTAssertEqual(uploader.diagnostics.snapshot.inputBackpressureCount, 0)
        XCTAssertEqual(uploader.diagnostics.snapshot.outboundBackpressureCount, 1)
        XCTAssertFalse(uploader.diagnostics.snapshot.active)
    }

    func testPingAndAudioShareOrderedClientSequence() async throws {
        let fixture = try await makeFixture()
        _ = fixture.uploader.offer(packet(generation: 1))
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 1 }
        try await fixture.uploader.ping()
        _ = fixture.uploader.offer(packet(generation: 1))
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 2 }

        let events = await fixture.socket.eventsValue()
        XCTAssertTrue(strictlyIncreasing(events.map(\.sequence)))
        let types = events.map(\.type)
        XCTAssertLessThan(
            try XCTUnwrap(types.firstIndex(of: .audioAppend)),
            try XCTUnwrap(types.firstIndex(of: .ping))
        )
    }

    func testFiveUtterancesKeepOneContinuousChunkSequence() async throws {
        let fixture = try await makeFixture(queueCapacity: 128)
        for turn in 0..<5 {
            for _ in 0..<4 { _ = fixture.uploader.offer(packet(generation: 1)) }
            await waitUntil {
                fixture.uploader.diagnostics.snapshot.sentAudioChunks == (turn + 1) * 4
            }
            try await fixture.uploader.commit()
        }
        let events = await fixture.socket.eventsValue()
        XCTAssertEqual(audioIndices(events), Array(0..<20))
        XCTAssertEqual(events.filter { $0.type == .audioCommit }.count, 5)
    }

    func testOldGenerationDelayedFailureCannotDeactivateNewGeneration() async throws {
        let result = try await runStaleGenerationFailureRace()
        let snapshot = result.uploader.diagnostics.snapshot
        let events = await result.socket.eventsValue()
        let generationTwoIndices = audioIndices(
            events.filter { $0.sessionID == "session-two" }
        )

        XCTAssertEqual(generationTwoIndices, [0, 1, 2])
        XCTAssertTrue(snapshot.active)
        XCTAssertEqual(snapshot.staleGenerationSendFailureCount, 1)
        XCTAssertEqual(snapshot.activeGenerationSendFailureCount, 0)
        let maxConcurrentSends = await result.socket.maxConcurrentSendsValue()
        XCTAssertEqual(result.notifications.sendFailureCount, 0)
        XCTAssertEqual(maxConcurrentSends, 1)
        XCTAssertEqual(snapshot.maxActiveDrainTasks, 1)
    }

    func testCurrentGenerationFailureStillFailsClosed() async throws {
        let socket = SerialUploadSocket(failAtAudioNumber: 1)
        let uploader = AudioUploadActor(socket: socket, queueCapacity: 16)
        let notifications = NotificationRecorder()
        await configure(uploader, notifications: notifications)
        try await open(uploader)

        for _ in 0..<5 { _ = uploader.offer(packet(generation: 1)) }
        await waitUntil { notifications.sendFailureCount == 1 }

        let snapshot = uploader.diagnostics.snapshot
        XCTAssertFalse(snapshot.active)
        XCTAssertEqual(snapshot.activeGenerationSendFailureCount, 1)
        XCTAssertEqual(snapshot.staleGenerationSendFailureCount, 0)
        XCTAssertEqual(snapshot.queueDepth, 0)
    }

    func testQueueCleanupOnlyRemovesFailedGenerationCommands() async throws {
        let result = try await runStaleGenerationFailureRace()
        let events = await result.socket.eventsValue()
        XCTAssertEqual(
            audioIndices(events.filter { $0.sessionID == "session-two" }),
            [0, 1, 2]
        )
        XCTAssertEqual(result.uploader.diagnostics.snapshot.queueDepth, 0)
    }

    func testStaleFailureDoesNotOverwriteCurrentDiagnostics() async throws {
        let result = try await runStaleGenerationFailureRace()
        let snapshot = result.uploader.diagnostics.snapshot
        XCTAssertEqual(snapshot.staleGenerationSendFailureCount, 1)
        XCTAssertEqual(snapshot.activeGenerationSendFailureCount, 0)
        XCTAssertEqual(snapshot.lastSendFailureCategory, "")
    }

    func testDuplicateFailureNotificationIsSuppressed() async throws {
        let socket = SerialUploadSocket(failAtAudioNumber: 1)
        let uploader = AudioUploadActor(socket: socket, queueCapacity: 32)
        let notifications = NotificationRecorder()
        await configure(uploader, notifications: notifications)
        try await open(uploader)

        for _ in 0..<20 { _ = uploader.offer(packet(generation: 1)) }
        await waitUntil { !uploader.diagnostics.snapshot.active }
        await Task.yield()

        XCTAssertEqual(notifications.sendFailureCount, 1)
        XCTAssertEqual(
            uploader.diagnostics.snapshot.activeGenerationSendFailureCount,
            1
        )
    }

    func testNewConnectionResetsSessionDiagnostics() async throws {
        let fixture = try await makeFixture(queueCapacity: 32)
        for _ in 0..<3 { _ = fixture.uploader.offer(packet(generation: 1)) }
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 3 }
        await fixture.uploader.activateCaptureGeneration(2)
        _ = fixture.uploader.offer(packet(generation: 1))
        await waitUntil {
            fixture.uploader.diagnostics.snapshot.droppedStaleGenerationChunks == 1
        }
        await fixture.uploader.abortConnection()
        _ = fixture.uploader.offer(packet(generation: 2))
        await waitUntil {
            fixture.uploader.diagnostics.snapshot.rejectedAfterCloseCommands == 1
        }

        try await fixture.uploader.openConnection(
            sessionID: "session-two",
            traceID: "trace-two"
        )
        await fixture.uploader.markReady()
        await fixture.uploader.activateCaptureGeneration(3)

        let snapshot = fixture.uploader.diagnostics.snapshot
        XCTAssertEqual(snapshot.sentAudioChunks, 0)
        XCTAssertEqual(snapshot.queueHighWater, 0)
        XCTAssertEqual(snapshot.droppedStaleGenerationChunks, 0)
        XCTAssertEqual(snapshot.rejectedAfterCloseCommands, 0)
        XCTAssertEqual(snapshot.staleGenerationSendFailureCount, 0)
        XCTAssertEqual(snapshot.activeGenerationSendFailureCount, 0)
        XCTAssertEqual(snapshot.inputBackpressureCount, 0)
        XCTAssertEqual(snapshot.lastFiveSentChunkIndices, [])
        XCTAssertEqual(snapshot.nextChunkIndex, 0)
        XCTAssertEqual(snapshot.queueDepth, 0)
        XCTAssertNotNil(snapshot.generationStartedAt)
    }

    func testSecondCallDoesNotContainFirstCallChunkCounts() async throws {
        let fixture = try await makeFixture()
        for _ in 0..<2 { _ = fixture.uploader.offer(packet(generation: 1)) }
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 2 }
        await fixture.uploader.abortConnection()
        try await fixture.uploader.openConnection(
            sessionID: "session-two",
            traceID: "trace-two"
        )
        await fixture.uploader.markReady()
        await fixture.uploader.activateCaptureGeneration(2)
        XCTAssertEqual(fixture.uploader.diagnostics.snapshot.sentAudioChunks, 0)

        for _ in 0..<3 { _ = fixture.uploader.offer(packet(generation: 2)) }
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 3 }
        XCTAssertEqual(fixture.uploader.diagnostics.snapshot.sentAudioChunks, 3)
    }

    func testQueueHighWaterResetsForNewGeneration() async throws {
        let socket = SerialUploadSocket(sendDelay: .milliseconds(10))
        let uploader = AudioUploadActor(socket: socket, queueCapacity: 32)
        await configure(uploader)
        try await open(uploader)
        for _ in 0..<8 { _ = uploader.offer(packet(generation: 1)) }
        await waitUntil { uploader.diagnostics.snapshot.queueHighWater > 0 }
        await waitUntil { uploader.diagnostics.snapshot.sentAudioChunks == 8 }

        await uploader.abortConnection()
        try await uploader.openConnection(sessionID: "session-two", traceID: "trace-two")
        await uploader.markReady()
        await uploader.activateCaptureGeneration(2)
        XCTAssertEqual(uploader.diagnostics.snapshot.queueHighWater, 0)
    }

    func testRecentIndicesResetForNewGeneration() async throws {
        let fixture = try await makeFixture()
        for _ in 0..<3 { _ = fixture.uploader.offer(packet(generation: 1)) }
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 3 }
        XCTAssertEqual(fixture.uploader.diagnostics.snapshot.lastFiveSentChunkIndices, [0, 1, 2])

        await fixture.uploader.abortConnection()
        try await fixture.uploader.openConnection(
            sessionID: "session-two",
            traceID: "trace-two"
        )
        await fixture.uploader.markReady()
        await fixture.uploader.activateCaptureGeneration(2)
        XCTAssertEqual(fixture.uploader.diagnostics.snapshot.lastFiveSentChunkIndices, [])

        for _ in 0..<3 { _ = fixture.uploader.offer(packet(generation: 2)) }
        await waitUntil { fixture.uploader.diagnostics.snapshot.sentAudioChunks == 3 }
        XCTAssertEqual(fixture.uploader.diagnostics.snapshot.lastFiveSentChunkIndices, [0, 1, 2])
    }

    func testStaleFailureCountResetsForNewGeneration() async throws {
        let result = try await runStaleGenerationFailureRace()
        XCTAssertEqual(
            result.uploader.diagnostics.snapshot.staleGenerationSendFailureCount,
            1
        )
        await result.uploader.abortConnection()
        try await result.uploader.openConnection(
            sessionID: "session-three",
            traceID: "trace-three"
        )
        XCTAssertEqual(
            result.uploader.diagnostics.snapshot.staleGenerationSendFailureCount,
            0
        )
    }

    func testTenThousandPacketConcurrentStressUsesOneWriter() async throws {
        let socket = SerialUploadSocket(yieldDuringSend: true)
        let uploader = AudioUploadActor(socket: socket, queueCapacity: 12_000)
        await configure(uploader)
        try await open(uploader)

        let controls = Task {
            for value in 0..<10 {
                try await uploader.sendClientState(["stress": .int(value)])
                try await uploader.ping()
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for producer in 0..<10 {
                group.enter()
                DispatchQueue.global().async {
                    let captured = CapturedAudioPacket.pcm16(
                        Data(repeating: 1, count: 640),
                        captureGeneration: 1
                    )
                    for index in 0..<1_000 {
                        if (producer + index).isMultiple(of: 137) {
                            Thread.sleep(forTimeInterval: 0.00001)
                        }
                        _ = uploader.offer(captured)
                    }
                    group.leave()
                }
            }
            group.notify(queue: .global()) { continuation.resume() }
        }
        // P2.8A-CI: 压测在 CI runner 上 20s 阈值过紧 (e26d32a 通过/后续轮次 21-23s 超时),
        // 放宽到 30s 适配慢环境; 断言内容不变.
        await waitUntil(timeout: .seconds(30)) {
            uploader.diagnostics.snapshot.sentAudioChunks == 10_000
        }
        try await controls.value
        try await uploader.commit()

        let events = await socket.eventsValue()
        XCTAssertEqual(audioIndices(events), Array(0..<10_000))
        XCTAssertTrue(strictlyIncreasing(events.map(\.sequence)))
        XCTAssertEqual(uploader.diagnostics.snapshot.maxActiveDrainTasks, 1)
        let maxConcurrentSends = await socket.maxConcurrentSendsValue()
        XCTAssertEqual(maxConcurrentSends, 1)
        XCTAssertLessThanOrEqual(uploader.diagnostics.snapshot.queueHighWater, 12_000)
    }

    private struct Fixture {
        let uploader: AudioUploadActor
        let socket: SerialUploadSocket
    }

    private struct StaleFailureRaceResult {
        let uploader: AudioUploadActor
        let socket: DelayedGenerationSocket
        let notifications: NotificationRecorder
    }

    private func runStaleGenerationFailureRace() async throws -> StaleFailureRaceResult {
        let socket = DelayedGenerationSocket()
        let uploader = AudioUploadActor(socket: socket, queueCapacity: 32)
        let notifications = NotificationRecorder()
        await configure(uploader, notifications: notifications)
        try await open(uploader)

        _ = uploader.offer(packet(generation: 1))
        await socket.waitForFirstGenerationAudioSend()
        await uploader.abortConnection()

        let openGenerationTwo = Task {
            try await uploader.openConnection(
                sessionID: "session-two",
                traceID: "trace-two"
            )
        }
        await waitUntil {
            uploader.diagnostics.snapshot.connectionGeneration == 2
        }
        await uploader.markReady()
        await uploader.activateCaptureGeneration(2)
        for _ in 0..<3 { _ = uploader.offer(packet(generation: 2)) }

        await socket.failFirstGenerationAudioSend()
        try await openGenerationTwo.value
        await waitUntil { uploader.diagnostics.snapshot.sentAudioChunks == 3 }

        return StaleFailureRaceResult(
            uploader: uploader,
            socket: socket,
            notifications: notifications
        )
    }

    private func makeFixture(queueCapacity: Int = 128) async throws -> Fixture {
        let socket = SerialUploadSocket()
        let uploader = AudioUploadActor(socket: socket, queueCapacity: queueCapacity)
        await configure(uploader)
        try await open(uploader)
        return Fixture(uploader: uploader, socket: socket)
    }

    private func configure(
        _ uploader: AudioUploadActor,
        plan: LockedPlan = LockedPlan(mode: .continuous),
        notifications: NotificationRecorder = NotificationRecorder()
    ) async {
        await uploader.configure(
            processor: { frame in plan.intents(for: frame) },
            notificationHandler: { event in notifications.record(event) }
        )
    }

    private func open(_ uploader: AudioUploadActor) async throws {
        try await uploader.openConnection(sessionID: "session-one", traceID: "trace-one")
        await uploader.markReady()
        await uploader.activateCaptureGeneration(1)
    }

    private func packet(generation: Int) -> CapturedAudioPacket {
        .pcm16(Data(repeating: 1, count: 640), captureGeneration: generation)
    }

    private func audioIndices(_ events: [VoiceEvent]) -> [Int] {
        events.compactMap { payloadInt($0, "chunk_index") }
    }

    private func payloadInt(_ event: VoiceEvent, _ key: String) -> Int? {
        guard event.type == .audioAppend,
              case .int(let value) = event.payload[key] else { return nil }
        return value
    }

    private func strictlyIncreasing(_ values: [Int]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { pair in
            pair.0 < pair.1
        }
    }

    private func waitUntil(
        timeout: Duration = .seconds(5),
        _ predicate: @escaping @Sendable () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("condition timed out")
    }
}

private final class LockedPlan: @unchecked Sendable {
    enum Mode { case continuous, commitThenLateAudio, bargeIn }
    private let lock = NSLock()
    private let mode: Mode
    private var count = 0

    init(mode: Mode) { self.mode = mode }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func intents(for frame: Data) -> [AudioUploadIntent] {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        switch mode {
        case .continuous:
            return [.beginUtterance(interruptResponseID: nil), .audio(frame)]
        case .commitThenLateAudio:
            return count == 1
                ? [.beginUtterance(interruptResponseID: nil), .audio(frame), .commit]
                : [.audio(frame)]
        case .bargeIn:
            return [.beginUtterance(interruptResponseID: "response-one"), .audio(frame)]
        }
    }
}

private final class NotificationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AudioUploadNotification] = []

    func record(_ event: AudioUploadNotification) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    var containsSendFailure: Bool { sendFailureCount > 0 }

    var sendFailureCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return events.filter {
            if case .sendFailed = $0 { return true }
            return false
        }.count
    }

    var containsBackpressure: Bool {
        lock.lock()
        defer { lock.unlock() }
        return events.contains {
            if case .backpressure = $0 { return true }
            return false
        }
    }
}

private actor DelayedGenerationSocket: VoiceWebSocketClient {
    nonisolated let lifecycleEvents: AsyncStream<VoiceWebSocketLifecycleEvent>
    private nonisolated let broadcaster = BoundedAsyncStreamBroadcaster<VoiceEvent>(bufferLimit: 8)
    private var sent: [VoiceEvent] = []
    private var connected = true
    private var activeSends = 0
    private var maxConcurrentSends = 0
    private var firstGenerationAudioStarted = false
    private var firstGenerationAudioWaiters: [CheckedContinuation<Void, Never>] = []
    private var suspendedSend: CheckedContinuation<Void, Error>?

    init() {
        lifecycleEvents = AsyncStream { _ in }
    }

    nonisolated func makeEventStream() -> AsyncStream<VoiceEvent> {
        broadcaster.makeStream()
    }

    func connect(url: URL, token: String, deviceID: String) async throws {
        _ = url
        _ = token
        _ = deviceID
        connected = true
    }

    func send(_ event: VoiceEvent) async throws {
        activeSends += 1
        maxConcurrentSends = max(maxConcurrentSends, activeSends)
        defer { activeSends -= 1 }

        if event.type == .audioAppend,
           event.sessionID == "session-one",
           !firstGenerationAudioStarted {
            firstGenerationAudioStarted = true
            let waiters = firstGenerationAudioWaiters
            firstGenerationAudioWaiters.removeAll()
            waiters.forEach { $0.resume() }
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                suspendedSend = continuation
            }
        }
        sent.append(event)
    }

    func waitForFirstGenerationAudioSend() async {
        if firstGenerationAudioStarted { return }
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in
            firstGenerationAudioWaiters.append(continuation)
        }
    }

    func failFirstGenerationAudioSend() {
        suspendedSend?.resume(throwing: AppError.networkUnavailable)
        suspendedSend = nil
    }

    func ping() async throws {}
    func disconnect() async { connected = false }
    func isConnected() async -> Bool { connected }
    func eventsValue() -> [VoiceEvent] { sent }
    func maxConcurrentSendsValue() -> Int { maxConcurrentSends }
}

private actor SerialUploadSocket: VoiceWebSocketClient {
    nonisolated let lifecycleEvents: AsyncStream<VoiceWebSocketLifecycleEvent>
    private nonisolated let broadcaster = BoundedAsyncStreamBroadcaster<VoiceEvent>(bufferLimit: 8)
    private var sent: [VoiceEvent] = []
    private var connected = true
    private var activeSends = 0
    private var maxConcurrentSends = 0
    private var audioSendNumber = 0
    private let failAtAudioNumber: Int?
    private let sendDelay: Duration?
    private let yieldDuringSend: Bool

    init(
        failAtAudioNumber: Int? = nil,
        sendDelay: Duration? = nil,
        yieldDuringSend: Bool = false
    ) {
        self.failAtAudioNumber = failAtAudioNumber
        self.sendDelay = sendDelay
        self.yieldDuringSend = yieldDuringSend
        lifecycleEvents = AsyncStream { _ in }
    }

    nonisolated func makeEventStream() -> AsyncStream<VoiceEvent> {
        broadcaster.makeStream()
    }

    func connect(url: URL, token: String, deviceID: String) async throws {
        _ = url
        _ = token
        _ = deviceID
        connected = true
    }

    func send(_ event: VoiceEvent) async throws {
        activeSends += 1
        maxConcurrentSends = max(maxConcurrentSends, activeSends)
        defer { activeSends -= 1 }
        if let sendDelay { try await Task.sleep(for: sendDelay) }
        if yieldDuringSend { await Task.yield() }
        if event.type == .audioAppend {
            audioSendNumber += 1
            if let failAtAudioNumber, audioSendNumber == failAtAudioNumber {
                throw AppError.networkUnavailable
            }
        }
        sent.append(event)
    }

    func ping() async throws {}
    func disconnect() async { connected = false }
    func isConnected() async -> Bool { connected }
    func eventsValue() -> [VoiceEvent] { sent }
    func maxConcurrentSendsValue() -> Int { maxConcurrentSends }
}
