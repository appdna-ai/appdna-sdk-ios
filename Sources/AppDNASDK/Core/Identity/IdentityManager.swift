import Foundation

/// Represents the current device + user identity.
struct DeviceIdentity {
    let anonId: String
    var userId: String?
    var traits: [String: Any]?
}

/// Manages anonymous and identified user identity.
/// Thread-safe via serial dispatch queue.
final class IdentityManager {
    private let queue = DispatchQueue(label: "ai.appdna.sdk.identity")
    private let keychainStore: KeychainStore

    // Weak reference set after initialization
    weak var sessionManager: SessionManager?

    private var _anonId: String
    private var _userId: String?
    private var _traits: [String: Any]?

    var currentIdentity: DeviceIdentity {
        queue.sync {
            DeviceIdentity(anonId: _anonId, userId: _userId, traits: _traits)
        }
    }

    init(keychainStore: KeychainStore) {
        self.keychainStore = keychainStore

        // Load or generate anonymous ID
        if let existing = keychainStore.getAnonId() {
            self._anonId = existing
            Log.debug("Loaded existing anon_id: \(existing)")
        } else {
            let newId = UUID().uuidString.lowercased()
            keychainStore.setAnonId(newId)
            self._anonId = newId
            Log.info("Generated new anon_id: \(newId)")
        }

        // Load persisted user ID and traits
        self._userId = keychainStore.getUserId()
        self._traits = keychainStore.getUserTraits()
    }

    /// Link anonymous user to a known user.
    func identify(userId: String, traits: [String: Any]? = nil) {
        queue.sync {
            _userId = userId
            _traits = traits
            keychainStore.setUserId(userId)
            if let traits = traits {
                keychainStore.setUserTraits(traits)
            }
        }
    }

    /// Clear user identity. Keeps anonymous ID.
    func reset() {
        queue.sync {
            _userId = nil
            _traits = nil
            keychainStore.clearUserId()
            keychainStore.clearUserTraits()
        }
    }
}
