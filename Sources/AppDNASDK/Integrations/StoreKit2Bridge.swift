import Foundation
import StoreKit

/// Native StoreKit 2 billing bridge. Default fallback when RevenueCat is not available.
final class StoreKit2Bridge: BillingBridgeProtocol {

    func purchase(
        productId: String,
        appAccountToken: UUID?
    ) async throws -> PurchaseResult {
        let products = try await Product.products(for: [productId])
        guard let product = products.first else {
            let err = StoreKit2Error.productNotFound(productId)
            await fireBillingPurchaseFailed(productId: productId, error: err)
            throw err
        }

        // Bind the resulting transaction to the current app user (Apple
        // surfaces it on `Transaction.appAccountToken` and in App Store
        // Server-Server notifications, so the binding survives renewals).
        // `nil` token = host has not identified a user — proceed untagged,
        // preserving pre-identify first-launch behaviour, but log it so the
        // app developer can see it during integration.
        var options: Set<Product.PurchaseOption> = []
        if let token = appAccountToken {
            options.insert(.appAccountToken(token))
        } else {
            Log.warning("StoreKit2Bridge.purchase: no appAccountToken — host should call AppDNA.identify(userId:) BEFORE purchase to avoid cross-account entitlement leaks.")
        }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase(options: options)
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

    func restore(appAccountToken: UUID?) async throws -> [String] {
        var restoredIds: [String] = []

        // Resolve the first-identifier anchor ONCE per restore call so the
        // decision matrix below sees a stable value across all transactions
        // even if the host identifies a different user mid-iteration.
        let firstIdentifier = AppAccountTokenResolver.firstIdentifiedToken()

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            // Per-user binding filter (see `EntitlementOwnerFilter`):
            // - tagged + matches current user → grant
            // - tagged + different user → DENY (cross-account leak guard)
            // - untagged + current user is the device's first-identifier
            //   → grant (migration-tolerant; legacy / pre-identify
            //   onboarding-paywall purchase)
            // - untagged + current user is NOT the first-identifier
            //   → DENY (the v1.0.62 leak close — was incorrectly granted)
            switch EntitlementOwnerFilter.decide(
                transactionToken: transaction.appAccountToken,
                expectedToken: appAccountToken,
                firstIdentifiedToken: firstIdentifier
            ) {
            case .grant, .grantAnonymousPolicy:
                restoredIds.append(transaction.productID)
            case .grantUntaggedMigration:
                Log.info("StoreKit2Bridge.restore: granting untagged historical transaction \(transaction.id) to the device's first-identifier (migration-tolerant policy — server should claim ownership).")
                restoredIds.append(transaction.productID)
            case .denyOtherUser:
                Log.warning("StoreKit2Bridge.restore: skipped transaction \(transaction.id) — appAccountToken does not match the current user.")
            case .denyUntaggedOtherUser:
                Log.warning("StoreKit2Bridge.restore: skipped untagged transaction \(transaction.id) — the current user is not the device's first-identifier, so the untagged history is not inherited (cross-account leak guard).")
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

    func getEntitlements(appAccountToken: UUID?) async -> [String] {
        var entitlements: [String] = []

        // See `restore(...)` above for the rationale on resolving the
        // first-identifier anchor once at the top of the read loop.
        let firstIdentifier = AppAccountTokenResolver.firstIdentifiedToken()

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            // Same per-user binding filter as `restore` above — see
            // `EntitlementOwnerFilter` for the full decision matrix.
            switch EntitlementOwnerFilter.decide(
                transactionToken: transaction.appAccountToken,
                expectedToken: appAccountToken,
                firstIdentifiedToken: firstIdentifier
            ) {
            case .grant, .grantAnonymousPolicy, .grantUntaggedMigration:
                entitlements.append(transaction.productID)
            case .denyOtherUser:
                Log.warning("StoreKit2Bridge.getEntitlements: skipped transaction \(transaction.id) — appAccountToken does not match the current user.")
            case .denyUntaggedOtherUser:
                Log.warning("StoreKit2Bridge.getEntitlements: skipped untagged transaction \(transaction.id) — the current user is not the device's first-identifier, so the untagged history is not inherited (cross-account leak guard).")
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
