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

/// Drop-in replacement for AsyncImage that checks the app bundle first.
/// Supports both `AsyncImage(url:content:)` and `AsyncImage(url:content:placeholder:)` patterns.
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
        } else {
            AsyncImage(url: url, content: content)
        }
    }
}
