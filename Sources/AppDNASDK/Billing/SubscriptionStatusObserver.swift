import Foundation
import StoreKit
#if canImport(UIKit)
import UIKit
#endif

/// One auto-renewable subscription as the SDK last observed it.
///
/// Field-for-field the same snapshot Android persists (`NativeBillingManager.SubSnapshot`), including
/// `purchaseTime` in epoch **milliseconds** — Play hands out millis, so iOS converts rather than
/// letting the same property mean two different things per platform.
struct SubSnapshot: Codable, Equatable {
    let productId: String
    let purchaseTime: Int64
    let isAutoRenewing: Bool
}

/// 🔴 iOS emitted ZERO subscription-lifecycle events.
///
/// `Billing/NativeBillingManager.swift` had a `Transaction.updates` listener, but that class was never
/// instantiated — the live billing surface is `BillingModule.bridge` → `StoreKit2Bridge`, which tracks
/// nothing. Net effect: an iOS subscriber produced exactly ONE MTPU-qualifying event, ever
/// (`purchase_completed` at signup). Every renewal after that was invisible, so iOS LTV,
/// renewal-retention and churn curves showed subscribers vanishing after month 1 — silently, because
/// `raw.sdk_events.properties` is a JSON blob and a missing event never alerts.
///
/// This observer is the live path's lifecycle emitter. It mirrors Android's
/// `NativeBillingManager.reconcileSubscriptionState` / `diffAndEmit` exactly — same three event names,
/// same property names, same snapshot-diff rules:
///
///   - product **vanished** from the entitlements, previously auto-renewing → `subscription_renewal_failed`
///     (billing retry / grace period), otherwise → `subscription_canceled`
///   - product **still present** with a later `purchaseTime` → `subscription_renewed`
///   - product **new** since the last snapshot → nothing (that is `purchase_completed`'s job — emitting
///     here too is how you get the double-count Android had on its purchase events)
///
/// Two triggers, matching Android's two: StoreKit's `Transaction.updates` (the direct analogue of Play's
/// `PurchasesUpdatedListener`, but unlike Play's it DOES fire for renewals) and app-foreground (Android
/// uses `ProcessLifecycleOwner.ON_START` — it catches the expirations that produce no transaction at all).
final class SubscriptionStatusObserver {

    /// Persisted under the same semantic key Android uses (`billing_last_sub_snapshot_v1`).
    static let snapshotKey = "appdna.billing.last_sub_snapshot_v1"

    private let eventTracker: EventTracker
    private let defaults: UserDefaults
    private var updatesTask: Task<Void, Never>?
    private var foregroundToken: NSObjectProtocol?

    init(eventTracker: EventTracker, defaults: UserDefaults = .standard) {
        self.eventTracker = eventTracker
        self.defaults = defaults
    }

    // MARK: - Lifecycle

    /// Start observing. Long-lived: the `Transaction.updates` sequence never ends, so the task lives
    /// for the whole SDK session and is cancelled by `stop()` (called from `AppDNA.shutdown()`).
    func start() {
        guard updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            // Renewals that happened while the app was dead do not necessarily arrive as an update —
            // reconcile once at launch so they are still caught. Same reason Android reconciles on
            // every foreground entry rather than trusting its purchase listener.
            await self?.reconcile()

            for await result in Transaction.updates {
                guard let self else { return }
                guard case .verified(let transaction) = result else { continue }
                // Apple redelivers an unfinished transaction on every launch forever. StoreKit2Bridge
                // finishes the ones it purchases; a RENEWAL arrives here and nothing else would.
                await transaction.finish()
                await self.reconcile()
            }
        }

