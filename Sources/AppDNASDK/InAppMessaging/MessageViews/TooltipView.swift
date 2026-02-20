import SwiftUI

/// Small contextual tooltip popup.
struct TooltipView: View {
    let content: MessageContent
    let onCTATap: () -> Void
    let onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        VStack {
            Spacer()

            if isVisible {
                tooltipContent
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.black.opacity(0.01))
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isVisible = true
            }
            // Auto-dismiss after timeout
            if let seconds = content.auto_dismiss_seconds, seconds > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(seconds)) {
                    withAnimation { isVisible = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDismiss() }
                }
            }
        }
    }

    private var tooltipContent: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
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

                Button {
                    withAnimation { isVisible = false }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                }
            }

            if let ctaText = content.cta_text {
                Button(action: {
                    onCTATap()
                }) {
                    Text(ctaText)
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: content.background_color ?? "#FFFFFF"))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
