import Foundation
import Compression
import UIKit

/// URL request errors.
enum APIError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, data: Data?)
    case networkError(Error)
    case decodingError(Error)
    case compressionError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .httpError(let statusCode, let data):
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no body"
            return "HTTP \(statusCode): \(body)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .compressionError:
            return "Compression error"
        }
    }
}

/// URLSession-based HTTP client with retry and auth headers.
final class APIClient {
    let apiKey: String
    let environment: Environment
    private let session: URLSession
    private let maxRetries = 3
    private let retryDelays: [TimeInterval] = [1, 2, 4]

    /// Set to true when event upload gets a 4xx (retrying won't help).
    private(set) var eventUploadPermanentlyFailed = false

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
                case .sandbox:    base = "https://api.appdna.ai"
                }
                guard let url = URL(string: base + path) else {
                    completion?(.failure(APIError.invalidURL))
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
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

    /// Fire-and-forget POST for event batches with gzip compression. Returns success status.
    func sendEvents(_ data: Data) async -> Bool {
        do {
            var urlRequest = try buildRequest(for: .ingestEvents)

            // SPEC-067: Compress event batch for bandwidth reduction
            if let compressed = Self.deflateCompress(data) {
                urlRequest.httpBody = compressed
                urlRequest.setValue("deflate", forHTTPHeaderField: "Content-Encoding")
                Log.debug("Compressed events: \(data.count) → \(compressed.count) bytes (\(String(format: "%.1f", Double(data.count) / max(Double(compressed.count), 1)))x)")
            } else {
                urlRequest.httpBody = data
                Log.warning("Compression failed, sending uncompressed")
            }

            let (responseData, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            let statusCode = httpResponse.statusCode
            if (200..<300).contains(statusCode) {
                eventUploadPermanentlyFailed = false
                return true
            }
            // Log the failure reason
            let body = String(data: responseData.prefix(500), encoding: .utf8) ?? "no body"
            if statusCode == 401 {
                Log.error("Event upload rejected: HTTP 401 — Invalid API key. Check your key in Console → Settings → SDK. Retrying won't help.")
                eventUploadPermanentlyFailed = true
            } else if (400..<500).contains(statusCode) {
                Log.error("Event upload rejected: HTTP \(statusCode) — \(body). Retrying won't help.")
                eventUploadPermanentlyFailed = true
            } else {
                Log.warning("Event upload failed: HTTP \(statusCode) — \(body). Will retry.")
            }
            return false
        } catch {
            Log.error("Event upload network error: \(error.localizedDescription). Will retry.")
            return false
        }
    }

    // MARK: - User Agent

    /// Cached user agent string using ProcessInfo to avoid MainActor-isolated UIDevice access.
    private static let userAgent: String = {
        let sdkVersion = AppDNA.sdkVersion
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let osVersionString = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        return "AppDNASDK/\(sdkVersion) iOS/\(osVersionString)"
    }()

    private func buildRequest(for endpoint: Endpoint) throws -> URLRequest {
        guard let url = endpoint.url(environment: environment) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        // SPEC-067: Request compressed responses from server
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")

        if endpoint.method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Serialize body from endpoint if present
        if let body = endpoint.body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    // MARK: - SPEC-067: Deflate Compression

    /// Compress data using raw deflate via Apple's Compression framework (no zlib dependency).
    static func deflateCompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        // Allocate a destination buffer (worst case: slightly larger than input)
        let destinationSize = data.count + 64
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { sourceRaw -> Int in
            guard let sourcePtr = sourceRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return compression_encode_buffer(
                destinationBuffer, destinationSize,
                sourcePtr, data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: compressedSize)
    }
}
