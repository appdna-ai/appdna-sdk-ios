import SwiftUI

/// Handles SVG, GIF, and standard images uniformly
public struct MediaImageView: View {
    let url: String
    let maxHeight: CGFloat
    let cornerRadius: CGFloat

    init(url: String, maxHeight: CGFloat = 200, cornerRadius: CGFloat = 0) {
        self.url = url
        self.maxHeight = maxHeight
        self.cornerRadius = cornerRadius
    }

    private var isSVG: Bool { url.lowercased().hasSuffix(".svg") }
    private var isGIF: Bool { url.lowercased().hasSuffix(".gif") }

    public var body: some View {
        // For SVG: In production, use SVGKit for native rendering
        // For GIF: In production, use SDWebImageSwiftUI for animation
        // Both fall back to AsyncImage which handles static rendering
        if let imageURL = URL(string: url) {
            BundledAsyncPhaseImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxHeight: maxHeight)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                case .failure:
                    imagePlaceholder
                case .empty:
                    ProgressView()
                        .frame(maxHeight: maxHeight)
                @unknown default:
                    imagePlaceholder
                }
            }
        } else {
            imagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray.opacity(0.1))
            .frame(height: maxHeight)
            .overlay(
                Image(systemName: isSVG ? "doc.richtext" : isGIF ? "photo.badge.plus" : "photo")
                    .foregroundColor(.gray)
            )
    }
}
