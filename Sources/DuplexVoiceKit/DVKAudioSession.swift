#if os(iOS)
import AVFoundation
import Foundation

/// Normalized microphone permission states exposed to a host application.
public enum DVKMicrophonePermissionState: String, Sendable {
    case notDetermined
    case granted
    case denied
}

/// Configures and monitors the shared iOS audio session for full-duplex voice.
@MainActor
public final class DVKAudioSessionController {
    public private(set) var isActive = false
    public private(set) var routeDescription = "inactive"

    private let session: AVAudioSession
    private let configuration: DVKAudioConfiguration
    private var routeObserver: NSObjectProtocol?

    public var permissionState: DVKMicrophonePermissionState {
        switch session.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    public init(
        configuration: DVKAudioConfiguration = .realtimeVoice,
        session: AVAudioSession = .sharedInstance()
    ) {
        self.configuration = configuration
        self.session = session
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshRoute()
            }
        }
    }

    deinit {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
    }

    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            session.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
    }

    public func activate() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        )
        try session.setPreferredSampleRate(configuration.captureSampleRate)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        isActive = true
        refreshRoute()
    }

    public func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        isActive = false
        routeDescription = "inactive"
    }

    public func refreshRoute() {
        let outputs = session.currentRoute.outputs.map { $0.portType.rawValue }
        routeDescription = outputs.isEmpty ? "no_output_route" : outputs.joined(separator: ",")
    }
}
#endif
