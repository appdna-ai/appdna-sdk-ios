import Foundation

/// API endpoint definitions.
enum Endpoint {
    case bootstrap
    case ingestEvents
    case ingestIdentify
    // Billing endpoints
    case verifyReceipt(body: [String: Any])
    case restorePurchases(body: [String: Any])
    case getEntitlements
    case signOffer(body: [String: Any])

    var path: String {
        switch self {
        case .bootstrap:        return "/api/v1/sdk/bootstrap"
        case .ingestEvents:     return "/api/v1/ingest/events"
        case .ingestIdentify:   return "/api/v1/ingest/identify"
        case .verifyReceipt:    return "/api/v1/billing/verify"
        case .restorePurchases: return "/api/v1/billing/restore"
        case .getEntitlements:  return "/api/v1/billing/entitlements"
        case .signOffer:        return "/api/v1/billing/offers/sign"
        }
    }

    var method: String {
        switch self {
        case .bootstrap:        return "GET"
        case .ingestEvents:     return "POST"
        case .ingestIdentify:   return "POST"
        case .verifyReceipt:    return "POST"
        case .restorePurchases: return "POST"
        case .getEntitlements:  return "GET"
        case .signOffer:        return "POST"
        }
    }

    /// JSON body for POST endpoints that carry associated data.
    var body: [String: Any]? {
        switch self {
        case .verifyReceipt(let body):    return body
        case .restorePurchases(let body):  return body
        case .signOffer(let body):         return body
        default:                           return nil
        }
    }

    func url(environment: Environment) -> URL? {
        let base: String
        switch environment {
        case .production: base = "https://api.appdna.ai"
        case .sandbox:    base = "https://sandbox-api.appdna.ai"
        }
        return URL(string: base + path)
    }
}
