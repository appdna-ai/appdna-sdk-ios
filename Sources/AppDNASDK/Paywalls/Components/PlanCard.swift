import SwiftUI

/// Individual plan option with radio-style selection.
struct PlanCard: View {
    let plan: PaywallPlan
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        if let badge = plan.badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 4) {
                        Text(plan.price)
                            .font(.subheadline.bold())
                            .foregroundColor(.primary)
                        if let period = plan.period {
                            Text("/ \(period)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let trial = plan.trialDuration {
                        Text("\(trial) free trial")
                            .font(.caption)
                            .foregroundColor(.blue)
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
