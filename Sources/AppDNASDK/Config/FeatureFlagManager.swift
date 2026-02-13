import Foundation

/// Thin wrapper over RemoteConfigManager for boolean feature flags.
final class FeatureFlagManager {
    private let remoteConfigManager: RemoteConfigManager

    init(remoteConfigManager: RemoteConfigManager) {
        self.remoteConfigManager = remoteConfigManager
    }

    /// Returns true if the flag exists and is a truthy boolean value.
    func isEnabled(flag: String) -> Bool {
        guard let value = remoteConfigManager.getConfig(key: flag) else {
            return false
        }

        if let bool = value as? Bool {
            return bool
        }

        // Treat numeric 1 as true
        if let num = value as? NSNumber {
            return num.boolValue
        }

        return false
    }
}
