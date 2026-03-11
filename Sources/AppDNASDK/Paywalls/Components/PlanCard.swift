import SwiftUI

/// Individual plan option with radio-style selection.
struct PlanCard: View {
    let plan: PaywallPlan
    let isSelected: Bool
    let onSelect: () -> Void
    var planIndex: Int = 0
    var loc: ((String, String) -> String)? = nil
    /// SPEC-084: Per-section style with element overrides.
    var sectionStyle: SectionStyleConfig? = nil

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

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if let ts = planNameTextStyle {
                            Text(loc?("plan.\(planIndex).name", plan.name) ?? plan.name)
                                .applyTextStyle(ts)
                        } else {
                            Text(loc?("plan.\(planIndex).name", plan.name) ?? plan.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                        }

                        if let badge = plan.badge {
                            if let ts = badgeTextStyle {
                                Text(loc?("plan.\(planIndex).badge", badge) ?? badge)
                                    .applyTextStyle(ts)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue)
                                    .clipShape(Capsule())
                            } else {
                                Text(loc?("plan.\(planIndex).badge", badge) ?? badge)
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    HStack(spacing: 4) {
                        if let ts = priceTextStyle {
                            Text(loc?("plan.\(planIndex).price", plan.price) ?? plan.price)
                                .applyTextStyle(ts)
                        } else {
                            Text(loc?("plan.\(planIndex).price", plan.price) ?? plan.price)
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
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
