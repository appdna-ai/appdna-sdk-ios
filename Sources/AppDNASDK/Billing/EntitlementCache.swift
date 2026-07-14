import Foundation
import FirebaseFirestore

/// Caches entitlements locally and listens to Firestore for real-time updates.
class EntitlementCache {
    private(set) var entitlements: [ServerEntitlement] = []
    private var firestoreListener: ListenerRegistration?
    private var changeHandlers: [([ServerEntitlement]) -> Void] = []

    private let userDefaultsKey = "com.appdna.entitlements"

    var hasActiveSubscription: Bool {
        entitlements.contains { $0.status == "active" || $0.status == "trialing" || $0.status == "grace_period" }
    }

    func entitlement(for productId: String) -> ServerEntitlement? {
        entitlements.first { $0.productId == productId && ($0.status == "active" || $0.status == "trialing") }
    }

    func update(_ entitlement: ServerEntitlement) {
        if let index = entitlements.firstIndex(where: { $0.productId == entitlement.productId }) {
            entitlements[index] = entitlement
        } else {
            entitlements.append(entitlement)
        }
        persistLocally()
        notifyHandlers()
    }

    func startObserving(orgId: String, appId: String, userId: String) {
        let path = "orgs/\(orgId)/apps/\(appId)/users/\(userId)/entitlements/current"
        guard let db = AppDNA.firestoreDB else { return }
        firestoreListener = db.document(path)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self, let data = snapshot?.data() else { return }
                self.parseFirestoreData(data)
                self.notifyHandlers()
            }
    }

    func stopObserving() {
        firestoreListener?.remove()
        firestoreListener = nil
    }

    func onEntitlementsChanged(_ handler: @escaping ([ServerEntitlement]) -> Void) {
        changeHandlers.append(handler)
    }

    func persistLocally() {
        if let data = try? JSONEncoder().encode(entitlements) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    func loadFromLocalCache() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let cached = try? JSONDecoder().decode([ServerEntitlement].self, from: data) {
            entitlements = cached
        }
    }

    private func parseFirestoreData(_ data: [String: Any]) {
        guard let subscriptions = data["subscriptions"] as? [[String: Any]] else { return }

        entitlements = subscriptions.compactMap { sub in
            guard let productId = sub["product_id"] as? String,
                  let store = sub["store"] as? String,
                  let status = sub["status"] as? String else { return nil }

            return ServerEntitlement(
                productId: productId,
                store: store,
                status: status,
                expiresAt: sub["expires_at"] as? String,
                isTrial: sub["is_trial"] as? Bool ?? false,
                offerType: sub["offer_type"] as? String
            )
        }
        persistLocally()
    }

    private func notifyHandlers() {
        let current = entitlements
        for handler in changeHandlers {
            handler(current)
        }
        NotificationCenter.default.post(name: .entitlementsChanged, object: nil, userInfo: ["entitlements": current])
    }
}

extension Notification.Name {
    static let entitlementsChanged = Notification.Name("com.appdna.entitlementsChanged")
}

// MARK: - ISO8601 parsing

/// 🔴 EVERY `expiresAt` FROM THE SERVER PARSED TO `nil`.
///
/// The server sends `Date.toISOString()` — `2026-07-14T10:00:00.000Z`, WITH fractional seconds. A bare
/// `ISO8601DateFormatter()` does not set `.withFractionalSeconds`, and without it the parse of a
/// fractional timestamp returns nil. Not "sometimes": every time, for every entitlement, on every build.
///
/// So the one code path that DID read an expiry threw it away, while the other
/// (`BillingModule.getEntitlements`) hard-coded nil. Between them, `Entitlement.expiresAt` was
/// unreachable — a public field of a public type that could not hold a value.
///
/// Tries fractional first (what our server actually sends), then plain (what a store or a hand-written
/// fixture might send). One parser, one place, both spellings.
enum ISO8601 {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from string: String) -> Date? {
        fractional.date(from: string) ?? plain.date(from: string)
    }
}
