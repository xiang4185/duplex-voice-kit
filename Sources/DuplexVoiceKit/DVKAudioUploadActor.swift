import Foundation

/// Describes how one processed PCM frame should affect the outbound voice stream.
public enum DVKAudioUploadIntent: Sendable {
    case beginUtterance(interruptResponseID: String?)
    case audio(Data)
    case commit
}

/// Reports observable upload outcomes without exposing queue or synchronization internals.
public enum DVKAudioUploadNotification: Sendable {
    case audioSent(bytes: Int, chunkIndex: Int)
    case commitSent
    case interruptSent(responseID: String)
    case sendFailed(category: String)
    case backpressure
}

/// Errors surfaced by the public audio upload pipeline.
public enum DVKAudioUploadError: Error, Equatable, Sendable {
    case inactiveConnection
    case queueBackpressure
    case invalidAudioChunk
    case sendFailed
}

/// An immutable-to-clients snapshot of upload ordering, generation, queue, and failure health.
public struct DVKAudioUploadDiagnosticsSnapshot: Sendable, Equatable {
    public internal(set) var connectionGeneration = 0
    public internal(set) var captureGeneration = 0
    public internal(set) var nextChunkIndex = 0
    public internal(set) var nextClientSequence = 0
    public internal(set) var active = false
    public internal(set) var acceptingAudio = false
    public internal(set) var queueDepth = 0
    public internal(set) var queueHighWater = 0
    public internal(set) var sentAudioChunks = 0
    public internal(set) var sentControlCommands = 0
    public internal(set) var droppedStaleGenerationChunks = 0
    public internal(set) var rejectedAfterCloseCommands = 0
    public internal(set) var staleGenerationSendFailureCount = 0
    public internal(set) var activeGenerationSendFailureCount = 0
    public internal(set) var inputBackpressureCount = 0
    public internal(set) var maxActiveDrainTasks = 0
    public internal(set) var lastFiveSentChunkIndices: [Int] = []
    public internal(set) var lastSendFailureCategory = ""
    public internal(set) var generationStartedAt: Date?
}

final class DVKAudioUploadDiagnosticsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value = DVKAudioUploadDiagnosticsSnapshot()

    var snapshot: DVKAudioUploadDiagnosticsSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func update(_ body: (inout DVKAudioUploadDiagnosticsSnapshot) -> Void) {
        lock.lock()
        body(&value)
        lock.unlock()
    }

    func reset(_ snapshot: DVKAudioUploadDiagnosticsSnapshot) {
        lock.lock()
        value = snapshot
        lock.unlock()
    }
}

private enum DVKAudioUploadControl: Sendable {
    case sessionStart
    case sessionResume(lastReceivedServerSequence: Int)
    case audioCommit
    case interrupt(responseID: String)
    case mute
    case unmute
    case clientState([String: DVKJSONValue])
    case sessionEnd
    case ping
}

private final class DVKUploadCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func resolve(_ result: Result<Void, Error>) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.result = result
            lock.unlock()
        }
    }
}

private enum DVKAudioUploadIngressItem: Sendable {
    case captured(DVKCapturedAudioPacket, connectionGeneration: Int)
    case control(DVKAudioUploadControl, DVKUploadCompletion, connectionGeneration: Int)

    var connectionGeneration: Int {
        switch self {
        case .captured(_, let generation), .control(_, _, let generation):
            return generation
        }
    }

    var isCapturedAudio: Bool {
        if case .captured = self { return true }
        return false
    }
}

private final class DVKAudioUploadIngress: @unchecked Sendable {
    let signals: AsyncStream<Int>
    private let continuation: AsyncStream<Int>.Continuation
    private let serialQueue = DispatchQueue(label: "duplexvoicekit.audio.upload.ingress")
    private let availableSlots: DispatchSemaphore
    private var queue: [DVKAudioUploadIngressItem] = []
    private var head = 0
    private var trackedGeneration = 0
    private var captureOfferGeneration = 0
    private var storedHighWater = 0

