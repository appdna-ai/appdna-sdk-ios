import XCTest
@testable import AppDNASDK

/// 🔴 `SubscriptionStatusObserver.reconcile()` could DOUBLE-EMIT `subscription_renewed` — an MTPU
/// OVER-count on the most common renewal case there is.
///
/// It was a plain `async` method on a plain class: no actor, no lock, no in-flight flag. Two
/// unsynchronized triggers drive it — the `Transaction.updates` task (which also reconciles once at
/// start) and a `didBecomeActive` observer that spawns its own Task — and the method awaits
/// `Transaction.currentEntitlements` AND `Product.products(for:)` (a network call) BEFORE writing its
/// snapshot. Cold start after a renewal that happened while the app was dead fires both triggers at once:
/// both load the same stale `previous`, both see the later `purchaseTime`, and both emit.
///
/// MTPU is how customers are metered (`BigQueryBillingService.getMTPU`), so a duplicate renewal event is
/// a billing error, not just a chart error.
///
/// These tests drive the REAL `reconcile()` through the injected `EntitlementLoader` seam — StoreKit
/// itself needs a StoreKitTest session, and a race nobody can drive is a race nobody proves fixed. The
/// loader stands in for the wide await window (`currentEntitlements` + the `Product.products` network
/// hop) that made the race reachable in the first place.
final class SubscriptionObserverConcurrencyTests: XCTestCase {

    private var events: [SDKEvent] = []
    private let eventsLock = NSLock()
    private var defaults: UserDefaults!
    private var tracker: EventTracker!

    override func setUp() {
        super.setUp()
        events = []
        let suite = "appdna.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        let keychain = KeychainStore(service: "ai.appdna.sdk.test.\(UUID().uuidString)")
        tracker = EventTracker(identityManager: IdentityManager(keychainStore: keychain))
        tracker.eventSink = { [weak self] event in
            guard let self else { return }
            // Passes run on the cooperative pool; the sink is written from more than one of them.
            self.eventsLock.lock()
            self.events.append(event)
            self.eventsLock.unlock()
        }
    }

    private func names() -> [String] {
        eventsLock.lock()
        defer { eventsLock.unlock() }
        return events.map(\.event_name)
    }

    private func snap(_ productId: String, purchaseTime: Int64) -> SubSnapshot {
        SubSnapshot(productId: productId, purchaseTime: purchaseTime, isAutoRenewing: true)
    }

    // MARK: - The double-emit

    /// The cold-start-after-a-renewal case, verbatim: a persisted snapshot from before the renewal, and
    /// TWO triggers firing at once against a loader that takes as long as StoreKit + the network do.
    ///
    /// Without the serial chain both passes read the pre-renewal snapshot and emit — two
    /// `subscription_renewed` for one renewal. With it, pass 2 reads what pass 1 persisted and emits
    /// nothing.
    func testTwoConcurrentReconcilesEmitExactlyOneSubscriptionRenewed() async {
        let observer = SubscriptionStatusObserver(
            eventTracker: tracker,
            defaults: defaults,
            loadCurrent: {
                // The window `reconcile()` really has: `Transaction.currentEntitlements` plus a
                // `Product.products(for:)` network round trip, all before the snapshot is written.
                try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms
                return ["pro_yearly": SubSnapshot(productId: "pro_yearly", purchaseTime: 2_000, isAutoRenewing: true)]
            }
        )
        observer.saveSnapshot(["pro_yearly": snap("pro_yearly", purchaseTime: 1_000)])

        // The two triggers: the start-reconcile and the first didBecomeActive-reconcile.
        async let first: Void = observer.reconcile()
        async let second: Void = observer.reconcile()
        _ = await (first, second)

        XCTAssertEqual(names(), ["subscription_renewed"], "one renewal must emit exactly one event")
    }

    /// The serialization itself, asserted directly — the emit-count test above depends on it, but this
    /// one cannot pass by luck of timing. Passes must not OVERLAP: the second loader may not start until
    /// the first pass has persisted its snapshot.
    func testReconcilePassesDoNotOverlap() async {
        let trace = TraceBox()
        let observer = SubscriptionStatusObserver(
            eventTracker: tracker,
            defaults: defaults,
            loadCurrent: {
                trace.append("enter")
                try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
                trace.append("exit")
                return [:]
            }
        )

        async let first: Void = observer.reconcile()
        async let second: Void = observer.reconcile()
        _ = await (first, second)

        // Unserialized this is ["enter", "enter", "exit", "exit"].
        XCTAssertEqual(trace.entries(), ["enter", "exit", "enter", "exit"])
    }

