import Foundation
import StoreKit

/// The ONE place a *successful purchase* becomes analytics on iOS.
///
/// 🔴 **`subscription_started` was a metered event that no SDK emitted.**
/// `BigQueryBillingService` meters MTPU over
/// `event_name IN ('purchase_completed', 'subscription_started', 'subscription_renewed')` — iOS,
/// Android, Flutter and RN had ZERO emit sites for the middle one. The only production rows carrying
/// that name were seeded demo data. Nothing downstream could separate a NEW SUBSCRIPTION from a
/// one-off / consumable / lifetime purchase, so every subscription funnel built on it was fiction.
///
/// The rule, and it is the whole reason this type exists:
///   - EVERY successful purchase emits `purchase_completed` (unchanged — this is additive).
///   - A purchase of an AUTO-RENEWING product ALSO emits `subscription_started`, once, with the SAME
///     property envelope.
///   - A one-off product emits `purchase_completed` and nothing else.
///
/// `subscription_started` is a PURCHASE-TIME event. It is deliberately NOT emitted from
/// `SubscriptionStatusObserver`: that class owns the renewal/reconcile diff, and a product that is new
/// to its snapshot is explicitly not its business ("that is `purchase_completed`'s job — emitting here
/// too is how you get the double-count Android had on its purchase events"). Emitting here as well
/// would double-count the first pass after every purchase — on the single most-metered event family.
enum PurchaseSuccessEvents {

    /// The property envelope shared by `purchase_completed` and `subscription_started`.
    ///
    /// Byte-identical between the two events on purpose: a funnel that joins them on `product_id` /
    /// `paywall_id` / `experiment_id` must not have to special-case one of them. Property names are the
    /// ones `purchase_completed` already shipped (`paywall_id`, `product_id`, `price`, `currency`,
    /// `provider`) — this builder is a *reuse* of that shape, not a new one.
    static func properties(
        paywallId: String?,
        result: PurchaseResult,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var props: [String: Any] = [
            "product_id": result.productId,
            "price": result.price,
            "currency": result.currency,
            "provider": result.provider,
        ]
        // Omitted rather than fabricated on the non-paywall paths (a direct/host-driven purchase has no
        // paywall), matching what those call sites emitted before.
        if let paywallId {
            props["paywall_id"] = paywallId
        }
        for (key, value) in extra {
            props[key] = value
        }
        return props
    }

    /// Emit `purchase_completed` and — only for an auto-renewing product — `subscription_started`.
    ///
    /// Exactly one of each, from the one site that observed the purchase.
    static func emit(
        tracker: EventTracker,
        paywallId: String?,
        result: PurchaseResult,
        extra: [String: Any] = [:]
    ) {
        let props = properties(paywallId: paywallId, result: result, extra: extra)
        tracker.track(event: "purchase_completed", properties: props)
        guard result.isSubscription else { return }
        tracker.track(event: "subscription_started", properties: props)
    }

    /// Does the App Store consider this product auto-renewing?
    ///
    /// Used by bridges whose provider model does not expose the product type at the emit site
    /// (`AdaptyBridge`). StoreKit is the same source of truth the store itself bills against, so the
    /// answer is provider-independent. Best-effort: a failed product lookup answers `false` rather than
    /// fabricating a subscription (an over-emit here would inflate a metered event).
    static func isAutoRenewable(productId: String) async -> Bool {
        guard let product = try? await Product.products(for: [productId]).first else {
            Log.warning("PurchaseSuccessEvents: product lookup failed for \(productId) — treating as non-subscription for subscription_started")
            return false
        }
        return product.subscription != nil
    }
}
