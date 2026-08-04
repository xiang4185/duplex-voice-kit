import Combine
import Foundation
import Network

enum NetworkConnectionType: String, Sendable {
    case wifi
    case cellular
    case wired
    case offline
    case other
}

@MainActor
protocol NetworkMonitoring: AnyObject {
    var connectionType: NetworkConnectionType { get }
    func start()
    func stop()
}

@MainActor
final class NetworkMonitor: ObservableObject, NetworkMonitoring {
    @Published private(set) var connectionType: NetworkConnectionType = .other
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "xiaomao.network.monitor")

    var isOnline: Bool { connectionType != .offline }

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let type: NetworkConnectionType
            if path.status != .satisfied {
                type = .offline
            } else if path.usesInterfaceType(.wifi) {
                type = .wifi
            } else if path.usesInterfaceType(.cellular) {
                type = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                type = .wired
            } else {
                type = .other
            }
            Task { @MainActor in self?.connectionType = type }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}

@MainActor
final class MockNetworkMonitor: NetworkMonitoring {
    var connectionType: NetworkConnectionType = .wifi
    func start() {}
    func stop() {}
}
