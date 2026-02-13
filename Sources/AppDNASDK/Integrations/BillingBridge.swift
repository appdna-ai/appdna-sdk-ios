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
protocol BillingBridgeProtocol {
    /// Purchase a product by its App Store product ID.
    func purchase(productId: String) async throws -> PurchaseResult

    /// Restore previously purchased products. Returns restored product IDs.
    func restore() async throws -> [String]

    /// Get current active entitlements.
    func getEntitlements() async -> [String]
}
