import Foundation
import StoreKit

/// ServerEntitlement model returned from server verification.
public struct ServerEntitlement: Codable {
    public let productId: String
    public let store: String
    public let status: String
    public let expiresAt: String?
    public let isTrial: Bool
    public let offerType: String?
}

/// Result of a billing operation.
public enum BillingResult {
    case purchased(ServerEntitlement)
    case cancelled
    case pending
    case unknown
}

/// Errors from billing operations.
public enum BillingError: LocalizedError {
    case productNotFound(String)
    case verificationFailed
    case networkError(Error)
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .productNotFound(let id): return "Product not found: \(id)"
        case .verificationFailed: return "Transaction verification failed"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .serverError(let msg): return "Server error: \(msg)"
        }
    }
}

/// Product info from StoreKit.
public struct ProductInfo {
    public let id: String
    public let displayName: String
    public let description: String
    public let price: Decimal
    public let displayPrice: String
    public let subscription: SubscriptionInfo?
}

public struct SubscriptionInfo {
    public let period: Product.SubscriptionPeriod
    public let introOffer: Product.SubscriptionOffer?
    public let isEligibleForIntroOffer: Bool
}

/// Manages native StoreKit 2 purchases with server-side verification.
public class NativeBillingManager {
    private let receiptVerifier: ReceiptVerifier
    private let entitlementCache: EntitlementCache
    private var transactionListenerTask: Task<Void, Never>?
    var currentPaywallId: String?
    var currentExperimentId: String?

    init(receiptVerifier: ReceiptVerifier, entitlementCache: EntitlementCache) {
        self.receiptVerifier = receiptVerifier
        self.entitlementCache = entitlementCache
    }

    /// Purchase a product via StoreKit 2, verify server-side.
    public func purchase(productId: String, offer: PromotionalOfferPayload? = nil) async throws -> BillingResult {
        // Track purchase_started event
        AppDNA.track(event: "purchase_started", properties: [
            "product_id": productId,
            "paywall_id": currentPaywallId ?? "",
            "experiment_id": currentExperimentId ?? "",
        ])

        let products: [Product]
        do {
            products = try await Product.products(for: [productId])
        } catch {
            AppDNA.track(event: "purchase_failed", properties: [
                "product_id": productId,
                "error": error.localizedDescription,
                "paywall_id": currentPaywallId ?? "",
            ])
            throw error
        }
        guard let product = products.first else {
            let err = BillingError.productNotFound(productId)
            AppDNA.track(event: "purchase_failed", properties: [
                "product_id": productId,
                "error": err.localizedDescription,
                "paywall_id": currentPaywallId ?? "",
            ])
            throw err
        }

        var options: Set<Product.PurchaseOption> = []
        if let offer = offer {
            options.insert(.promotionalOffer(
                offerID: offer.offerId,
                keyID: offer.keyId,
                nonce: UUID(uuidString: offer.nonce) ?? UUID(),
                signature: Data(base64Encoded: offer.signature) ?? Data(),
                timestamp: offer.timestamp
            ))
        }

        let result: Product.PurchaseResult
        do {
            result = try await product.purchase(options: options)
        } catch {
            AppDNA.track(event: "purchase_failed", properties: [
                "product_id": productId,
                "error": error.localizedDescription,
                "paywall_id": currentPaywallId ?? "",
                "experiment_id": currentExperimentId ?? "",
            ])
            throw error
        }

        switch result {
        case .success(let verification):
            let signedJWS = verification.jwsRepresentation
            let transaction: Transaction
            do {
                transaction = try checkVerified(verification)
            } catch {
                AppDNA.track(event: "purchase_failed", properties: [
                    "product_id": productId,
                    "error": "verification_failed",
                    "paywall_id": currentPaywallId ?? "",
                ])
                throw error
            }

            // Verify server-side
            let entitlement = try await receiptVerifier.verify(
                signedTransaction: signedJWS,
                platform: "ios",
                paywallId: currentPaywallId,
                experimentId: currentExperimentId
            )

            // Finish transaction
            await transaction.finish()

            // Update local cache
            entitlementCache.update(entitlement)

            // Track purchase_completed
            AppDNA.track(event: "purchase_completed", properties: [
                "product_id": productId,
                "price": NSDecimalNumber(decimal: product.price).doubleValue,
                "currency": product.priceFormatStyle.currencyCode ?? "USD",
                "paywall_id": currentPaywallId ?? "",
                "experiment_id": currentExperimentId ?? "",
                "is_trial": entitlement.isTrial,
            ])

            return .purchased(entitlement)

        case .userCancelled:
            AppDNA.track(event: "purchase_canceled", properties: [
                "product_id": productId,
                "paywall_id": currentPaywallId ?? "",
            ])
            return .cancelled

        case .pending:
            AppDNA.track(event: "purchase_pending", properties: [
                "product_id": productId,
            ])
            return .pending

        @unknown default:
            return .unknown
        }
    }

    /// Restore purchases via AppStore.sync() and Transaction.currentEntitlements.
    public func restorePurchases() async throws -> [ServerEntitlement] {
        try await AppStore.sync()

        var transactions: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified = result {
                transactions.append(result.jwsRepresentation)
            }
        }

        let entitlements = try await receiptVerifier.restore(transactions: transactions)

        for entitlement in entitlements {
            entitlementCache.update(entitlement)
            AppDNA.track(event: "purchase_restored", properties: [
                "product_id": entitlement.productId,
            ])
        }

        return entitlements
    }

    /// Get localized product info from StoreKit.
    public func getProducts(productIds: [String]) async throws -> [ProductInfo] {
        let products = try await Product.products(for: Set(productIds))
        var result: [ProductInfo] = []
        for product in products {
            var subInfo: SubscriptionInfo?
            if let sub = product.subscription {
                let eligible = await sub.isEligibleForIntroOffer
                subInfo = SubscriptionInfo(
                    period: sub.subscriptionPeriod,
                    introOffer: sub.introductoryOffer,
                    isEligibleForIntroOffer: eligible
                )
            }
            result.append(ProductInfo(
                id: product.id,
                displayName: product.displayName,
                description: product.description,
                price: product.price,
                displayPrice: product.displayPrice,
                subscription: subInfo
            ))
        }
        return result
    }

    /// Start listening for transaction updates (renewals, revocations).
    public func listenForTransactionUpdates() {
        transactionListenerTask = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    let signedJWS = result.jwsRepresentation
                    do {
                        let entitlement = try await receiptVerifier.verify(
                            signedTransaction: signedJWS,
                            platform: "ios",
                            paywallId: nil,
                            experimentId: nil
                        )
                        await transaction.finish()
                        entitlementCache.update(entitlement)
                    } catch {
                        Log.error("Failed to verify transaction update: \(error)")
                    }
                }
            }
        }
    }

    func stopListening() {
        transactionListenerTask?.cancel()
        transactionListenerTask = nil
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw BillingError.verificationFailed
        case .verified(let value):
            return value
        }
    }
}
