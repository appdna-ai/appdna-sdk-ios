import SwiftUI

/// Primary purchase CTA button with loading state.
struct CTAButton: View {
    let cta: PaywallCTA?
    let isPurchasing: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                }
                Text(isPurchasing ? "Processing..." : (cta?.text ?? "Subscribe"))
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.blue)
            )
        }
        .disabled(isPurchasing)
        .padding(.horizontal)
    }
}
