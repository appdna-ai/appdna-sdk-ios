import SwiftUI

/// Primary purchase CTA button with loading state.
struct CTAButton: View {
    let cta: PaywallCTA?
    let isPurchasing: Bool
    let onTap: () -> Void
    var loc: ((String, String) -> String)? = nil
    /// SPEC-084: Per-section style with element overrides.
    var sectionStyle: SectionStyleConfig? = nil
    /// CTA gradient (from section data)
    var ctaGradient: PaywallGradient? = nil

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
        return Color(hex: cta?.resolvedBgColor ?? "#6366F1")
    }
    private var buttonTextColor: Color {
        if let ts = buttonTextStyle, let hex = ts.color {
            return Color(hex: hex)
        }
        return Color(hex: cta?.resolvedTextColor ?? "#FFFFFF")
    }
    private var buttonCornerRadius: CGFloat {
        CGFloat(cta?.resolvedCornerRadius ?? 12.0)
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
                        .foregroundColor(buttonTextColor)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if let grad = ctaGradient, let stops = grad.stops, stops.count >= 2 {
                        RoundedRectangle(cornerRadius: buttonCornerRadius)
                            .fill(LinearGradient(
                                stops: stops.map { Gradient.Stop(color: Color(hex: $0.color ?? "#000"), location: ($0.position ?? 0) / 100.0) },
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                    } else {
                        RoundedRectangle(cornerRadius: buttonCornerRadius)
                            .fill(buttonBgColor)
                    }
                }
            )
        }
        .disabled(isPurchasing)
        .padding(.horizontal)
    }
}
