import SwiftUI

/// Top or bottom banner message with auto-dismiss.
struct BannerView: View {
    let content: MessageContent
    let onCTATap: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible = false

    private var isTop: Bool {
        content.banner_position != .bottom
    }

    var body: some View {
        VStack {
            if !isTop { Spacer() }

            if isVisible {
                bannerContent
                    .transition(.move(edge: isTop ? .top : .bottom).combined(with: .opacity))
            }

            if isTop { Spacer() }
        }
        .background(Color.black.opacity(0.01)) // Tap-through background
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isVisible = true
            }
            // Auto-dismiss
            if let seconds = content.auto_dismiss_seconds, seconds > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(seconds)) {
                    withAnimation { isVisible = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDismiss() }
                }
            }
        }
    }

    private var bannerContent: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let title = content.title {
                    Text(title)
                        .font(.subheadline.bold())
                }
                if let body = content.body {
                    Text(body)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let ctaText = content.cta_text {
                Button(ctaText, action: onCTATap)
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }

            Button {
                withAnimation { isVisible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: content.background_color ?? "#FFFFFF"))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(isTop ? .top : .bottom, 8)
    }
}
