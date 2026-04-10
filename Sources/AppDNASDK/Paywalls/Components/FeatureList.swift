import SwiftUI

/// Checkmark feature list for paywalls.
/// Supports plain string features and rich structured items with icons, images, and excluded state.
struct FeatureList: View {
    let features: [String]
    var richItems: [PaywallGenericItem]? = nil
    var columns: Int = 1
    var gap: CGFloat = 12
    /// SPEC-084: Per-section style with element overrides.
    var sectionStyle: SectionStyleConfig? = nil
    /// Direct icon color override from section.data.icon_color — takes priority
    /// over sectionStyle.elements["icon"].textStyle.color. Exposed in the console
    /// Content tab for easier access than the Style tab.
    var iconColorOverride: String? = nil
    /// Circle background behind each feature icon (screenshot 10 effect)
    var iconBgColor: String? = nil
    var iconBgOpacity: CGFloat = 0.15
    var iconBgSize: CGFloat = 32

    private var itemTextStyle: TextStyleConfig? {
        // Console saves under "item_text" key; fall back to legacy "item" key for older configs
        sectionStyle?.elements?["item_text"]?.textStyle
            ?? sectionStyle?.elements?["item"]?.textStyle
    }
    private var iconColor: Color? {
        // Priority: section.data.icon_color (Content tab) > style.elements.icon.textStyle.color (Style tab)
        if let hex = iconColorOverride, !hex.isEmpty {
            return Color(hex: hex)
        }
        if let hex = sectionStyle?.elements?["icon"]?.textStyle?.color {
            return Color(hex: hex)
        }
        return nil
    }

    var body: some View {
        if columns > 1, let items = richItems, !items.isEmpty {
            // Multi-column grid
            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: gap), count: columns)
            LazyVGrid(columns: gridColumns, spacing: gap) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    richItemRow(item)
                }
            }
            .padding(.horizontal)
        } else if let items = richItems, !items.isEmpty {
            // Single column rich items
            VStack(alignment: .leading, spacing: gap) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    richItemRow(item)
                }
            }
            .padding(.horizontal)
        } else {
            // Plain string features (legacy)
            VStack(alignment: .leading, spacing: gap) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 12) {
                        featureIcon()
                        if let ts = itemTextStyle {
                            Text(feature).applyTextStyle(ts)
                        } else {
                            Text(feature).font(.body).foregroundColor(.primary)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func richItemRow(_ item: PaywallGenericItem) -> some View {
        let isIncluded = item.included ?? true
        HStack(spacing: 12) {
            // Icon: custom emoji/SF Symbol, or default check/cross — with optional circle bg
            featureIcon(item: item, isIncluded: isIncluded)

            // Text
            if let ts = itemTextStyle {
                Text(item.displayText ?? "").applyTextStyle(ts)
            } else {
                Text(item.displayText ?? "").font(.body).foregroundColor(.primary)
            }
        }
        .opacity(isIncluded ? 1.0 : 0.4)
    }

    /// Renders a feature icon with optional circle background (screenshot 10).
    @ViewBuilder
    private func featureIcon(item: PaywallGenericItem? = nil, isIncluded: Bool = true) -> some View {
        let icon: some View = Group {
            if let emoji = item?.emoji, !emoji.isEmpty {
                Text(emoji).font(.body)
            } else if let iconName = item?.icon, !iconName.isEmpty {
                Image(systemName: iconName)
                    .foregroundColor(iconColor ?? (isIncluded ? Color(hex: "#6366F1") : Color(hex: "#EF4444")))
                    .font(.body)
            } else if let imageUrl = item?.image_url, let url = URL(string: imageUrl) {
                BundledAsyncImage(url: url) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isIncluded ? (iconColor ?? Color(hex: "#6366F1")) : Color(hex: "#EF4444").opacity(0.5))
                    .font(.body)
            }
        }

        if let bgHex = iconBgColor {
            ZStack {
                Circle()
                    .fill(Color(hex: bgHex).opacity(iconBgOpacity))
                    .frame(width: iconBgSize, height: iconBgSize)
                icon
            }
            .frame(width: iconBgSize, height: iconBgSize)
        } else {
            icon
        }
    }
}
