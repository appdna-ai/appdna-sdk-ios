import Foundation
import KeychainAccess

/// Wrapper around KeychainAccess for identity persistence.
final class KeychainStore {
    private let keychain: Keychain

    private enum Keys {
        static let anonId = "anon_id"
        static let userId = "user_id"
        static let userTraits = "user_traits"
    }

    init(service: String = "ai.appdna.sdk") {
        self.keychain = Keychain(service: service)
            .accessibility(.afterFirstUnlock)
    }

    // MARK: - Anonymous ID

    func getAnonId() -> String? {
        try? keychain.get(Keys.anonId)
    }

    func setAnonId(_ id: String) {
        try? keychain.set(id, key: Keys.anonId)
    }

    // MARK: - User ID

    func getUserId() -> String? {
        try? keychain.get(Keys.userId)
    }

    func setUserId(_ id: String) {
        try? keychain.set(id, key: Keys.userId)
    }

    func clearUserId() {
        try? keychain.remove(Keys.userId)
    }

    // MARK: - User Traits

    func getUserTraits() -> [String: Any]? {
        guard let data = try? keychain.getData(Keys.userTraits) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func setUserTraits(_ traits: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: traits) else { return }
        try? keychain.set(data, key: Keys.userTraits)
    }

    func clearUserTraits() {
        try? keychain.remove(Keys.userTraits)
    }

    // MARK: - Generic string storage

    func getString(key: String) -> String? {
        try? keychain.get(key)
    }

    func setString(key: String, value: String) {
        try? keychain.set(value, key: key)
    }
}
