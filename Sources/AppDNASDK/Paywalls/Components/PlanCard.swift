import SwiftUI

/// Individual plan option with radio-style selection.
/// Supports card/badge styling from section data (Gap 11).
struct PlanCard: View {
    let plan: PaywallPlan
    let isSelected: Bool
    let onSelect: () -> Void
    var planIndex: Int = 0
    var loc: ((String, String) -> String)? = nil
    /// SPEC-084: Per-section style with element overrides.
    var sectionStyle: SectionStyleConfig? = nil
    /// Gap 11: Card/badge styling from section data.
    var cardStyle: PlanCardStyle = PlanCardStyle()

    private var planNameTextStyle: TextStyleConfig? {
        sectionStyle?.elements?["plan_name"]?.textStyle
    }
    private var priceTextStyle: TextStyleConfig? {
        sectionStyle?.elements?["price"]?.textStyle
    }
    private var periodTextStyle: TextStyleConfig? {
        sectionStyle?.elements?["period"]?.textStyle
    }
    private var badgeTextStyle: TextStyleConfig? {
        sectionStyle?.elements?["badge"]?.textStyle
    }
    private var featureTextStyle: TextStyleConfig? {
        sectionStyle?.elements?["feature"]?.textStyle
    }

    private var cornerRadius: CGFloat { cardStyle.cardCornerRadius ?? 12 }
    private var cardPadding: CGFloat { cardStyle.cardPadding ?? 16 }
    private var selectedBorder: Color { Color(hex: cardStyle.selectedBorderColor ?? "#3B82F6") }
    private var selectedBg: Color? {
        cardStyle.selectedBgColor.map { Color(hex: $0) }
    }
    private var selectedScaleValue: CGFloat { cardStyle.selectedScale ?? 1.0 }
    private var badgeBg: Color { Color(hex: cardStyle.badgeBgColor ?? "#3B82F6") }
    private var badgeFg: Color { Color(hex: cardStyle.badgeTextColor ?? "#FFFFFF") }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: badgeAlignment) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            if let ts = planNameTextStyle {
                                Text(loc?("plan.\(planIndex).name", plan.name ?? "") ?? plan.name ?? "")
                                    .applyTextStyle(ts)
                            } else {
                                Text(loc?("plan.\(planIndex).name", plan.name ?? "") ?? plan.name ?? "")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }

                            // Inline badge (default position)
                            if let badge = plan.badge, badgePositionValue == "inline" {
                                badgeView(badge)
                            }
                        }

                        HStack(spacing: 4) {
                            if let ts = priceTextStyle {
                                Text(loc?("plan.\(planIndex).price", plan.price ?? "") ?? plan.price ?? "")
                                    .applyTextStyle(ts)
                            } else {
                                Text(loc?("plan.\(planIndex).price", plan.price ?? "") ?? plan.price ?? "")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                            }
                            if let period = plan.period {
                                if let ts = periodTextStyle {
                                    Text(loc?("plan.\(planIndex).period", "/ \(period)") ?? "/ \(period)")
                                        .applyTextStyle(ts)
                                } else {
                                    Text(loc?("plan.\(planIndex).period", "/ \(period)") ?? "/ \(period)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        if let trial = plan.trialDuration {
                            if let ts = featureTextStyle {
                                Text(loc?("plan.\(planIndex).trial", "\(trial) free trial") ?? "\(trial) free trial")
                                    .applyTextStyle(ts)
                            } else {
                                Text(loc?("plan.\(planIndex).trial", "\(trial) free trial") ?? "\(trial) free trial")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(isSelected ? selectedBorder : .secondary)
                }
                .padding(cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isSelected ? (selectedBg ?? Color(.secondarySystemBackground)) : Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isSelected ? selectedBorder : Color.clear, lineWidth: 2)
                )
                .if(cardStyle.cardShadow ?? false) { view in
                    view.shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }

                // Positioned badge (top_left / top_right)
                if let badge = plan.badge, badgePositionValue != "inline" {
                    badgeView(badge)
                        .offset(x: badgePositionValue == "top_left" ? 0 : 0, y: -10)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? selectedScaleValue : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    // MARK: - Badge helpers

    private var badgePositionValue: String { cardStyle.badgePosition ?? "inline" }

    private var badgeAlignment: Alignment {
        switch badgePositionValue {
        case "top_left": return .topLeading
        case "top_right": return .topTrailing
        default: return .topLeading
        }
    }

    @ViewBuilder
    private func badgeView(_ badge: String) -> some View {
        let text = loc?("plan.\(planIndex).badge", badge) ?? badge
        let shape = cardStyle.badgeStyle ?? "capsule"

        if let ts = badgeTextStyle {
            Text(text)
                .applyTextStyle(ts)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(badgeBg)
                .clipShape(badgeShape(shape))
        } else {
            Text(text)
                .font(.caption2.bold())
                .foregroundColor(badgeFg)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(badgeBg)
                .clipShape(badgeShape(shape))
        }
    }

    private func badgeShape(_ style: String) -> some Shape {
        switch style {
        case "rectangle":
            return AnyShape(RoundedRectangle(cornerRadius: 2))
        case "rounded":
            return AnyShape(RoundedRectangle(cornerRadius: 6))
        default: // capsule
            return AnyShape(Capsule())
        }
    }
}

/// Helper to hold plan card styling values extracted from section data.
struct PlanCardStyle {
    var cardCornerRadius: CGFloat? = nil
    var cardPadding: CGFloat? = nil
    var cardGap: CGFloat? = nil
    var cardShadow: Bool? = nil
    var badgePosition: String? = nil
    var badgeStyle: String? = nil
    var badgeBgColor: String? = nil
    var badgeTextColor: String? = nil
    var selectedBorderColor: String? = nil
    var selectedBgColor: String? = nil
    var selectedScale: CGFloat? = nil

    init() {}

    init(from data: PaywallSectionData?) {
        self.cardCornerRadius = data?.cardCornerRadius
        self.cardPadding = data?.cardPadding
        self.cardGap = data?.cardGap
        self.cardShadow = data?.cardShadow
        self.badgePosition = data?.badgePosition
        self.badgeStyle = data?.badgeStyle
        self.badgeBgColor = data?.badgeBgColor
        self.badgeTextColor = data?.badgeTextColor
        self.selectedBorderColor = data?.selectedBorderColor
        self.selectedBgColor = data?.selectedBgColor
        self.selectedScale = data?.selectedScale
    }
}

/// Type-erased AnyShape for badge styling.
struct AnyShape: Shape {
    private let _path: (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        _path = { rect in shape.path(in: rect) }
    }

    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}

/// Conditional view modifier helper.
extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
