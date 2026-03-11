import SwiftUI

/// Checkmark feature list for paywalls.
struct FeatureList: View {
    let features: [String]
    /// SPEC-084: Per-section style with element overrides.
    var sectionStyle: SectionStyleConfig? = nil

    private var itemTextStyle: TextStyleConfig? {
        sectionStyle?.elements?["item"]?.textStyle
    }
    private var iconColor: Color? {
        if let hex = sectionStyle?.elements?["icon"]?.textStyle?.color {
            return Color(hex: hex)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(features, id: \.self) { feature in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(iconColor ?? .green)
                        .font(.body)
                    if let ts = itemTextStyle {
                        Text(feature)
                            .applyTextStyle(ts)
                    } else {
                        Text(feature)
                            .font(.body)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}
