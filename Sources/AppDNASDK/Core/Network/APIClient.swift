import Foundation
import UIKit
import Compression

/// URL request errors.
enum APIError: Error {
    case invalidURL
    case httpError(statusCode: Int, data: Data?)
    case networkError(Error)
    case decodingError(Error)
    case compressionError
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

    /// Fire-and-forget POST for event batches with gzip compression. Returns success status.
    func sendEvents(_ data: Data) async -> Bool {
        do {
            var urlRequest = try buildRequest(for: .ingestEvents)

            // SPEC-067: Gzip compress event batch for bandwidth reduction
            if let compressed = Self.gzipCompress(data) {
                urlRequest.httpBody = compressed
                urlRequest.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
                Log.debug("Compressed events: \(data.count) → \(compressed.count) bytes (\(String(format: "%.1f", Double(data.count) / max(Double(compressed.count), 1)))x)")
            } else {
                urlRequest.httpBody = data
                Log.warning("Gzip compression failed, sending uncompressed")
            }

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
        // SPEC-067: Request gzip-compressed responses from server
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

        if endpoint.method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Serialize body from endpoint if present
        if let body = endpoint.body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    // MARK: - SPEC-067: Gzip Compression

    /// Compress data using gzip (RFC 1952) with zlib.
    static func gzipCompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        var stream = z_stream()
        // windowBits = 15 + 16 for gzip header
        let initResult = deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
                                       MAX_WBITS + 16, MAX_MEM_LEVEL, Z_DEFAULT_STRATEGY,
                                       ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initResult == Z_OK else { return nil }
        defer { deflateEnd(&stream) }

        let bufferSize = deflateBound(&stream, UInt(data.count))
        var outputData = Data(count: Int(bufferSize))

        let result: Int32 = data.withUnsafeBytes { inputPointer in
            guard let inputBase = inputPointer.baseAddress else { return Z_DATA_ERROR }
            stream.next_in = UnsafeMutablePointer(mutating: inputBase.assumingMemoryBound(to: UInt8.self))
            stream.avail_in = UInt32(data.count)

            return outputData.withUnsafeMutableBytes { outputPointer in
                guard let outputBase = outputPointer.baseAddress else { return Z_DATA_ERROR }
                stream.next_out = outputBase.assumingMemoryBound(to: UInt8.self)
                stream.avail_out = UInt32(bufferSize)
                return deflate(&stream, Z_FINISH)
            }
        }

        guard result == Z_STREAM_END else { return nil }
        outputData.count = Int(stream.total_out)
        return outputData
    }
}
