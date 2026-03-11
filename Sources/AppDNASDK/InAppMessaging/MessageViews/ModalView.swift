import SwiftUI

/// Centered modal message with overlay backdrop.
struct ModalView: View {
    let content: MessageContent
    let onCTATap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Modal card
            VStack(spacing: 16) {
                // Dismiss button
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                    }
                }
                .padding(.trailing, -4)

                // Optional image
                if let urlString = content.image_url, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                // Title — SPEC-084: apply text_color
                if let title = content.title {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundColor(content.text_color.map { Color(hex: $0) } ?? .primary)
                        .multilineTextAlignment(.center)
                }

                // Body — SPEC-084: apply text_color
                if let body = content.body {
                    Text(body)
                        .font(.body)
                        .foregroundColor(content.text_color.map { Color(hex: $0).opacity(0.7) } ?? .secondary)
                        .multilineTextAlignment(.center)
                }

                // CTA button — SPEC-084: apply button_color, corner_radius
                if let ctaText = content.cta_text {
                    Button(action: onCTATap) {
                        Text(ctaText)
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(hex: content.button_color ?? "#6366F1"))
                            .cornerRadius(CGFloat(content.corner_radius ?? 12))
                    }
                }

                // Dismiss text
                if let dismissText = content.dismiss_text {
                    Button(dismissText, action: onDismiss)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: CGFloat(content.corner_radius ?? 20))
                    .fill(Color(hex: content.background_color ?? "#FFFFFF"))
            )
            .padding(.horizontal, 32)
        }
    }
}