    init(capacity: Int) {
        availableSlots = DispatchSemaphore(value: max(1, capacity))
        let pair = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(256))
        signals = pair.stream
        continuation = pair.continuation
    }

    func offerCaptured(_ packet: DVKCapturedAudioPacket) -> Bool {
        guard availableSlots.wait(timeout: .now()) == .success else {
            serialQueue.async { [self] in
                continuation.yield(-max(1, captureOfferGeneration))
            }
            return false
        }
        serialQueue.async { [self] in
            let generation = captureOfferGeneration
            let item = DVKAudioUploadIngressItem.captured(
                packet,
                connectionGeneration: generation
            )
            append(item)
            continuation.yield(generation)
        }
        return true
    }

    func offerControl(_ item: DVKAudioUploadIngressItem) -> Bool {
        let generation = max(1, item.connectionGeneration)
        guard availableSlots.wait(timeout: .now()) == .success else {
            continuation.yield(-generation)
            return false
        }
        serialQueue.sync { append(item) }
        continuation.yield(generation)
        return true
    }

    private func append(_ item: DVKAudioUploadIngressItem) {
        queue.append(item)
        if item.isCapturedAudio,
           item.connectionGeneration == trackedGeneration {
            let audioDepth = queue[head...].filter {
                $0.connectionGeneration == trackedGeneration && $0.isCapturedAudio
            }.count
            storedHighWater = max(storedHighWater, audioDepth)
        }
    }

    func pop() -> DVKAudioUploadIngressItem? {
        let item: DVKAudioUploadIngressItem? = serialQueue.sync {
            guard head < queue.count else { return nil }
            let item = queue[head]
            head += 1
            if head >= 256, head * 2 >= queue.count {
                queue.removeFirst(head)
                head = 0
            }
            return item
        }
        if item != nil { availableSlots.signal() }
        return item
    }

    func remove(generation: Int) -> [DVKAudioUploadIngressItem] {
        let removed: [DVKAudioUploadIngressItem] = serialQueue.sync {
            let pending = Array(queue[head...])
            let removed = pending.filter { $0.connectionGeneration == generation }
            queue = pending.filter { $0.connectionGeneration != generation }
            head = 0
            return removed
        }
        for _ in removed { availableSlots.signal() }
        return removed
    }

    func resetHighWater(generation: Int) {
        serialQueue.sync {
            trackedGeneration = generation
            captureOfferGeneration = generation
            storedHighWater = 0
        }
    }

    func deactivateCaptureOffers() {
        serialQueue.sync {
            captureOfferGeneration = 0
        }
    }

    func depth(generation: Int) -> Int {
        serialQueue.sync {
            queue[head...].filter {
                $0.connectionGeneration == generation && $0.isCapturedAudio
            }.count
        }
    }

    func highWater(generation: Int) -> Int {
        serialQueue.sync { generation == trackedGeneration ? storedHighWater : 0 }
    }
}

