import Foundation
import CommonCrypto
import UIKit
import UserNotifications

/// Manages push token capture, Keychain storage, backend registration, and delivery tracking.
final class PushTokenManager {
    private let keychainStore: KeychainStore
    private weak var eventTracker: EventTracker?
    private weak var apiClient: APIClient?

    private static let keychainKey = "push_token"

    /// The current push token string (hex-encoded), read from Keychain.
    var currentTokenString: String? {
        keychainStore.getString(key: Self.keychainKey)
    }

    init(keychainStore: KeychainStore, eventTracker: EventTracker?, apiClient: APIClient? = nil) {
        self.keychainStore = keychainStore
        self.eventTracker = eventTracker
        self.apiClient = apiClient
    }

    /// Store the push token, send a registration event, and register with backend.
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

        // Register token with backend (POST /api/v1/push/token)
        registerTokenWithBackend(tokenString)
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

    /// Track that a push notification was delivered (called from notification extension or foreground handler).
    func trackDelivered(pushId: String) {
        eventTracker?.track(event: "push_delivered", properties: ["push_id": pushId])

        Task {
            do {
                let _: EmptyResponse = try await apiClient?.request(.pushDelivered(body: [
                    "push_id": pushId,
                ])) ?? EmptyResponse()
            } catch {
                Log.warning("Failed to track push delivered: \(error)")
            }
        }
    }

    /// Track that a push notification was tapped.
    func trackTapped(pushId: String, action: String? = nil) {
        var props: [String: String] = ["push_id": pushId]
        if let action = action { props["action"] = action }
        eventTracker?.track(event: "push_tapped", properties: props)

        Task {
            do {
                let _: EmptyResponse = try await apiClient?.request(.pushTapped(body: [
                    "push_id": pushId,
                ])) ?? EmptyResponse()
            } catch {
                Log.warning("Failed to track push tapped: \(error)")
            }
        }
    }

    // MARK: - Public: Permission Request

    /// Request push notification permission from the user.
    /// Returns `true` if the user granted permission, `false` otherwise.
    public func requestPermission() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            setPushPermission(granted: granted)
            return granted
        } catch {
            Log.error("Failed to request push permission: \(error)")
            return false
        }
    }

    // MARK: - Private

    private func registerTokenWithBackend(_ tokenString: String) {
        Task {
            do {
                let body: [String: Any] = [
                    "token": tokenString,
                    "platform": "ios",
                    "device_id": UIDevice.current.identifierForVendor?.uuidString ?? "",
                    "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                    "sdk_version": "0.3.0",
                    "os_version": UIDevice.current.systemVersion,
                ]
                let _: EmptyResponse = try await apiClient?.request(.registerPushToken(body: body)) ?? EmptyResponse()
                Log.info("Push token registered with backend")
            } catch {
                Log.warning("Failed to register push token with backend: \(error)")
            }
        }
    }

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

/// Empty Codable response for fire-and-forget requests.
private struct EmptyResponse: Codable {}
