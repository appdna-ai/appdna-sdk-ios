import Foundation
import UIKit

/// URL request errors.
enum APIError: Error {
    case invalidURL
    case httpError(statusCode: Int, data: Data?)
    case networkError(Error)
    case decodingError(Error)
}

/// URLSession-based HTTP client with retry and auth headers.
final class APIClient {
    private let apiKey: String
    private let environment: Environment
    private let session: URLSession
    private let maxRetries = 3
    private let retryDelays: [TimeInterval] = [1, 2, 4]

    init(apiKey: String, environment: Environment) {
        self.apiKey = apiKey
        self.environment = environment

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    /// Execute a request with automatic retry on 5xx and network errors.
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let urlRequest = try buildRequest(for: endpoint)
        var lastError: Error?

        for attempt in 0...maxRetries {
            if attempt > 0 {
                let delay = retryDelays[min(attempt - 1, retryDelays.count - 1)]
                Log.debug("Retrying request (attempt \(attempt + 1)) after \(delay)s")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            do {
                let (data, response) = try await session.data(for: urlRequest)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.networkError(URLError(.badServerResponse))
                }

                let statusCode = httpResponse.statusCode

                if (200..<300).contains(statusCode) {
                    do {
                        let decoded = try JSONDecoder().decode(T.self, from: data)
                        return decoded
                    } catch {
                        throw APIError.decodingError(error)
                    }
                }

                // 4xx — client error, no retry
                if (400..<500).contains(statusCode) {
                    throw APIError.httpError(statusCode: statusCode, data: data)
                }

                // 5xx — server error, retry
                lastError = APIError.httpError(statusCode: statusCode, data: data)
                Log.warning("Server error \(statusCode), will retry")
            } catch let error as APIError {
                throw error // Don't retry decoding or 4xx errors
            } catch {
                // Network error — retry
                lastError = APIError.networkError(error)
                Log.warning("Network error: \(error.localizedDescription), will retry")
            }
        }

        throw lastError ?? APIError.networkError(URLError(.unknown))
    }

    /// Fire-and-forget POST with JSON body. Callback with success/error.
    func post(path: String, body: [String: Any], completion: ((Result<Void, Error>) -> Void)? = nil) {
        Task {
            do {
                let base: String
                switch environment {
                case .production: base = "https://api.appdna.ai"
                case .sandbox:    base = "https://sandbox-api.appdna.ai"
                }
                guard let url = URL(string: base + path) else {
                    completion?(.failure(APIError.invalidURL))
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(
                    "AppDNASDK/\(AppDNA.sdkVersion) iOS/\(UIDevice.current.systemVersion)",
                    forHTTPHeaderField: "User-Agent"
                )
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (_, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    completion?(.failure(APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, data: nil)))
                    return
                }
                completion?(.success(()))
            } catch {
                completion?(.failure(error))
            }
        }
    }

    /// Fire-and-forget POST for event batches. Returns success status.
    func sendEvents(_ data: Data) async -> Bool {
        do {
            var urlRequest = try buildRequest(for: .ingestEvents)
            urlRequest.httpBody = data

            let (_, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            Log.error("Failed to send events: \(error.localizedDescription)")
            return false
        }
    }

    private func buildRequest(for endpoint: Endpoint) throws -> URLRequest {
        guard let url = endpoint.url(environment: environment) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(
            "AppDNASDK/\(AppDNA.sdkVersion) iOS/\(UIDevice.current.systemVersion)",
            forHTTPHeaderField: "User-Agent"
        )

        if endpoint.method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Serialize body from endpoint if present
        if let body = endpoint.body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }
}
