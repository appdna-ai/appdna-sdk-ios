import SwiftUI

/// Primary purchase CTA button with loading state.
struct CTAButton: View {
    let cta: PaywallCTA?
    let isPurchasing: Bool
    let onTap: () -> Void
    var loc: ((String, String) -> String)? = nil
    /// SPEC-084: Per-section style with element overrides.
    var sectionStyle: SectionStyleConfig? = nil

    private var buttonElement: ElementStyleConfig? {
        sectionStyle?.elements?["button"]
    }
    private var buttonTextStyle: TextStyleConfig? {
        buttonElement?.textStyle
    }
    private var buttonBgColor: Color {
        if let hex = buttonElement?.background?.color {
            return Color(hex: hex)
        }
        return .blue
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                }
                if let ts = buttonTextStyle {
                    Text(isPurchasing ? "Processing..." : (loc?("cta.text", cta?.text ?? "Subscribe") ?? cta?.text ?? "Subscribe"))
                        .applyTextStyle(ts)
                } else {
                    Text(isPurchasing ? "Processing..." : (loc?("cta.text", cta?.text ?? "Subscribe") ?? cta?.text ?? "Subscribe"))
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(buttonBgColor)
            )
        }
        .disabled(isPurchasing)
        .padding(.horizontal)
    }
}
