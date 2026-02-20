import SwiftUI

/// Full-screen takeover message.
struct FullscreenView: View {
    let content: MessageContent
    let onCTATap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(hex: content.background_color ?? "#FFFFFF")
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Optional image
                if let urlString = content.image_url, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 300, maxHeight: 300)
                        }
                    }
                }

                // Title
                if let title = content.title {
                    Text(title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Body
                if let body = content.body {
                    Text(body)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // CTA
                if let ctaText = content.cta_text {
                    Button(action: onCTATap) {
                        Text(ctaText)
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.accentColor)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 24)
                }

                // Dismiss text
                if let dismissText = content.dismiss_text {
                    Button(dismissText, action: onDismiss)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer().frame(height: 32)
            }

            // Close button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            .padding(16)
        }
    }
}
