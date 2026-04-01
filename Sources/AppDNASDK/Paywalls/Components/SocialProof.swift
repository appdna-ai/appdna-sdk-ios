import SwiftUI

/// Star rating and review count display.
struct SocialProof: View {
    let data: PaywallSectionData?
    var loc: ((String, String) -> String)? = nil
    /// SPEC-084: Per-section style with element overrides.
    var sectionStyle: SectionStyleConfig? = nil

    private var valueTextStyle: TextStyleConfig? {
        sectionStyle?.elements?["value"]?.textStyle
    }

    var body: some View {
        VStack(spacing: 8) {
            if let rating = data?.rating {
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { index in
                        Image(systemName: starName(for: index, rating: rating))
                            .foregroundColor(Color(hex: "#FBBF24"))
                            .font(.body)
                    }

                    if let count = data?.reviewCount {
                        if let ts = valueTextStyle {
                            Text("(\(formatCount(count)))")
                                .applyTextStyle(ts)
                        } else {
                            Text("(\(formatCount(count)))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            if let testimonial = data?.testimonial {
                Text("\"\(loc?("social_proof.testimonial", testimonial) ?? testimonial)\"")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .font(.subheadline.italic())
                    .padding(.horizontal)
            }
        }
    }

    private func starName(for index: Int, rating: Double) -> String {
        let threshold = Double(index) + 1
        if rating >= threshold {
            return "star.fill"
        } else if rating >= threshold - 0.5 {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            return "\(count / 1000).\((count % 1000) / 100)K"
        }
        return "\(count)"
    }
}
