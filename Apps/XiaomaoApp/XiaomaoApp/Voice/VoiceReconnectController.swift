import DuplexVoiceKit
import Foundation

typealias VoiceReconnectPolicy = DVKReconnectPolicy

extension DVKReconnectPolicy {
    static let development = DVKReconnectPolicy.realtimeDefault
}

/// App Task-lifecycle coordinator backed by the shared DVK reconnect policy.
actor VoiceReconnectController {
    private(set) var attempt = 0
    let policy: VoiceReconnectPolicy

    init(policy: VoiceReconnectPolicy = .development) {
        self.policy = policy
    }

    func reset() {
        attempt = 0
    }

    func nextDelay() -> Duration? {
        guard attempt < policy.maximumAttempts else { return nil }
        attempt += 1
        return policy.delay(for: attempt)
    }
}
