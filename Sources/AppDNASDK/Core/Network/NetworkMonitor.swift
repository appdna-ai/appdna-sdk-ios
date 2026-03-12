import Foundation
import Network

/// SPEC-067: Network condition monitoring for adaptive batch sizing.
/// Wraps NWPathMonitor to expose current connection type.
final class NetworkMonitor {
    /// Shared singleton instance.
    static let shared = NetworkMonitor()

    /// Connection type categories for adaptive batching.
    enum ConnectionType {
        case wifi
        case cellular
        case none
    }

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "ai.appdna.sdk.networkmonitor")
    private(set) var currentConnectionType: ConnectionType = .wifi
    private(set) var isExpensive: Bool = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if path.status == .satisfied {
                if path.usesInterfaceType(.wifi) {
                    self.currentConnectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self.currentConnectionType = .cellular
                } else {
                    // Wired or other connected interface — treat as wifi
                    self.currentConnectionType = .wifi
                }
            } else {
                self.currentConnectionType = .none
            }
            self.isExpensive = path.isExpensive
            Log.debug("Network changed: \(self.currentConnectionType), expensive=\(self.isExpensive)")
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    /// Returns the adaptive batch size based on current network conditions.
    var adaptiveBatchSize: Int {
        switch currentConnectionType {
        case .wifi:
            return 100
        case .cellular:
            return isExpensive ? 20 : 50
        case .none:
            return 0
        }
    }
}
