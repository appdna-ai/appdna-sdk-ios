import Foundation
import FirebaseFirestore

/// Notification posted when the web entitlement changes.
extension Notification.Name {
    static let webEntitlementChanged = Notification.Name("AppDNA.webEntitlementChanged")
}

/// Reads and observes web subscription entitlements from Firestore.
/// Path: /orgs/{orgId}/apps/{appId}/users/{userId}/web_entitlements
final class WebEntitlementManager {
    private var listener: ListenerRegistration?
    private(set) var currentEntitlement: WebEntitlement?
    private weak var eventTracker: EventTracker?
    private var previousStatus: EntitlementStatus?
    private static let cacheKey = "ai.appdna.sdk.web_entitlement_cache"

    init(eventTracker: EventTracker?) {
        self.eventTracker = eventTracker
        // Load cached entitlement for offline resilience
        loadCachedEntitlement()
    }

    private func loadCachedEntitlement() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        currentEntitlement = WebEntitlement(from: map)
        previousStatus = currentEntitlement?.status
    }

    private func cacheEntitlement(_ entitlement: WebEntitlement?) {
        if let entitlement {
            let map = entitlement.toMap()
            if let data = try? JSONSerialization.data(withJSONObject: map) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        }
    }

    /// Start observing the Firestore entitlement document for the given user.
    func startObserving(orgId: String, appId: String, userId: String) {
        stopObserving()

        let path = "orgs/\(orgId)/apps/\(appId)/users/\(userId)/web_entitlements"
        Log.debug("WebEntitlementManager: observing \(path)")

        listener = Firestore.firestore().document(path).addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }

            if let error {
                Log.error("WebEntitlement listener error: \(error.localizedDescription)")
                return
            }

            guard let data = snapshot?.data() else {
                // No entitlement doc — user has no web subscription
                if self.currentEntitlement != nil {
                    self.currentEntitlement = nil
                    self.cacheEntitlement(nil)
                    NotificationCenter.default.post(name: .webEntitlementChanged, object: nil)
                }
                return
            }

            let entitlement = WebEntitlement(from: data)
            let prevStatus = self.previousStatus
            self.currentEntitlement = entitlement
            self.previousStatus = entitlement.status
            self.cacheEntitlement(entitlement)

            // Post notification
            NotificationCenter.default.post(name: .webEntitlementChanged, object: entitlement)

            // Track events
            if entitlement.isActive && (prevStatus == nil || prevStatus == .canceled || prevStatus == .pastDue) {
                self.eventTracker?.track(event: "web_entitlement_activated", properties: [
                    "plan_name": entitlement.planName ?? "",
                    "status": entitlement.status.rawValue,
                ])
            } else if !entitlement.isActive && (prevStatus == .active || prevStatus == .trialing) {
                self.eventTracker?.track(event: "web_entitlement_expired", properties: [
                    "plan_name": entitlement.planName ?? "",
                    "reason": entitlement.status.rawValue,
                ])
            }
        }
    }

    /// Stop observing.
    func stopObserving() {
        listener?.remove()
        listener = nil
    }

    deinit {
        stopObserving()
    }
}
