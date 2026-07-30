#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation

/// A redacted session-level diagnostic snapshot containing no transcript, token, or raw audio.
public struct DVKDiagnosticsSnapshot: Sendable, Equatable {
    public let state: DVKSessionState
    public let transportState: String
    public let sessionHash: String
    public let lastEventType: String
    public let lastEventSequence: Int
    public let reconnectAttempt: Int
    public let captureGeneration: Int
    public let uploadConnectionGeneration: Int
    public let uploadNextChunkIndex: Int
    public let uploadNextClientSequence: Int
    public let uploadQueueDepth: Int
    public let uploadQueueHighWater: Int
    public let droppedStaleGenerationChunks: Int
    public let inputBackpressureCount: Int
    public let lastFiveSentChunkIndices: [Int]
    public let lastFailureCategory: String
    public let generatedAt: Date

    public init(
        state: DVKSessionState,
        transportState: String,
        sessionHash: String,
        lastEventType: String,
        lastEventSequence: Int,
        reconnectAttempt: Int,
        captureGeneration: Int,
        uploadConnectionGeneration: Int,
        uploadNextChunkIndex: Int,
        uploadNextClientSequence: Int,
        uploadQueueDepth: Int,
        uploadQueueHighWater: Int,
        droppedStaleGenerationChunks: Int,
        inputBackpressureCount: Int,
        lastFiveSentChunkIndices: [Int],
        lastFailureCategory: String,
        generatedAt: Date = Date()
    ) {
        self.state = state
        self.transportState = transportState
        self.sessionHash = sessionHash
        self.lastEventType = lastEventType
        self.lastEventSequence = max(0, lastEventSequence)
        self.reconnectAttempt = max(0, reconnectAttempt)
        self.captureGeneration = max(0, captureGeneration)
        self.uploadConnectionGeneration = max(0, uploadConnectionGeneration)
        self.uploadNextChunkIndex = max(0, uploadNextChunkIndex)
        self.uploadNextClientSequence = max(0, uploadNextClientSequence)
        self.uploadQueueDepth = max(0, uploadQueueDepth)
        self.uploadQueueHighWater = max(0, uploadQueueHighWater)
        self.droppedStaleGenerationChunks = max(0, droppedStaleGenerationChunks)
        self.inputBackpressureCount = max(0, inputBackpressureCount)
        self.lastFiveSentChunkIndices = Array(lastFiveSentChunkIndices.suffix(5))
        self.lastFailureCategory = lastFailureCategory
        self.generatedAt = generatedAt
    }

    public var redactedText: String {
        let formatter = ISO8601DateFormatter()
        return [
            "DuplexVoiceKit diagnostics",
            "state=\(state.rawValue)",
            "transport_state=\(safe(transportState, fallback: "unknown"))",
            "session_hash=\(safe(sessionHash, fallback: "none"))",
            "last_event_type=\(safe(lastEventType, fallback: "none"))",
            "last_event_sequence=\(lastEventSequence)",
            "reconnect_attempt=\(reconnectAttempt)",
            "capture_generation=\(captureGeneration)",
            "upload_connection_generation=\(uploadConnectionGeneration)",
            "upload_next_chunk_index=\(uploadNextChunkIndex)",
            "upload_next_client_sequence=\(uploadNextClientSequence)",
            "upload_queue_depth=\(uploadQueueDepth)",
            "upload_queue_high_water=\(uploadQueueHighWater)",
            "upload_dropped_stale_generation_chunks=\(droppedStaleGenerationChunks)",
            "upload_input_backpressure_count=\(inputBackpressureCount)",
            "upload_last_five_sent_chunk_indices=\(lastFiveSentChunkIndices.map(String.init).joined(separator: ","))",
            "last_failure_category=\(safe(lastFailureCategory, fallback: "none"))",
            "generated_at=\(formatter.string(from: generatedAt))"
        ].joined(separator: "\n")
    }

    public static func shortHash(_ value: String) -> String {
        guard !value.isEmpty else { return "none" }
#if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
#else
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash).suffix(8).lowercased()
#endif
    }

    private func safe(_ value: String, fallback: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(160))
    }
}

struct DVKDiagnosticsEntry: Sendable, Equatable {
    let sequence: Int
    let category: String
    let generatedAt: Date
}

final class DVKDiagnosticsRingBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var entries: [DVKDiagnosticsEntry] = []

    init(capacity: Int = 64) {
        self.capacity = max(1, capacity)
    }

    func append(_ entry: DVKDiagnosticsEntry) {
        lock.lock()
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        lock.unlock()
    }

    var snapshot: [DVKDiagnosticsEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}
