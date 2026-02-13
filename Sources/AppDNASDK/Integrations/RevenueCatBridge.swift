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
        let offerings = try await Purchases.shared.offerings()
        guard let package = offerings.all.values
            .flatMap(\.availablePackages)
            .first(where: { $0.storeProduct.productIdentifier == productId }) else {
            throw RevenueCatError.productNotFound(productId)
        }

        let (_, customerInfo, _) = try await Purchases.shared.purchase(package: package)

        let product = package.storeProduct
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
        return Array(customerInfo.entitlements.active.keys)
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
        fatalError("RevenueCat is not available. Use StoreKit2Bridge instead.")
    }

    func restore() async throws -> [String] {
        fatalError("RevenueCat is not available. Use StoreKit2Bridge instead.")
    }

    func getEntitlements() async -> [String] {
        return []
    }
}

#endif
