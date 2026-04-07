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
    private var showIcon: Bool { cardStyle.showIcon }
    private var showImage: Bool { cardStyle.showImage }
    private var showSubtitle: Bool { cardStyle.showSubtitle }
    private var showFeatures: Bool { cardStyle.showFeatures }
    private var showSavings: Bool { cardStyle.showSavings }

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
    private var selectedBorder: Color { Color(hex: cardStyle.selectedBorderColor ?? "#6366F1") }
    private var selectedBg: Color? {
        cardStyle.selectedBgColor.map { Color(hex: $0) }
    }
    private var selectedScaleValue: CGFloat { cardStyle.selectedScale ?? 1.0 }
    private var badgeBg: Color { Color(hex: cardStyle.badgeBgColor ?? "#6366F1") }
    private var badgeFg: Color { Color(hex: cardStyle.badgeTextColor ?? "#FFFFFF") }

    var body: some View {
        Button(action: {
            print("[PlanCard] Tapped plan: \(plan.id ?? "nil")")
            onSelect()
        }) {
            ZStack(alignment: badgeAlignment) {
                VStack(spacing: 0) {
                    // Plan image (if enabled)
                    if showImage, let imgUrl = plan.image_url, let url = URL(string: imgUrl) {
                        BundledAsyncImage(url: url) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color.gray.opacity(0.1)
                        }
                        .frame(height: 80)
                        .clipped()
                    }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            if let ts = planNameTextStyle {
                                Text(loc?("plan.\(planIndex).name", plan.displayName) ?? plan.displayName)
                                    .applyTextStyle(ts)
                            } else {
                                Text(loc?("plan.\(planIndex).name", plan.displayName) ?? plan.displayName)
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
                                Text(loc?("plan.\(planIndex).price", plan.displayPrice) ?? plan.displayPrice)
                                    .applyTextStyle(ts)
                            } else {
                                Text(loc?("plan.\(planIndex).price", plan.displayPrice) ?? plan.displayPrice)
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

                        if let trial = plan.trialLabel {
                            if let ts = featureTextStyle {
                                Text(loc?("plan.\(planIndex).trial", "\(trial) free trial") ?? "\(trial) free trial")
                                    .applyTextStyle(ts)
                            } else {
                                Text(loc?("plan.\(planIndex).trial", "\(trial) free trial") ?? "\(trial) free trial")
                                    .font(.caption)
                                    .foregroundColor(Color(hex: "#6366F1"))
                            }
                        }

                        // Description
                        if showSubtitle, let desc = plan.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        // Savings text
                        if showSavings, let savings = plan.savings_text, !savings.isEmpty {
                            Text(savings)
                                .font(.caption2.bold())
                                .foregroundColor(Color(hex: "#22C55E"))
                        }

                        // Per-plan features
                        if showFeatures, let features = plan.features, !features.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(features, id: \.self) { feat in
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(Color(hex: "#6366F1"))
                                        Text(feat).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    Spacer()

                    // Plan icon
                    if showIcon, let iconName = plan.icon, !iconName.isEmpty {
                        Image(systemName: iconName)
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .padding(.trailing, 4)
                    }

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(isSelected ? selectedBorder : .secondary)
                }
                .padding(cardPadding)
                .contentShape(Rectangle()) // Make entire card area tappable including Spacer gaps
                } // close VStack for image
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isSelected ? (selectedBg ?? Color.clear) : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isSelected ? selectedBorder : Color.clear, lineWidth: 2)
                )
                .shadow(
                    color: (cardStyle.cardShadow != nil && cardStyle.cardShadow != "none" && cardStyle.cardShadow != "false")
                        ? .black.opacity(0.1) : .clear,
                    radius: cardStyle.cardShadow == "sm" ? 2 : cardStyle.cardShadow == "lg" ? 8 : 4,
                    x: 0,
                    y: cardStyle.cardShadow == "sm" ? 1 : cardStyle.cardShadow == "lg" ? 4 : 2
                )

                // Positioned badge (top_left / top_right)
                if let badge = plan.badge, badgePositionValue != "inline" {
                    badgeView(badge)
                        .offset(x: badgePositionValue == "top_left" ? 0 : 0, y: -10)
                }
            }
        }
        .contentShape(Rectangle())
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

        if !text.isEmpty {
            if let ts = badgeTextStyle {
                Text(text)
                    .applyTextStyle(ts)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(badgeBg)
                    .clipShape(badgeShape(shape))
            } else {
                Text(text)
                    .font(.caption2.bold())
                    .foregroundColor(badgeFg)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(badgeBg)
                    .clipShape(badgeShape(shape))
            }
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
    var cardShadow: String? = nil  // "none", "sm", "md", "lg", or "true"/"false"
    var badgePosition: String? = nil
    var badgeStyle: String? = nil
    var badgeBgColor: String? = nil
    var badgeTextColor: String? = nil
    var selectedBorderColor: String? = nil
    var selectedBgColor: String? = nil
    var selectedScale: CGFloat? = nil
    // Show flags
    var showIcon: Bool = false
    var showImage: Bool = false
    var showSubtitle: Bool = false
    var showFeatures: Bool = false
    var showSavings: Bool = false

    init() {}

    init(from data: PaywallSectionData?) {
        self.cardCornerRadius = data?.cardCornerRadius
        self.cardPadding = data?.cardPadding
        self.cardGap = data?.cardGap
        // card_shadow can be Bool or String ("none", "sm", "md", "lg")
        if let val = data?.cardShadow?.value {
            if let b = val as? Bool { self.cardShadow = b ? "md" : "none" }
            else if let s = val as? String { self.cardShadow = s }
        }
        self.badgePosition = data?.badgePosition
        self.badgeStyle = data?.badgeStyle
        self.badgeBgColor = data?.badgeBgColor
        self.badgeTextColor = data?.badgeTextColor
        self.selectedBorderColor = data?.selectedBorderColor
        self.selectedBgColor = data?.selectedBgColor
        self.selectedScale = data?.selectedScale
        self.showIcon = data?.showPlanIcons ?? false
        self.showImage = data?.showPlanImages ?? false
        self.showSubtitle = data?.showPlanSubtitles ?? false
        self.showFeatures = data?.showPlanFeatures ?? false
        self.showSavings = data?.showSavings ?? false
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
