import Foundation
import UIKit

/// Prefetches remote images into the URL cache so SwiftUI's AsyncImage loads
/// them instantly when a step is displayed. Prevents the "screen flashes with
/// no image" effect when advancing to a step that has large remote assets.
///
/// Usage: call `ImagePreloader.prefetch(urls:timeout:completion:)` before
/// rendering a new step. URLs already in the URLCache are skipped. Bundled
/// assets ("appdna-assets/...") are skipped since they're already on disk.
enum ImagePreloader {
    /// Shared in-memory image cache, also used as the backing store for URLSession.
    private static let cache: URLCache = {
        // 20 MB in-memory, 100 MB on-disk — same sizing as SDWebImage defaults
        let cache = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 100 * 1024 * 1024,
            diskPath: "appdna_image_cache"
        )
        return cache
    }()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = ImagePreloader.cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    /// Tracks URLs whose data is already known to be in the cache so we
    /// don't re-fetch the same image multiple times in quick succession.
    private static var cachedURLs = Set<String>()
    private static let cacheLock = NSLock()

    /// Prefetch the given URLs into the URL cache. Completion fires after all
    /// have finished (or individual timeouts elapsed). Safe to call multiple
    /// times with overlapping URL sets.
    ///
    /// - Parameters:
    ///   - urls: The remote image URLs to fetch. Bundled assets and already-cached
    ///     URLs are skipped.
    ///   - timeout: Maximum time to wait for ALL fetches to complete. Defaults to
    ///     3 seconds — after this, completion fires with whatever's been loaded.
    ///     Prevents a slow network from blocking the UX forever.
    ///   - completion: Called on the main queue once all fetches finish or the
    ///     timeout elapses. Always fires exactly once.
    static func prefetch(
        urls: [URL],
        timeout: TimeInterval = 3.0,
        completion: @escaping () -> Void
    ) {
        // Filter out bundled assets, duplicates, and already-cached URLs
        let toFetch = filterForPrefetch(urls: urls)

        guard !toFetch.isEmpty else {
            DispatchQueue.main.async { completion() }
            return
        }

        Log.debug("[ImagePreloader] Prefetching \(toFetch.count) image(s)")

        let group = DispatchGroup()
        for url in toFetch {
            group.enter()
            let request = URLRequest(url: url)
            let task = session.dataTask(with: request) { data, response, error in
                defer { group.leave() }
                if let error = error {
                    Log.debug("[ImagePreloader] fetch failed for \(url.absoluteString): \(error.localizedDescription)")
                    return
                }
                // Successful fetches are automatically stored in the URLCache
                // configured on the session.
                cacheLock.lock()
                cachedURLs.insert(url.absoluteString)
                cacheLock.unlock()
                if let d = data {
                    Log.debug("[ImagePreloader] cached \(url.lastPathComponent) (\(d.count) bytes)")
                }
            }
            task.resume()
        }

        // Race the group completion against a timeout so a hung network
        // doesn't block navigation.
        var didFire = false
        let fireOnce: () -> Void = {
            DispatchQueue.main.async {
                guard !didFire else { return }
                didFire = true
                completion()
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) { fireOnce() }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            if !didFire {
                Log.debug("[ImagePreloader] timeout reached after \(timeout)s — proceeding with partial cache")
                fireOnce()
            }
        }
    }

    /// Async/await variant.
    static func prefetch(urls: [URL], timeout: TimeInterval = 3.0) async {
        await withCheckedContinuation { continuation in
            prefetch(urls: urls, timeout: timeout) {
                continuation.resume()
            }
        }
    }

    // MARK: - Private helpers

    private static func filterForPrefetch(urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        cacheLock.lock()
        defer { cacheLock.unlock() }
        for url in urls {
            let s = url.absoluteString
            // Skip bundled assets — they're already on disk
            if s.hasPrefix("appdna-assets/") { continue }
            // Skip duplicates within this batch
            if seen.contains(s) { continue }
            seen.insert(s)
            // Skip URLs we've already fetched this session
            if cachedURLs.contains(s) { continue }
            // Skip URLs already in the URL cache from a prior session
            let request = URLRequest(url: url)
            if session.configuration.urlCache?.cachedResponse(for: request) != nil {
                cachedURLs.insert(s)
                continue
            }
            result.append(url)
        }
        return result
    }
}
