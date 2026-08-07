import DuplexVoiceKit
import Foundation

typealias VoiceActivityMode = DVKVoiceActivityMode
typealias VoiceActivityState = DVKVoiceActivityState
typealias VoiceActivityCommitReason = DVKVoiceActivityCommitReason
typealias VoiceActivityConfiguration = DVKVoiceActivityConfiguration
typealias VoiceActivityAction = DVKVoiceActivityAction
typealias VoiceActivityAnalysis = DVKVoiceActivityAnalysis
typealias VoiceActivityDetector = DVKVoiceActivityDetector

extension DVKVoiceActivityConfiguration {
    /// Xiaomao host tuning: preserve the proven Core thresholds and only shorten
    /// the end-of-utterance silence window so a completed sentence is committed
    /// earlier. Public Core defaults remain unchanged for other hosts.
    static let xiaomaoRealtime = realtimeDefault.replacingEndSilence(milliseconds: 480)
}
