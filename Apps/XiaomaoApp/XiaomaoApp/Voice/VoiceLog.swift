import Foundation
import OSLog

enum VoiceLog {
    static let subsystem = "com.example.xiaomao.sideload"
    static let lifecycle = Logger(subsystem: subsystem, category: "voice.lifecycle")
    static let websocket = Logger(subsystem: subsystem, category: "voice.websocket")
    static let audio = Logger(subsystem: subsystem, category: "voice.audio")
    static let ui = Logger(subsystem: subsystem, category: "voice.ui")
}
