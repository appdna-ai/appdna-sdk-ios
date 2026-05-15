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
    case providerNotAvailable(String)

    public var errorDescription: String? {
        switch self {
        case .productNotFound(let id): return "Product not found: \(id)"
        case .verificationFailed: return "Transaction verification failed"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .serverError(let msg): return "Server error: \(msg)"
        case .providerNotAvailable(let msg): return msg
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
    ///
    /// `appAccountToken` (when supplied) is attached to the StoreKit
    /// transaction via `.appAccountToken(...)` so the transaction is bound
    /// to the current app user — preventing the cross-account leak where a
    /// later user signed in on the same device could otherwise see this
    /// transaction in `Transaction.currentEntitlements`. If `nil`, the
    /// resolver falls back to the currently-identified user (via
    /// `AppAccountTokenResolver.tokenForCurrentUser()`); if no user has
    /// identified yet the purchase still proceeds untagged (with a warning),
    /// preserving pre-identify first-launch behaviour.
    public func purchase(
        productId: String,
        offer: PromotionalOfferPayload? = nil,
        appAccountToken: UUID? = nil
    ) async throws -> BillingResult {
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
        // Per-user binding token: explicit caller token wins; otherwise
        // derive from the currently-identified user.
        let resolvedToken = appAccountToken ?? AppAccountTokenResolver.tokenForCurrentUser()
        if let token = resolvedToken {
            options.insert(.appAccountToken(token))
        } else {
            Log.warning("NativeBillingManager.purchase: no appAccountToken — host should call AppDNA.identify(userId:) BEFORE purchase to avoid cross-account entitlement leaks.")
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

    /// SPEC-401 Fix 1D — silent entitlement-cache refresh.
    ///
    /// Reads `Transaction.currentEntitlements` and updates `EntitlementCache`
    /// in place — same conversion pattern as `restorePurchases()` but skips
    /// the heavy/visible parts: no `AppStore.sync()` network call, no
    /// `purchase_restored` event emission, no delegate callback. Designed
    /// for `AppDNA.identify` and host-driven post-auth refresh hooks where
    /// firing user-visible restore events would be wrong.
    ///
    /// Errors are swallowed and logged at warning level — callers must be
    /// able to chain without try/catch (identify is fire-and-forget). On
    /// failure the cache stays at whatever it was before; no state mutation.
    public func refreshEntitlementCache() async {
        do {
            // Per-user binding filter (see `EntitlementOwnerFilter`): only
            // transactions tagged with the currently-identified user's token
            // are collected — transactions tagged with a different user are
            // skipped (this is the cached/silent counterpart of the
            // `restorePurchases` defence below). When no user is yet
            // identified, the filter is permissive (anonymous policy).
            let expectedToken = AppAccountTokenResolver.tokenForCurrentUser()
            let transactions = await ownedJWSes(expectedToken: expectedToken, source: "refreshEntitlementCache")
            // Empty entitlements is a valid state (user has no past purchases)
            // — short-circuit before hitting the verifier so we don't make a
            // network call for nothing.
            guard !transactions.isEmpty else { return }
            let entitlements = try await receiptVerifier.restore(transactions: transactions)
            for entitlement in entitlements {
                entitlementCache.update(entitlement)
            }
        } catch {
            Log.warning("refreshEntitlementCache: silent refresh failed — \(error.localizedDescription)")
        }
    }

    /// Restore purchases via AppStore.sync() and Transaction.currentEntitlements.
    ///
    /// Cross-account-leak defence: transactions tagged with a different
    /// user's `appAccountToken` are skipped (the device-level
    /// `Transaction.currentEntitlements` includes them, but they don't belong
    /// to the currently-identified app user). Untagged historical transactions
    /// are granted under the migration-tolerant policy and surfaced to the
    /// server-side `receiptVerifier.restore(...)` for ownership claiming.
    public func restorePurchases() async throws -> [ServerEntitlement] {
        try await AppStore.sync()

        let expectedToken = AppAccountTokenResolver.tokenForCurrentUser()
        let transactions = await ownedJWSes(expectedToken: expectedToken, source: "restorePurchases")

        let entitlements = try await receiptVerifier.restore(transactions: transactions)

        for entitlement in entitlements {
            entitlementCache.update(entitlement)
            AppDNA.track(event: "purchase_restored", properties: [
                "product_id": entitlement.productId,
            ])
        }

        return entitlements
    }

    // MARK: - Owner-filtered transaction reader (cross-account-leak defence)

    /// Iterate `Transaction.currentEntitlements`, apply the per-user
    /// ownership filter (`EntitlementOwnerFilter`), and return the verified
    /// JWS strings of the transactions that belong to the current user. The
    /// `source` parameter is used only for log breadcrumbs.
    ///
    /// Returns the JWS strings (not `Transaction` values) because both
    /// callers immediately ship them off to `receiptVerifier.restore(...)` —
    /// the server is the authoritative ownership store under the
    /// migration-tolerant policy.
    private func ownedJWSes(expectedToken: UUID?, source: String) async -> [String] {
        var owned: [String] = []
        // Resolve the first-identifier anchor once per call (see
        // `StoreKit2Bridge.restore` for the same pattern). Scopes the
        // `grantUntaggedMigration` carve-out to the device's first-identified
        // user so a later user-switch can't inherit untagged history.
        let firstIdentifier = AppAccountTokenResolver.firstIdentifiedToken()
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }
            switch EntitlementOwnerFilter.decide(
                transactionToken: tx.appAccountToken,
                expectedToken: expectedToken,
                firstIdentifiedToken: firstIdentifier
            ) {
            case .grant, .grantAnonymousPolicy:
                owned.append(result.jwsRepresentation)
            case .grantUntaggedMigration:
                Log.info("\(source): granting untagged historical transaction \(tx.id) to the device's first-identifier (migration-tolerant policy — server should claim ownership).")
                owned.append(result.jwsRepresentation)
            case .denyOtherUser:
                Log.warning("\(source): skipped transaction \(tx.id) — appAccountToken does not match the current user.")
            case .denyUntaggedOtherUser:
                Log.warning("\(source): skipped untagged transaction \(tx.id) — the current user is not the device's first-identifier, so the untagged history is not inherited (cross-account leak guard).")
            }
        }
        return owned
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
    ///
    /// **NOTE (v1.0.63):** `NativeBillingManager` is currently not wired in
    /// the active runtime path (the production billing surface goes through
    /// `BillingModule.bridge` → `StoreKit2Bridge` instead). The
    /// `EntitlementOwnerFilter` call below is kept in parity with the
    /// active read sites in `StoreKit2Bridge` so a future revival of this
    /// listener class doesn't silently reintroduce the cross-account-leak
    /// on auto-renewals (user A's renewal arriving while user B is logged
    /// in must NOT push user A's entitlement into user B's cache).
    public func listenForTransactionUpdates() {
        transactionListenerTask = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    // Per-user binding filter — see `EntitlementOwnerFilter`
                    // for the full decision matrix. A renewal arriving for
                    // user A's subscription while user B is identified
                    // MUST NOT update B's cache.
                    let expectedToken = AppAccountTokenResolver.tokenForCurrentUser()
                    let firstIdentifier = AppAccountTokenResolver.firstIdentifiedToken()
                    switch EntitlementOwnerFilter.decide(
                        transactionToken: transaction.appAccountToken,
                        expectedToken: expectedToken,
                        firstIdentifiedToken: firstIdentifier
                    ) {
                    case .denyOtherUser, .denyUntaggedOtherUser:
                        Log.warning("listenForTransactionUpdates: skipped transaction \(transaction.id) — does not belong to the current user.")
                        await transaction.finish()
                        continue
                    case .grant, .grantAnonymousPolicy, .grantUntaggedMigration:
                        break
                    }
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
