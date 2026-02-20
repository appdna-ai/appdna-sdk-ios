import SwiftUI

/// Star rating and review count display.
struct SocialProof: View {
    let data: PaywallSectionData?

    var body: some View {
        VStack(spacing: 8) {
            if let rating = data?.rating {
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { index in
                        Image(systemName: starName(for: index, rating: rating))
                            .foregroundColor(.yellow)
                            .font(.body)
                    }

                    if let count = data?.reviewCount {
                        Text("(\(formatCount(count)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let testimonial = data?.testimonial {
                Text("\"\(testimonial)\"")
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
