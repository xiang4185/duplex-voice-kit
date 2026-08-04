import Foundation

struct VoiceMetrics: Sendable {
    var traceID = ""
    var sessionID = ""
    var responseID = ""
    var route: VoiceRoute = .b
    var inputFrames = 0
    var outputChunks = 0
    var inputBytes = 0
    var outputBytes = 0
    var droppedFrames = 0
    var duplicateFrames = 0
    var reorderedFrames = 0
    var reconnectCount = 0
    var interruptCount = 0
    var interruptSuccessCount = 0
    var degradedCount = 0
    var startedAt: Date?
    var firstInputAt: Date?
    var firstAudioAt: Date?
    var finishedAt: Date?
}
