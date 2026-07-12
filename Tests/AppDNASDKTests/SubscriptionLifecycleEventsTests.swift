import XCTest
@testable import AppDNASDK

/// 🔴 iOS emitted ZERO subscription-lifecycle events — every renewal was invisible.
///
/// The only code that could emit them lived in `Billing/NativeBillingManager`, a class that was never
/// instantiated (the live path is `StoreKit2Bridge`, which tracks nothing). An iOS subscriber therefore
/// produced exactly ONE MTPU-qualifying event, ever. `SubscriptionStatusObserver` is the live path's
/// emitter; these tests drive its REAL diff and read back what the REAL `EventTracker` produced, via the
/// `eventSink` seam.
///
/// The StoreKit half (`reconcile()`, which reads `Transaction.currentEntitlements`) is not drivable in a
/// unit test without a StoreKitTest session — but the diff below is what decides EVERY emit, and its
/// inputs are the snapshot shape `reconcile()` builds.
///
/// Property + event names are asserted literally, because they must equal Android's byte-for-byte:
/// `NativeBillingManager.diffAndEmit` emits `subscription_renewed {product_id, purchase_time}`,
/// `subscription_canceled {product_id}`, `subscription_renewal_failed {product_id}`. A divergent name
/// here is the same silent-analytics bug in a new place — `raw.sdk_events.properties` is a JSON blob and
/// a misspelled key never alerts.
final class SubscriptionLifecycleEventsTests: XCTestCase {

    private var events: [SDKEvent] = []
    private var observer: SubscriptionStatusObserver!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        events = []
        let suite = "appdna.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        let keychain = KeychainStore(service: "ai.appdna.sdk.test.\(UUID().uuidString)")
        let tracker = EventTracker(identityManager: IdentityManager(keychainStore: keychain))
        tracker.eventSink = { [weak self] event in self?.events.append(event) }
        observer = SubscriptionStatusObserver(eventTracker: tracker, defaults: defaults)
    }

    private func snap(
        _ productId: String,
        purchaseTime: Int64,
        isAutoRenewing: Bool = true
    ) -> SubSnapshot {
        SubSnapshot(productId: productId, purchaseTime: purchaseTime, isAutoRenewing: isAutoRenewing)
    }

    private func names() -> [String] { events.map(\.event_name) }

    private func properties(of eventName: String) -> [String: Any] {
        guard let event = events.first(where: { $0.event_name == eventName }),
              let props = event.properties else { return [:] }
        return props.mapValues { $0.value }
    }

    // MARK: - Renewal

    func testRenewalEmitsSubscriptionRenewedWithAndroidsPropertyNames() {
        observer.diffAndEmit(
            previous: ["pro_yearly": snap("pro_yearly", purchaseTime: 1_000)],
            current: ["pro_yearly": snap("pro_yearly", purchaseTime: 2_000)]
        )

        XCTAssertEqual(names(), ["subscription_renewed"])
        let props = properties(of: "subscription_renewed")
        XCTAssertEqual(props["product_id"] as? String, "pro_yearly")
        XCTAssertEqual(props["purchase_time"] as? Int64, 2_000)
    }

    func testAnUnchangedSubscriptionEmitsNothing() {
        observer.diffAndEmit(
            previous: ["pro_yearly": snap("pro_yearly", purchaseTime: 1_000)],
            current: ["pro_yearly": snap("pro_yearly", purchaseTime: 1_000)]
        )
        XCTAssertEqual(names(), [])
    }

    // MARK: - Cancel vs renewal-failure

    func testAVanishedAutoRenewingSubscriptionIsARenewalFailure() {
        observer.diffAndEmit(
            previous: ["pro_yearly": snap("pro_yearly", purchaseTime: 1_000, isAutoRenewing: true)],
            current: [:]
        )

        XCTAssertEqual(names(), ["subscription_renewal_failed"])
        XCTAssertEqual(properties(of: "subscription_renewal_failed")["product_id"] as? String, "pro_yearly")
    }

    func testAVanishedNonAutoRenewingSubscriptionIsACancel() {
        observer.diffAndEmit(
            previous: ["pro_yearly": snap("pro_yearly", purchaseTime: 1_000, isAutoRenewing: false)],
            current: [:]
        )

        XCTAssertEqual(names(), ["subscription_canceled"])
        XCTAssertEqual(properties(of: "subscription_canceled")["product_id"] as? String, "pro_yearly")
    }

    // MARK: - The first purchase is not a renewal

    func testANewSubscriptionEmitsNothing() {
        // The initial purchase is `purchase_completed`'s job. Emitting here as well is exactly the
        // double-count that Android had on its purchase events.
        observer.diffAndEmit(previous: [:], current: ["pro_yearly": snap("pro_yearly", purchaseTime: 5_000)])
        XCTAssertEqual(names(), [])
    }

    // MARK: - Snapshot persistence (a renewal must not re-emit on every launch)

    func testSnapshotRoundTripsSoARenewalIsEmittedOnlyOnce() {
        let snapshot = ["pro_yearly": snap("pro_yearly", purchaseTime: 2_000)]
        observer.saveSnapshot(snapshot)
        XCTAssertEqual(observer.loadSnapshot(), snapshot)

        // Second pass over the SAME state: nothing new.
        observer.diffAndEmit(previous: observer.loadSnapshot(), current: snapshot)
        XCTAssertEqual(names(), [])
    }
}