    /// Serialized, NOT coalesced. A second trigger that arrives during a pass still runs its own pass
    /// afterwards — it may carry state the first pass began before it existed. Dropping it would trade
    /// the over-count for an under-count.
    func testASecondPassStillObservesStateThatChangedDuringTheFirst() async {
        let state = SnapshotBox(["pro_yearly": snap("pro_yearly", purchaseTime: 1_000)])
        let observer = SubscriptionStatusObserver(
            eventTracker: tracker,
            defaults: defaults,
            loadCurrent: { state.value() }
        )
        observer.saveSnapshot(["pro_yearly": snap("pro_yearly", purchaseTime: 1_000)])

        await observer.reconcile()
        XCTAssertEqual(names(), [], "nothing changed yet")

        // The renewal lands, and a trigger fires for it.
        state.set(["pro_yearly": snap("pro_yearly", purchaseTime: 2_000)])
        await observer.reconcile()
        XCTAssertEqual(names(), ["subscription_renewed"])

        // …and a third pass over the same state re-emits nothing.
        await observer.reconcile()
        XCTAssertEqual(names(), ["subscription_renewed"])
    }

    // MARK: - RevenueCat / Adapty (`.providerOwned`)

    /// 🔴 The RevenueCat / Adapty hosts emitted ZERO subscription-lifecycle events: the observer was
    /// only started `if billingBridge is StoreKit2Bridge`, under a comment claiming those bridges "own
    /// their own event emission" — which they do not. This observer is the SDK's only emitter of the
    /// three, so an iOS host on `.revenueCat` or `.adapty` produced exactly one MTPU event per
    /// subscriber, ever.
    ///
    /// Under `.providerOwned` the observer must NOT drain `Transaction.updates` (the provider owns
    /// transaction finishing), but it must still reconcile — at start, on foreground, and on the
    /// provider's own subscriber-state callback (`AppDNA.reconcileSubscriptionState()` →
    /// `reconcileNow()`). This asserts a provider-owned observer emits the renewal.
    func testProviderOwnedObserverStillEmitsLifecycleEventsOnStart() async throws {
        let observer = SubscriptionStatusObserver(
            eventTracker: tracker,
            defaults: defaults,
            mode: .providerOwned,
            loadCurrent: { ["pro_yearly": SubSnapshot(productId: "pro_yearly", purchaseTime: 2_000, isAutoRenewing: true)] }
        )
        observer.saveSnapshot(["pro_yearly": snap("pro_yearly", purchaseTime: 1_000)])
        defer { observer.stop() }

        observer.start() // spawns the start-reconcile
        try await waitFor { self.names() == ["subscription_renewed"] }

        // …and the provider's callback path emits nothing extra for state that has not moved.
        observer.reconcileNow()
        await observer.reconcile()
        XCTAssertEqual(names(), ["subscription_renewed"])
    }

    /// Poll rather than sleep: `start()` reconciles inside a detached Task, and a fixed sleep either
    /// flakes or wastes a second.
    private func waitFor(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition not met within \(timeout)s")
    }

    /// `reconcileNow()` — the non-async entry point the foreground observer and the RevenueCat /
    /// Adapty callbacks use — goes through the same chain.
    func testReconcileNowIsSerializedAgainstReconcile() async {
        let trace = TraceBox()
        let observer = SubscriptionStatusObserver(
            eventTracker: tracker,
            defaults: defaults,
            loadCurrent: {
                trace.append("enter")
                try? await Task.sleep(nanoseconds: 50_000_000)
                trace.append("exit")
                return [:]
            }
        )

        observer.reconcileNow()
        await observer.reconcile()
        // The awaited pass is queued BEHIND the fire-and-forget one, so by the time it returns both have
        // run, in order.
        XCTAssertEqual(trace.entries(), ["enter", "exit", "enter", "exit"])
    }
}

/// A thread-safe ordered trace. The passes run on the cooperative pool, so an unlocked array here would
/// be the test's own data race.
private final class TraceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    func append(_ item: String) {
        lock.lock()
        items.append(item)
        lock.unlock()
    }

    func entries() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

/// A mutable snapshot the test can move between passes.
private final class SnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: [String: SubSnapshot]

    init(_ snapshot: [String: SubSnapshot]) { self.snapshot = snapshot }

    func value() -> [String: SubSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func set(_ next: [String: SubSnapshot]) {
        lock.lock()
        snapshot = next
        lock.unlock()
    }
}
