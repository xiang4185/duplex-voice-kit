import AVFoundation
import Combine
import DuplexVoiceKit
import Foundation

enum MicrophonePermissionState: String, Sendable {
    case notDetermined
    case granted
    case denied
}

@MainActor
protocol AudioSessionControlling: AnyObject {
    var permissionState: MicrophonePermissionState { get }
    var isActive: Bool { get }
    var routeDescription: String { get }
    func requestPermission() async -> Bool
    func activate() throws
    func deactivate()
    func refreshRoute()
}

/// Observable App adapter. Category, mode, route options, preferred sample rate,
/// activation, and deactivation are owned by DVKAudioSessionController.
@MainActor
final class AudioSessionController: ObservableObject, AudioSessionControlling {
    @Published private(set) var isActive = false
    @Published private(set) var routeDescription = "未激活"

    private let core: DVKAudioSessionController
    private var routeObserver: NSObjectProtocol?

    var permissionState: MicrophonePermissionState {
        switch core.permissionState {
        case .notDetermined: return .notDetermined
        case .granted: return .granted
        case .denied: return .denied
        }
    }

    init() {
        core = DVKAudioSessionController()
        installRouteObserver()
    }

    init(core: DVKAudioSessionController) {
        self.core = core
        installRouteObserver()
    }

    private func installRouteObserver() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
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

    func requestPermission() async -> Bool {
        await core.requestPermission()
    }

    func activate() throws {
        try core.activate()
        isActive = core.isActive
        refreshRoute()
    }

    func deactivate() {
        core.deactivate()
        isActive = core.isActive
        routeDescription = "未激活"
    }

    func refreshRoute() {
        core.refreshRoute()
        routeDescription = core.routeDescription == "no_output_route"
            ? "无输出路由"
            : core.routeDescription.replacingOccurrences(of: ",", with: ", ")
    }
}

@MainActor
final class MockAudioSessionController: AudioSessionControlling {
    var permissionState: MicrophonePermissionState = .granted
    private(set) var isActive = false
    private(set) var routeDescription = "Mock Speaker"

    func requestPermission() async -> Bool { permissionState == .granted }
    func activate() throws { isActive = true }
    func deactivate() { isActive = false }
    func refreshRoute() {}
}
