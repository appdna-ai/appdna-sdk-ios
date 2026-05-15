import Foundation

/// Result of a completed purchase.
public struct PurchaseResult {
    public let productId: String
    public let transactionId: String
    public let price: Double
    public let currency: String
    public let provider: String
}

/// Protocol for billing provider integrations.
///
/// The `appAccountToken:` parameter is the per-user binding token used to
/// defend against the cross-account-entitlement-leak (User A buys → User B
/// signs in on the same device → B should NOT see A's subscription). It is
/// resolved from the currently-identified user (via
/// `AppAccountTokenResolver.tokenForCurrentUser()`) or supplied explicitly by
/// the caller. `nil` means "host has not identified a user yet" — bridges
/// MUST treat that as the legacy unfiltered path (preserves first-launch /
/// pre-identify behaviour).
protocol BillingBridgeProtocol {
    /// Purchase a product by its App Store product ID.
    /// `appAccountToken`, when non-nil, MUST be passed through to
    /// `Product.purchase(options: [.appAccountToken(token)])` so the resulting
    /// transaction is bound to the current user.
    func purchase(
        productId: String,
        appAccountToken: UUID?
    ) async throws -> PurchaseResult

    /// Restore previously purchased products. Returns restored product IDs.
    /// `appAccountToken`, when non-nil, MUST be used to filter entitlements:
    /// transactions tagged with a different token MUST be excluded
    /// (`EntitlementOwnerFilter`).
    func restore(appAccountToken: UUID?) async throws -> [String]

    /// Get current active entitlements. Same filtering contract as `restore`.
    func getEntitlements(appAccountToken: UUID?) async -> [String]
}

// MARK: - Back-compat conveniences

/// Default-nil overloads so existing call sites that don't yet thread a token
/// keep compiling. New call sites should always pass an explicit token.
extension BillingBridgeProtocol {
    func purchase(productId: String) async throws -> PurchaseResult {
        try await purchase(productId: productId, appAccountToken: nil)
    }
    func restore() async throws -> [String] {
        try await restore(appAccountToken: nil)
    }
    func getEntitlements() async -> [String] {
        await getEntitlements(appAccountToken: nil)
    }
}
