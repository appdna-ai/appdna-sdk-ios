import Foundation

/// Payload for a signed promotional offer.
public struct PromotionalOfferPayload: Codable {
    public let offerId: String
    public let keyId: String
    public let nonce: String
    public let timestamp: Int
    public let signature: String
}

struct SignOfferResponse: Codable {
    let data: PromotionalOfferPayload
}

/// Requests signed promotional offers from the AppDNA backend.
class PromotionalOfferHandler {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func getSignedOffer(offerId: String, productId: String) async throws -> PromotionalOfferPayload {
        let body: [String: Any] = [
            "offerId": offerId,
            "productId": productId,
        ]
        let response: SignOfferResponse = try await apiClient.request(.signOffer(body: body))
        return response.data
    }
}
