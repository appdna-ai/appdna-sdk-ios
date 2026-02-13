import SwiftUI

/// Paywall header with optional title, subtitle, and background image.
struct HeaderSection: View {
    let data: PaywallSectionData?

    var body: some View {
        VStack(spacing: 8) {
            if let imageUrl = data?.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                } placeholder: {
                    Color.clear.frame(height: 200)
                }
            }

            if let title = data?.title {
                Text(title)
                    .font(.title.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }

            if let subtitle = data?.subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 40)
        .padding(.horizontal)
    }
}