actor DVKAudioUploadActor: DVKAudioCaptureSink {
    typealias FrameProcessor = @Sendable (Data) async -> [DVKAudioUploadIntent]
    typealias NotificationHandler = @Sendable (DVKAudioUploadNotification) async -> Void

    nonisolated let diagnostics = DVKAudioUploadDiagnosticsStore()
    private nonisolated let ingress: DVKAudioUploadIngress
    private let transport: any DVKOutboundTransport
    private var processor: FrameProcessor?
    private var notificationHandler: NotificationHandler?
    private var drainTask: Task<Void, Never>?
    private var codec = DVKProtocolCodec()
    private var sessionID = ""
    private var traceID = ""
    private var sessionStartPayload: [String: DVKJSONValue] = [:]
    private var activeConnectionGeneration = 0
    private var captureGeneration = 0
    private var nextChunkIndex = 0
    private var active = false
    private var ready = false
    private var acceptingAudio = false
    private var utteranceOpen = false
    private var pendingPCM16 = Data()
    private var activeDrainTasks = 0
    private var failureNotifiedGeneration: Int?
    private var backpressureNotifiedGeneration: Int?

    init(transport: any DVKOutboundTransport, queueCapacity: Int = 100) {
        self.transport = transport
        ingress = DVKAudioUploadIngress(capacity: queueCapacity)
    }

    @discardableResult
    nonisolated func offer(_ packet: DVKCapturedAudioPacket) -> Bool {
        ingress.offerCaptured(packet)
    }

    func configure(
        processor: @escaping FrameProcessor,
        notificationHandler: @escaping NotificationHandler
    ) {
        self.processor = processor
        self.notificationHandler = notificationHandler
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in
            await self?.drainLoop()
        }
    }

    func openConnection(
        sessionID: String,
        traceID: String,
        sessionStartPayload: [String: DVKJSONValue] = [:],
        resumeFrom lastReceivedServerSequence: Int? = nil
    ) async throws {
        let previousGeneration = activeConnectionGeneration
        ingress.deactivateCaptureOffers()
        if previousGeneration > 0 {
            rejectPending(
                generation: previousGeneration,
                error: DVKAudioUploadError.inactiveConnection
            )
        }
        activeConnectionGeneration &+= 1
        self.sessionID = sessionID
        self.traceID = traceID
        self.sessionStartPayload = sessionStartPayload
        codec = DVKProtocolCodec()
        nextChunkIndex = 0
        captureGeneration = 0
        pendingPCM16.removeAll(keepingCapacity: false)
        utteranceOpen = false
        active = true
        ready = false
        acceptingAudio = false
        failureNotifiedGeneration = nil
        backpressureNotifiedGeneration = nil
        ingress.resetHighWater(generation: activeConnectionGeneration)
        var freshDiagnostics = DVKAudioUploadDiagnosticsSnapshot()
        freshDiagnostics.connectionGeneration = activeConnectionGeneration
        freshDiagnostics.active = true
        freshDiagnostics.maxActiveDrainTasks = activeDrainTasks
        freshDiagnostics.generationStartedAt = Date()
        diagnostics.reset(freshDiagnostics)
        publishDiagnostics()
        if let lastReceivedServerSequence {
            try await enqueueAndWait(.sessionResume(
                lastReceivedServerSequence: max(0, lastReceivedServerSequence)
            ))
        } else {
            try await enqueueAndWait(.sessionStart)
        }
    }

    func markReady() {
        guard active else { return }
        ready = true
        publishDiagnostics()
    }

    func activateCaptureGeneration(_ generation: Int) {
        guard active, ready else { return }
        captureGeneration = generation
        acceptingAudio = true
        pendingPCM16.removeAll(keepingCapacity: false)
        publishDiagnostics()
    }

    func pauseCapture() {
        acceptingAudio = false
        captureGeneration &+= 1
        pendingPCM16.removeAll(keepingCapacity: false)
        publishDiagnostics()
    }

    func commit() async throws {
        try await enqueueAndWait(.audioCommit)
    }

    func interrupt(responseID: String) async throws {
        try await enqueueAndWait(.interrupt(responseID: responseID))
    }

    func setMuted(_ muted: Bool) async throws {
        try await enqueueAndWait(muted ? .mute : .unmute)
    }

    func sendClientState(_ payload: [String: DVKJSONValue]) async throws {
        try await enqueueAndWait(.clientState(payload))
    }

    func ping() async throws {
        try await enqueueAndWait(.ping)
    }

    func endSession() async throws {
        try await enqueueAndWait(.sessionEnd)
    }

    func abortConnection() {
        let generation = activeConnectionGeneration
        ingress.deactivateCaptureOffers()
        active = false
        ready = false
        acceptingAudio = false
        utteranceOpen = false
        pendingPCM16.removeAll(keepingCapacity: false)
        rejectPending(
            generation: generation,
            error: DVKAudioUploadError.inactiveConnection
        )
        publishDiagnostics()
    }

    private func enqueueAndWait(_ command: DVKAudioUploadControl) async throws {
        guard active else { throw DVKAudioUploadError.inactiveConnection }
        let generation = activeConnectionGeneration
        let completion = DVKUploadCompletion()
        guard ingress.offerControl(.control(
            command,
            completion,
            connectionGeneration: generation
        )) else {
            completion.resolve(.failure(DVKAudioUploadError.queueBackpressure))
            throw DVKAudioUploadError.queueBackpressure
        }
        publishDiagnostics()
        try await completion.wait()
    }

    private func drainLoop() async {
        activeDrainTasks += 1
        diagnostics.update {
            $0.maxActiveDrainTasks = max($0.maxActiveDrainTasks, activeDrainTasks)
        }
        defer { activeDrainTasks -= 1 }
        for await signal in ingress.signals {
            if signal < 0 {
                await failBackpressure(generation: abs(signal))
            }
            while let item = ingress.pop() {
                await process(item)
            }
            publishDiagnostics()
        }
    }

    private func process(_ item: DVKAudioUploadIngressItem) async {
        switch item {
        case .captured(let packet, let generation):
            await processCaptured(packet, connectionGeneration: generation)
        case .control(let command, let completion, let generation):
            do {
                try await processControl(command, connectionGeneration: generation)
                completion.resolve(.success(Void()))
            } catch {
                completion.resolve(.failure(error))
            }
        }
    }

    private func processCaptured(
        _ packet: DVKCapturedAudioPacket,
        connectionGeneration sendingGeneration: Int
    ) async {
        guard sendingGeneration > 0 else {
            diagnostics.update { $0.rejectedAfterCloseCommands += 1 }
            return
        }
        guard sendingGeneration == activeConnectionGeneration else {
            diagnostics.update { $0.droppedStaleGenerationChunks += 1 }
            return
        }
        guard active, ready, acceptingAudio else {
            diagnostics.update { $0.rejectedAfterCloseCommands += 1 }
            return
        }
        if packet.captureGeneration > captureGeneration {
            captureGeneration = packet.captureGeneration
            pendingPCM16.removeAll(keepingCapacity: false)
            publishDiagnostics()
        } else if packet.captureGeneration < captureGeneration {
            diagnostics.update { $0.droppedStaleGenerationChunks += 1 }
            return
        }
        guard let processor else { return }
        pendingPCM16.append(resampleToPCM16(packet))
        while pendingPCM16.count >= 640, active, acceptingAudio {
            let frame = Data(pendingPCM16.prefix(640))
            pendingPCM16.removeFirst(640)
            let packetGeneration = captureGeneration
            let intents = await processor(frame)
            guard active,
                  ready,
                  acceptingAudio,
                  sendingGeneration == activeConnectionGeneration,
                  packetGeneration == captureGeneration else {
                diagnostics.update { $0.droppedStaleGenerationChunks += 1 }
                return
            }
            do {
                for intent in intents {
                    try await processIntent(
                        intent,
                        connectionGeneration: sendingGeneration
                    )
                }
            } catch {
                return
            }
        }
    }

    private func processIntent(
        _ intent: DVKAudioUploadIntent,
        connectionGeneration sendingGeneration: Int
    ) async throws {
        guard active,
              ready,
              sendingGeneration == activeConnectionGeneration else {
            throw DVKAudioUploadError.inactiveConnection
        }
        switch intent {
        case .beginUtterance(let responseID):
            utteranceOpen = true
            if let responseID, !responseID.isEmpty {
                try await sendMessage(
                    .interrupt,
                    payload: ["response_id": .string(responseID)],
                    connectionGeneration: sendingGeneration
                )
                await notificationHandler?(.interruptSent(responseID: responseID))
            }
        case .audio(let data):
            guard utteranceOpen else {
                diagnostics.update { $0.rejectedAfterCloseCommands += 1 }
                return
            }
            guard data.count <= DVKProtocolCodec.maximumChunkBytes,
                  data.count.isMultiple(of: 2) else {
                throw DVKAudioUploadError.invalidAudioChunk
            }
            let index = nextChunkIndex
            let message = codec.makeMessage(
                type: .audioAppend,
                sessionID: sessionID,
                traceID: traceID,
                payload: [
                    "format": .string(DVKProtocolCodec.format),
                    "sample_rate": .int(DVKProtocolCodec.sampleRate),
                    "channels": .int(DVKProtocolCodec.channels),
                    "chunk_index": .int(index),
                    "audio": .string(data.base64EncodedString())
                ]
            )
            do {
                try await transport.send(message)
            } catch {
                await failSend(error, generation: sendingGeneration)
                throw DVKAudioUploadError.sendFailed
            }
            guard active,
                  sendingGeneration == activeConnectionGeneration else {
                throw DVKAudioUploadError.inactiveConnection
            }
            nextChunkIndex += 1
            diagnostics.update {
                $0.nextChunkIndex = nextChunkIndex
                $0.sentAudioChunks += 1
                $0.lastFiveSentChunkIndices.append(index)
                if $0.lastFiveSentChunkIndices.count > 5 {
                    $0.lastFiveSentChunkIndices.removeFirst()
                }
            }
            await notificationHandler?(.audioSent(bytes: data.count, chunkIndex: index))
        case .commit:
            guard utteranceOpen else { return }
            try await sendMessage(
                .audioCommit,
                connectionGeneration: sendingGeneration
            )
            utteranceOpen = false
            await notificationHandler?(.commitSent)
        }
    }

    private func processControl(
        _ command: DVKAudioUploadControl,
        connectionGeneration sendingGeneration: Int
    ) async throws {
        switch command {
        case .sessionStart:
            try await sendMessage(
                .sessionStart,
                payload: sessionStartPayload,
                connectionGeneration: sendingGeneration
            )
        case .sessionResume(let sequence):
            try await sendMessage(
                .sessionResume,
                payload: ["last_received_server_sequence": .int(sequence)],
                connectionGeneration: sendingGeneration
            )
        case .audioCommit:
            try await sendMessage(
                .audioCommit,
                connectionGeneration: sendingGeneration
            )
            utteranceOpen = false
            await notificationHandler?(.commitSent)
        case .interrupt(let responseID):
            try await sendMessage(
                .interrupt,
                payload: ["response_id": .string(responseID)],
                connectionGeneration: sendingGeneration
            )
            await notificationHandler?(.interruptSent(responseID: responseID))
        case .mute:
            try await sendMessage(.mute, connectionGeneration: sendingGeneration)
        case .unmute:
            try await sendMessage(.unmute, connectionGeneration: sendingGeneration)
        case .clientState(let payload):
            try await sendMessage(
                .clientState,
                payload: payload,
                connectionGeneration: sendingGeneration
            )
        case .sessionEnd:
            try await sendMessage(.sessionEnd, connectionGeneration: sendingGeneration)
        case .ping:
            try await sendMessage(.ping, connectionGeneration: sendingGeneration)
        }
    }

    private func sendMessage(
        _ type: DVKProtocolEventType,
        payload: [String: DVKJSONValue] = [:],
        connectionGeneration sendingGeneration: Int
    ) async throws {
        guard active,
              sendingGeneration == activeConnectionGeneration else {
            throw DVKAudioUploadError.inactiveConnection
        }
        let message = codec.makeMessage(
            type: type,
            sessionID: sessionID,
            traceID: traceID,
            payload: payload
        )
        do {
            try await transport.send(message)
        } catch {
            await failSend(error, generation: sendingGeneration)
            throw DVKAudioUploadError.sendFailed
        }
        guard active,
              sendingGeneration == activeConnectionGeneration else {
            throw DVKAudioUploadError.inactiveConnection
        }
        diagnostics.update { $0.sentControlCommands += 1 }
    }

    private func failBackpressure(generation: Int) async {
        guard generation == activeConnectionGeneration else { return }
        guard active else { return }
        guard backpressureNotifiedGeneration != generation else { return }
        backpressureNotifiedGeneration = generation
        diagnostics.update { $0.inputBackpressureCount += 1 }
        ingress.deactivateCaptureOffers()
        active = false
        ready = false
        acceptingAudio = false
        pendingPCM16.removeAll(keepingCapacity: false)
        rejectPending(
            generation: generation,
            error: DVKAudioUploadError.queueBackpressure
        )
        await notificationHandler?(.backpressure)
        publishDiagnostics()
    }

    private func failSend(_ error: Error, generation: Int) async {
        guard generation == activeConnectionGeneration else {
            diagnostics.update { $0.staleGenerationSendFailureCount += 1 }
            return
        }
        guard active else { return }
        guard failureNotifiedGeneration != generation else { return }
        failureNotifiedGeneration = generation
        let category = String(describing: type(of: error))
        diagnostics.update {
            $0.activeGenerationSendFailureCount += 1
            $0.lastSendFailureCategory = category
        }
        ingress.deactivateCaptureOffers()
        active = false
        ready = false
        acceptingAudio = false
        pendingPCM16.removeAll(keepingCapacity: false)
        rejectPending(
            generation: generation,
            error: DVKAudioUploadError.sendFailed
        )
        await notificationHandler?(.sendFailed(category: category))
        publishDiagnostics()
    }

    private func rejectPending(generation: Int, error: Error) {
        for item in ingress.remove(generation: generation) {
            if case .control(_, let completion, _) = item {
                completion.resolve(.failure(error))
            }
        }
    }

    private func publishDiagnostics() {
        diagnostics.update {
            $0.connectionGeneration = activeConnectionGeneration
            $0.captureGeneration = captureGeneration
            $0.nextChunkIndex = nextChunkIndex
            $0.nextClientSequence = codec.clientSequence
            $0.active = active
            $0.acceptingAudio = acceptingAudio
            $0.queueDepth = ingress.depth(generation: activeConnectionGeneration)
            $0.queueHighWater = max(
                $0.queueHighWater,
                ingress.highWater(generation: activeConnectionGeneration)
            )
        }
    }

    private func resampleToPCM16(_ packet: DVKCapturedAudioPacket) -> Data {
        guard packet.frameCount > 0, packet.channels > 0, packet.sampleRate > 0 else { return Data() }
        let mono = monoFloatSamples(packet)
        guard !mono.isEmpty else { return Data() }
        let outputCount = max(1, Int((Double(mono.count) * 16_000.0 / Double(packet.sampleRate)).rounded()))
        var output = [Int16]()
        output.reserveCapacity(outputCount)
        for index in 0..<outputCount {
            let position = Double(index) * Double(max(1, mono.count - 1)) / Double(max(1, outputCount - 1))
            let lower = Int(position.rounded(.down))
            let upper = min(mono.count - 1, lower + 1)
            let fraction = Float(position - Double(lower))
            let value = mono[lower] + (mono[upper] - mono[lower]) * fraction
            let clamped = max(-1.0, min(1.0, value))
            output.append(Int16(clamped * Float(Int16.max)))
        }
        return output.withUnsafeBytes { Data($0) }
    }

    private func monoFloatSamples(_ packet: DVKCapturedAudioPacket) -> [Float] {
        switch packet.format {
        case .float32Planar:
            return packet.data.withUnsafeBytes { raw in
                let source = raw.bindMemory(to: Float.self)
                return (0..<packet.frameCount).map { frame in
                    var total: Float = 0
                    for channel in 0..<packet.channels {
                        total += source[channel * packet.frameCount + frame]
                    }
                    return total / Float(packet.channels)
                }
            }
        case .float32Interleaved:
            return packet.data.withUnsafeBytes { raw in
                let source = raw.bindMemory(to: Float.self)
                return (0..<packet.frameCount).map { frame in
                    var total: Float = 0
                    for channel in 0..<packet.channels {
                        total += source[frame * packet.channels + channel]
                    }
                    return total / Float(packet.channels)
                }
            }
        case .int16Planar:
            return packet.data.withUnsafeBytes { raw in
                let source = raw.bindMemory(to: Int16.self)
                return (0..<packet.frameCount).map { frame in
                    var total: Float = 0
                    for channel in 0..<packet.channels {
                        total += Float(source[channel * packet.frameCount + frame]) / Float(Int16.max)
                    }
                    return total / Float(packet.channels)
                }
            }
        case .int16Interleaved:
            return packet.data.withUnsafeBytes { raw in
                let source = raw.bindMemory(to: Int16.self)
                return (0..<packet.frameCount).map { frame in
                    var total: Float = 0
                    for channel in 0..<packet.channels {
                        total += Float(source[frame * packet.channels + channel]) / Float(Int16.max)
                    }
                    return total / Float(packet.channels)
                }
            }
        }
    }
}
