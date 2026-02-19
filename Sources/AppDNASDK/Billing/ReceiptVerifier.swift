import Foundation

/// Server-side receipt verification response.
struct VerifyResponse: Codable {
    let data: EntitlementResult

    struct EntitlementResult: Codable {
        let entitled: Bool
        let subscription: SubscriptionData
    }

    struct SubscriptionData: Codable {
        let product_id: String
        let store: String
        let status: String
        let current_period_end: String?
        let offer_applied: OfferApplied?
    }

    struct OfferApplied: Codable {
        let offer_type: String?
    }
}

struct RestoreResponse: Codable {
    let data: [EntitlementData]

    struct EntitlementData: Codable {
        let product_id: String
        let store: String
        let status: String
        let current_period_end: String?
        let offer_applied: OfferApplied?
    }

    struct OfferApplied: Codable {
        let offer_type: String?
    }
}

/// Handles server-side receipt verification via AppDNA API.
class ReceiptVerifier {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func verify(signedTransaction: String, platform: String, paywallId: String?, experimentId: String?) async throws -> ServerEntitlement {
        var body: [String: Any] = [
            "platform": platform,
            "transaction": signedTransaction,
        ]
        if let paywallId = paywallId { body["paywall_id"] = paywallId }
        if let experimentId = experimentId { body["experiment_id"] = experimentId }

        let response: VerifyResponse = try await apiClient.request(.verifyReceipt(body: body))

        return ServerEntitlement(
            productId: response.data.subscription.product_id,
            store: response.data.subscription.store,
            status: response.data.subscription.status,
            expiresAt: response.data.subscription.current_period_end,
            isTrial: response.data.subscription.status == "trialing",
            offerType: response.data.subscription.offer_applied?.offer_type
        )
    }

    func restore(transactions: [String]) async throws -> [ServerEntitlement] {
        let body: [String: Any] = [
            "platform": "ios",
            "transactions": transactions,
        ]

        let response: RestoreResponse = try await apiClient.request(.restorePurchases(body: body))

        return response.data.map { data in
            ServerEntitlement(
                productId: data.product_id,
                store: data.store,
                status: data.status,
                expiresAt: data.current_period_end,
                isTrial: data.status == "trialing",
                offerType: data.offer_applied?.offer_type
            )
        }
    }
}
