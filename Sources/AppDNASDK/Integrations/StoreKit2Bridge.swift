import Foundation
import StoreKit

/// Native StoreKit 2 billing bridge. Default fallback when RevenueCat is not available.
final class StoreKit2Bridge: BillingBridgeProtocol {

    func purchase(productId: String) async throws -> PurchaseResult {
        let products = try await Product.products(for: [productId])
        guard let product = products.first else {
            let err = StoreKit2Error.productNotFound(productId)
            await fireBillingPurchaseFailed(productId: productId, error: err)
            throw err
        }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase()
        } catch {
            await fireBillingPurchaseFailed(productId: productId, error: error)
            throw error
        }

        switch result {
        case .success(let verification):
            let transaction: Transaction
            do {
                transaction = try checkVerified(verification)
            } catch {
                await fireBillingPurchaseFailed(productId: productId, error: error)
                throw error
            }
            await transaction.finish()

            // SPEC-400 — fire onPurchaseCompleted to the host's
            // registered AppDNABillingDelegate. Single source of truth
            // for billing-delegate purchase callbacks; PaywallManager
            // does NOT fire here, so each successful purchase produces
            // exactly one onPurchaseCompleted invocation.
            let txInfo = TransactionInfo(
                transactionId: String(transaction.id),
                productId: product.id,
                purchaseDate: transaction.purchaseDate,
                environment: "production"
            )
            await MainActor.run {
                AppDNA.billingDelegate?.onPurchaseCompleted(productId: product.id, transaction: txInfo)
            }

            return PurchaseResult(
                productId: product.id,
                transactionId: String(transaction.id),
                price: NSDecimalNumber(decimal: product.price).doubleValue,
                currency: product.priceFormatStyle.currencyCode ?? "USD",
                provider: "storekit2"
            )

        case .userCancelled:
            let err = StoreKit2Error.userCancelled
            await fireBillingPurchaseFailed(productId: productId, error: err)
            throw err

        case .pending:
            let err = StoreKit2Error.purchasePending
            await fireBillingPurchaseFailed(productId: productId, error: err)
            throw err

        @unknown default:
            let err = StoreKit2Error.unknown
            await fireBillingPurchaseFailed(productId: productId, error: err)
            throw err
        }
    }

    func restore() async throws -> [String] {
        var restoredIds: [String] = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                restoredIds.append(transaction.productID)
            }
        }

        // SPEC-400 — fire onRestoreCompleted alongside the return.
        let ids = restoredIds
        await MainActor.run {
            AppDNA.billingDelegate?.onRestoreCompleted(restoredProducts: ids)
        }

        return restoredIds
    }

    /// SPEC-400 — single helper for the purchase-failure delegate fan-out.
    private func fireBillingPurchaseFailed(productId: String, error: Error) async {
        await MainActor.run {
            AppDNA.billingDelegate?.onPurchaseFailed(productId: productId, error: error)
        }
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
