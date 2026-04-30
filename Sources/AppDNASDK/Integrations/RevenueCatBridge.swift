import Foundation

#if canImport(RevenueCat)
import RevenueCat

/// RevenueCat billing bridge. Wraps RevenueCat Purchases SDK and auto-tracks events.
final class RevenueCatBridge: NSObject, BillingBridgeProtocol {
    private let eventTracker: EventTracker

    init(eventTracker: EventTracker) {
        self.eventTracker = eventTracker
        super.init()

        // Observe RevenueCat purchase delegate
        Purchases.shared.delegate = self
    }

    func purchase(productId: String) async throws -> PurchaseResult {
        let offerings: Offerings
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            await fireBillingPurchaseFailed(productId: productId, error: error)
            throw error
        }
        guard let package = offerings.all.values
            .flatMap(\.availablePackages)
            .first(where: { $0.storeProduct.productIdentifier == productId }) else {
            let err = RevenueCatError.productNotFound(productId)
            await fireBillingPurchaseFailed(productId: productId, error: err)
            throw err
        }

        let customerInfo: CustomerInfo
        do {
            (_, customerInfo, _) = try await Purchases.shared.purchase(package: package)
        } catch {
            await fireBillingPurchaseFailed(productId: productId, error: error)
            throw error
        }

        let product = package.storeProduct
        // SPEC-400 — fire onPurchaseCompleted to the host's
        // AppDNABillingDelegate. The PurchasesDelegate.receivedUpdated
        // callback below also fires for entitlement changes, but is
        // not 1:1 with purchases (it fires on restore + cross-device
        // sync too) and only emits an analytics event, never the
        // billing delegate. SPEC-400 single-source-of-truth: every
        // purchase produces exactly one onPurchaseCompleted call from
        // the bridge that drove it.
        let txInfo = TransactionInfo(
            transactionId: customerInfo.originalAppUserId,
            productId: product.productIdentifier,
            purchaseDate: Date(),
            environment: "production"
        )
        await MainActor.run {
            AppDNA.billingDelegate?.onPurchaseCompleted(productId: product.productIdentifier, transaction: txInfo)
        }

        return PurchaseResult(
            productId: product.productIdentifier,
            transactionId: customerInfo.originalAppUserId,
            price: NSDecimalNumber(decimal: product.price).doubleValue,
            currency: product.currencyCode ?? "USD",
            provider: "revenuecat"
        )
    }

    func restore() async throws -> [String] {
        let customerInfo = try await Purchases.shared.restorePurchases()
        let restoredIds = Array(customerInfo.entitlements.active.keys)
        // SPEC-400 — fire onRestoreCompleted.
        await MainActor.run {
            AppDNA.billingDelegate?.onRestoreCompleted(restoredProducts: restoredIds)
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
        guard let info = try? await Purchases.shared.customerInfo() else { return [] }
        return Array(info.entitlements.active.keys)
    }
}

extension RevenueCatBridge: PurchasesDelegate {
    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        // Auto-track entitlement changes
        let activeEntitlements = Array(customerInfo.entitlements.active.keys)
        if !activeEntitlements.isEmpty {
            eventTracker.track(event: "purchase_completed", properties: [
                "provider": "revenuecat",
                "entitlements": activeEntitlements,
            ])
        }
    }
}

enum RevenueCatError: LocalizedError {
    case productNotFound(String)

    var errorDescription: String? {
        switch self {
        case .productNotFound(let id): return "RevenueCat product not found: \(id)"
        }
    }
}

#else

/// Stub when RevenueCat is not available. Should never be instantiated at runtime
/// (AppDNA.swift falls back to StoreKit2Bridge).
final class RevenueCatBridge: BillingBridgeProtocol {
    private let eventTracker: EventTracker

    init(eventTracker: EventTracker) {
        self.eventTracker = eventTracker
        Log.warning("RevenueCat module not available — RevenueCatBridge is a no-op stub")
    }

    func purchase(productId: String) async throws -> PurchaseResult {
        throw BillingError.providerNotAvailable("RevenueCat is not available. Install the RevenueCat SDK or use native StoreKit.")
    }

    func restore() async throws -> [String] {
        throw BillingError.providerNotAvailable("RevenueCat is not available. Install the RevenueCat SDK or use native StoreKit.")
    }

    func getEntitlements() async -> [String] {
        return []
    }
}

#endif
