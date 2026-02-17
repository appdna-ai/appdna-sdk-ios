import Foundation
#if canImport(Adapty)
import Adapty
#endif

/// Adapty SDK billing bridge implementation.
/// Wraps Adapty SDK calls and maps models to AppDNA's billing types.
///
/// Usage: Configure via `AppDNA.configure(billing: .adapty(apiKey: "..."))`
///
/// Requires Adapty SDK to be available (conditionally imported).
/// If Adapty is not linked, this bridge logs a warning and returns empty results.
final class AdaptyBridge: BillingBridgeProtocol {
    private let apiKey: String
    private weak var eventTracker: EventTracker?
    private var isActivated = false

    init(apiKey: String, eventTracker: EventTracker?) {
        self.apiKey = apiKey
        self.eventTracker = eventTracker
        activate()
    }

    private func activate() {
        #if canImport(Adapty)
        Adapty.activate(apiKey)
        isActivated = true
        Log.info("Adapty bridge activated")
        #else
        Log.warning("Adapty SDK not available — billing operations will return empty results")
        #endif
    }

    // MARK: - BillingBridgeProtocol

    func purchase(productId: String) async throws -> PurchaseResult {
        eventTracker?.track(event: "purchase_started", properties: [
            "product_id": productId,
            "provider": "adapty",
        ])

        #if canImport(Adapty)
        do {
            let result = try await Adapty.makePurchase(product: productId)
            let purchaseResult = PurchaseResult(
                productId: productId,
                transactionId: result.transactionId ?? UUID().uuidString,
                price: result.price ?? 0,
                currency: result.currencyCode ?? "USD",
                provider: "adapty"
            )
            eventTracker?.track(event: "purchase_completed", properties: [
                "product_id": productId,
                "price": purchaseResult.price,
                "currency": purchaseResult.currency,
                "provider": "adapty",
            ])
            return purchaseResult
        } catch {
            eventTracker?.track(event: "purchase_failed", properties: [
                "product_id": productId,
                "error": error.localizedDescription,
                "provider": "adapty",
            ])
            throw error
        }
        #else
        // Stub: Adapty not available
        throw NSError(
            domain: "ai.appdna.sdk",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Adapty SDK not linked"]
        )
        #endif
    }

    func restore() async throws -> [String] {
        #if canImport(Adapty)
        let profile = try await Adapty.restorePurchases()
        let ids = profile.accessLevels.filter(\.value.isActive).map(\.key)
        eventTracker?.track(event: "purchase_restored", properties: [
            "restored_count": ids.count,
            "provider": "adapty",
        ])
        return ids
        #else
        return []
        #endif
    }

    func getEntitlements() async -> [String] {
        #if canImport(Adapty)
        do {
            let profile = try await Adapty.getProfile()
            return profile.accessLevels.filter(\.value.isActive).map(\.key)
        } catch {
            Log.error("Adapty getEntitlements failed: \(error.localizedDescription)")
            return []
        }
        #else
        return []
        #endif
    }
}