        #if canImport(UIKit)
        foregroundToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.reconcile() }
        }
        #endif
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        if let token = foregroundToken {
            NotificationCenter.default.removeObserver(token)
            foregroundToken = nil
        }
    }

    // MARK: - Reconcile

    /// Re-derive the current subscription snapshot from StoreKit, diff it against the persisted one,
    /// emit, and persist. Mirrors Android `reconcileSubscriptionState()`.
    func reconcile() async {
        // Cross-account-leak guard, resolved ONCE per pass so the decision matrix sees a stable value
        // even if the host identifies a different user mid-iteration (same as `StoreKit2Bridge.restore`).
        let expectedToken = AppAccountTokenResolver.tokenForCurrentUser()
        let firstIdentifier = AppAccountTokenResolver.firstIdentifiedToken()

        var current: [String: SubSnapshot] = [:]
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productType == .autoRenewable else { continue }
            if transaction.revocationDate != nil { continue }

            switch EntitlementOwnerFilter.decide(
                transactionToken: transaction.appAccountToken,
                expectedToken: expectedToken,
                firstIdentifiedToken: firstIdentifier
            ) {
            case .denyOtherUser, .denyUntaggedOtherUser:
                // A renewal for user A arriving while user B is signed in is not user B's renewal.
                continue
            case .grant, .grantAnonymousPolicy, .grantUntaggedMigration:
                break
            }

            let willAutoRenew = await autoRenewStatus(for: transaction.productID)
            current[transaction.productID] = SubSnapshot(
                productId: transaction.productID,
                purchaseTime: Int64(transaction.purchaseDate.timeIntervalSince1970 * 1000),
                isAutoRenewing: willAutoRenew
            )
        }

        let previous = loadSnapshot()
        diffAndEmit(previous: previous, current: current)
        saveSnapshot(current)
    }

    /// The pure diff. No I/O, no StoreKit — this is the half a unit test can drive.
    ///
    /// Event + property names are Android's, verbatim (`NativeBillingManager.diffAndEmit`): a divergent
    /// property name here would be the same silent-analytics bug in a new place. Both names are spelled
    /// out as literals at the callsite so `check:event-name-parity` can see them.
    func diffAndEmit(previous: [String: SubSnapshot], current: [String: SubSnapshot]) {
        for (productId, prev) in previous where current[productId] == nil {
            if prev.isAutoRenewing {
                eventTracker.track(event: "subscription_renewal_failed", properties: [
                    "product_id": productId,
                ])
            } else {
                eventTracker.track(event: "subscription_canceled", properties: [
                    "product_id": productId,
                ])
            }
        }

        for (productId, now) in current {
            guard let prev = previous[productId] else { continue } // new product = purchase, not renewal
            if now.purchaseTime > prev.purchaseTime {
                eventTracker.track(event: "subscription_renewed", properties: [
                    "product_id": productId,
                    "purchase_time": now.purchaseTime,
                ])
            }
        }
    }

    // MARK: - Auto-renew status

    /// Whether Apple will auto-renew this subscription — the same signal Play exposes as
    /// `Purchase.isAutoRenewing`, and the one that decides `renewal_failed` vs `canceled` when the
    /// product later vanishes. Unknown (offline, unresolvable product) defaults to `true`, which is what
    /// an active subscription normally is; the alternative would mis-label a billing-retry as a
    /// deliberate cancel.
    private func autoRenewStatus(for productID: String) async -> Bool {
        do {
            let products = try await Product.products(for: [productID])
            guard let subscription = products.first?.subscription else { return true }
            let statuses = try await subscription.status
            guard let status = statuses.first else { return true }
            guard case .verified(let renewalInfo) = status.renewalInfo else { return true }
            return renewalInfo.willAutoRenew
        } catch {
            Log.debug("SubscriptionStatusObserver: could not resolve auto-renew status for \(productID): \(error)")
            return true
        }
    }

    // MARK: - Persistence

    func loadSnapshot() -> [String: SubSnapshot] {
        guard let data = defaults.data(forKey: Self.snapshotKey) else { return [:] }
        return (try? JSONDecoder().decode([String: SubSnapshot].self, from: data)) ?? [:]
    }

    func saveSnapshot(_ snapshot: [String: SubSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.snapshotKey)
    }
}
