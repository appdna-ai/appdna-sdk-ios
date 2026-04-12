import SwiftUI

/// Shared helper to resolve a URL to a local bundled image if available.
/// The bundle-assets script rewrites remote URLs to relative paths like "appdna-assets/abc123.png".
enum BundledImageResolver {
    static func resolve(_ url: URL) -> Image? {
        let urlString = url.absoluteString

        guard urlString.hasPrefix("appdna-assets/") else { return nil }

        let filename = urlString.replacingOccurrences(of: "appdna-assets/", with: "")
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension

        if let path = Bundle.main.path(forResource: name, ofType: ext, inDirectory: "appdna-assets"),
           let uiImage = UIImage(contentsOfFile: path) {
            return Image(uiImage: uiImage)
        }

        if let path = Bundle.main.path(forResource: name, ofType: ext),
           let uiImage = UIImage(contentsOfFile: path) {
            return Image(uiImage: uiImage)
        }

        return nil
    }
}

/// Synchronously check URLCache for a cached image. Returns nil if the URL
/// isn't in the shared cache or the data doesn't decode. Used to skip the
/// AsyncImage "flash from placeholder to success" when an image was prefetched
/// via ImagePreloader.
enum URLCacheImageResolver {
    static func resolve(_ url: URL) -> Image? {
        let request = URLRequest(url: url)
        guard let cached = URLCache.shared.cachedResponse(for: request),
              let ui = UIImage(data: cached.data) else {
            return nil
        }
        return Image(uiImage: ui)
    }
}

/// Drop-in replacement for AsyncImage that checks the app bundle first, then
/// the shared URLCache, then falls through to AsyncImage. The URLCache check
/// means prefetched images render synchronously with no placeholder flash.
struct BundledAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let makeContent: (Image) -> Content
    let makePlaceholder: () -> Placeholder

    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.makeContent = content
        self.makePlaceholder = placeholder
    }

    var body: some View {
        if let url, let localImage = BundledImageResolver.resolve(url) {
            makeContent(localImage)
        } else if let url, let cached = URLCacheImageResolver.resolve(url) {
            makeContent(cached)
        } else {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    makeContent(image)
                default:
                    makePlaceholder()
                }
            }
        }
    }
}

// Phase-based initializer: AsyncImage(url:content:) where content receives AsyncImagePhase
struct BundledAsyncPhaseImage<Content: View>: View {
    let url: URL?
    let content: (AsyncImagePhase) -> Content

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        if let url, let localImage = BundledImageResolver.resolve(url) {
            content(.success(localImage))
        } else if let url, let cached = URLCacheImageResolver.resolve(url) {
            content(.success(cached))
        } else {
            AsyncImage(url: url, content: content)
        }
    }
}
