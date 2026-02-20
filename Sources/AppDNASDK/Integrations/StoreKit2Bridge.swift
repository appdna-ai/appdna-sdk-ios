import Foundation
import StoreKit

/// Native StoreKit 2 billing bridge. Default fallback when RevenueCat is not available.
final class StoreKit2Bridge: BillingBridgeProtocol {

    func purchase(productId: String) async throws -> PurchaseResult {
        let products = try await Product.products(for: [productId])
        guard let product = products.first else {
            throw StoreKit2Error.productNotFound(productId)
        }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()

            return PurchaseResult(
                productId: product.id,
                transactionId: String(transaction.id),
                price: NSDecimalNumber(decimal: product.price).doubleValue,
                currency: product.priceFormatStyle.currencyCode ?? "USD",
                provider: "storekit2"
            )

        case .userCancelled:
            throw StoreKit2Error.userCancelled

        case .pending:
            throw StoreKit2Error.purchasePending

        @unknown default:
            throw StoreKit2Error.unknown
        }
    }

    func restore() async throws -> [String] {
        var restoredIds: [String] = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                restoredIds.append(transaction.productID)
            }
        }

        return restoredIds
    }

    func getEntitlements() async -> [String] {
        var entitlements: [String] = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                entitlements.append(transaction.productID)
            }
        }

        return entitlements
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKit2Error.verificationFailed
        case .verified(let value):
            return value
        }
    }
}

// MARK: - Errors

enum StoreKit2Error: LocalizedError {
    case productNotFound(String)
    case userCancelled
    case purchasePending
    case verificationFailed
    case unknown

    var errorDescription: String? {
        switch self {
        case .productNotFound(let id): return "Product not found: \(id)"
        case .userCancelled: return "Purchase was cancelled"
        case .purchasePending: return "Purchase is pending approval"
        case .verificationFailed: return "Transaction verification failed"
        case .unknown: return "Unknown purchase error"
        }
    }
}
