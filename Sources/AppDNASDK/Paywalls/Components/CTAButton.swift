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
    /// Override CTA text (from section config.text)
    var textOverride: String? = nil
    /// Restore purchase text (from section config)
    var restoreText: String? = nil
    /// Whether to show restore button
    var showRestore: Bool = false
    /// Restore button position relative to Subscribe: "above" or "below" (default: "below")
    var restorePosition: String = "below"
    /// Direct color override for the restore link (takes priority over restore_text element style)
    var restoreTextColor: String? = nil
    /// Direct font size override for the restore link
    var restoreFontSize: CGFloat? = nil
    /// Restore action
    var onRestore: (() -> Void)? = nil

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

    private var restoreTextStyle: TextStyleConfig? {
        sectionStyle?.elements?["restore_text"]?.textStyle
    }

    @ViewBuilder
    private var subscribeButton: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                }
                if let ts = buttonTextStyle {
                    Text(isPurchasing ? "Processing..." : (loc?("cta.text", textOverride ?? cta?.text ?? "Subscribe") ?? textOverride ?? cta?.text ?? "Subscribe"))
                        .applyTextStyle(ts)
                } else {
                    Text(isPurchasing ? "Processing..." : (loc?("cta.text", textOverride ?? cta?.text ?? "Subscribe") ?? textOverride ?? cta?.text ?? "Subscribe"))
                        .font(.headline)
                        .foregroundColor(buttonTextColor)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, CGFloat(cta?.resolvedPaddingVertical ?? 16))
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

    @ViewBuilder
    private var restoreButton: some View {
        if showRestore, let text = restoreText, !text.isEmpty {
            Button(action: { onRestore?() }) {
                // Priority order:
                // 1. Direct restoreTextColor/restoreFontSize from section data (console Content tab)
                // 2. restore_text element style (console Style tab)
                // 3. Default: .secondary gray at .subheadline size
                let directColor: Color? = restoreTextColor.map { Color(hex: $0) }
                let directFont: Font = restoreFontSize.map { .system(size: $0) } ?? .subheadline
                if let directColor = directColor {
                    Text(text)
                        .font(directFont)
                        .foregroundColor(directColor)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                } else if let ts = restoreTextStyle {
                    Text(text)
                        .applyTextStyle(ts)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                } else {
                    Text(text)
                        .font(directFont)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if restorePosition == "above" {
                restoreButton
                subscribeButton
            } else {
                subscribeButton
                restoreButton
            }
        }
    }
}
