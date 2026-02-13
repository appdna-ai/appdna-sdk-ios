import Foundation

/// API endpoint definitions.
enum Endpoint {
    case bootstrap
    case ingestEvents
    case ingestIdentify

    var path: String {
        switch self {
        case .bootstrap:      return "/api/v1/sdk/bootstrap"
        case .ingestEvents:   return "/api/v1/ingest/events"
        case .ingestIdentify: return "/api/v1/ingest/identify"
        }
    }

    var method: String {
        switch self {
        case .bootstrap:      return "GET"
        case .ingestEvents:   return "POST"
        case .ingestIdentify: return "POST"
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
