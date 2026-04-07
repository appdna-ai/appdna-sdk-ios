import SwiftUI

/// Paywall header with optional title, subtitle, and background image.
struct HeaderSection: View {
    let data: PaywallSectionData?
    var loc: ((String, String) -> String)? = nil
    /// SPEC-084: Per-section style with element overrides.
    var sectionStyle: SectionStyleConfig? = nil

    private var titleTextStyle: TextStyleConfig? {
        data?.title_style ?? sectionStyle?.elements?["title"]?.textStyle
    }
    private var subtitleTextStyle: TextStyleConfig? {
        data?.subtitle_style ?? sectionStyle?.elements?["subtitle"]?.textStyle
    }

    var body: some View {
        VStack(spacing: 8) {
            if let imageUrl = data?.imageUrl, let url = URL(string: imageUrl) {
                BundledAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                } placeholder: {
                    Color.clear.frame(height: 200)
                }
            }

            if let title = data?.title {
                if let ts = titleTextStyle {
                    Text(loc?("section-header.title", title) ?? title)
                        .applyTextStyle(ts)
                } else {
                    Text(loc?("section-header.title", title) ?? title)
                        .font(.title.bold())
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
            }

            if let subtitle = data?.subtitle {
                if let ts = subtitleTextStyle {
                    Text(loc?("section-header.subtitle", subtitle) ?? subtitle)
                        .applyTextStyle(ts)
                } else {
                    Text(loc?("section-header.subtitle", subtitle) ?? subtitle)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.top, 40)
        .padding(.horizontal)
    }
}
