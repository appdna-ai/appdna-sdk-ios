import Foundation
import CommonCrypto

/// Manages push token capture, Keychain storage, and forwarding via events.
final class PushTokenManager {
    private let keychainStore: KeychainStore
    private weak var eventTracker: EventTracker?

    private static let keychainKey = "push_token"

    init(keychainStore: KeychainStore, eventTracker: EventTracker?) {
        self.keychainStore = keychainStore
        self.eventTracker = eventTracker
    }

    /// Store the push token and send a registration event if it has changed.
    /// - Parameter token: The raw APNS token data from `didRegisterForRemoteNotificationsWithDeviceToken`.
    func setPushToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        let previousToken = keychainStore.getString(key: Self.keychainKey)

        // Store in Keychain (not UserDefaults — sensitive data)
        keychainStore.setString(key: Self.keychainKey, value: tokenString)

        // Only send event if token is new or changed
        if tokenString != previousToken {
            let hashedToken = sha256(tokenString)
            eventTracker?.track(event: "push_token_registered", properties: [
                "token_hash": hashedToken,
                "platform": "ios",
            ])
            Log.info("Push token registered (hash: \(hashedToken.prefix(12))...)")
        }
    }

    /// Track push permission status.
    /// - Parameter granted: Whether the user granted push notification permission.
    func setPushPermission(granted: Bool) {
        if granted {
            eventTracker?.track(event: "push_permission_granted", properties: [:])
        } else {
            eventTracker?.track(event: "push_permission_denied", properties: [:])
        }
        Log.info("Push permission: \(granted ? "granted" : "denied")")
    }

    // MARK: - Private

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
