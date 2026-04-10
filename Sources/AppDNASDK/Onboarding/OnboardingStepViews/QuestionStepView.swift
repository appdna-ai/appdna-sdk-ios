import SwiftUI

/// Question step: title, option grid, single/multi select, CTA.
struct QuestionStepView: View {
    let config: StepConfig
    let onNext: ([String: Any]?) -> Void

    @State private var selectedIds: Set<String> = []

    private var isMultiSelect: Bool {
        config.selection_mode == .multi
    }

    // MARK: - Configurable colors from element_style

    /// Accent color used for selected state (border, fill tint, CTA).
    private var accentColor: Color {
        if let hex = config.element_style?.border?.color { return Color(hex: hex) }
        if let hex = config.element_style?.background?.color { return Color(hex: hex) }
        return Color(hex: "#6366F1")
    }

    /// Background color for selected option cards — reads selection_style.background or falls back to accent at 15%.
    private var selectedBgColor: Color {
        if let hex = config.element_style?.shadow?.color { return Color(hex: hex) } // Reuse shadow.color as selected_bg
        return accentColor.opacity(0.15)
    }

    /// Background color for unselected option cards.
    private var optionBgColor: Color {
        if let hex = config.element_style?.background?.overlay { return Color(hex: hex) }
        if let hex = config.element_style?.background?.color { return Color(hex: hex).opacity(0.1) }
        return Color.white.opacity(0.08)
    }

    /// Border color for selected option cards.
    private var selectedBorderColor: Color {
        accentColor
    }

    /// Border color for unselected option cards.
    private var optionBorderColor: Color {
        if let hex = config.element_style?.border?.color { return Color(hex: hex).opacity(0.3) }
        return Color.white.opacity(0.15)
    }

    /// Text color for option labels (uses element_style text_style if set).
    private var optionTextColor: Color {
        if let hex = config.element_style?.textStyle?.color { return Color(hex: hex) }
        return .primary
    }

    var body: some View {
        VStack(spacing: 24) {
            if let title = config.title {
                Text(title.interpolated())
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
            }

            // Options grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ], spacing: 12) {
                    ForEach(config.options ?? []) { option in
                        optionCard(option)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            // CTA
            Button {
                let data: [String: Any] = [
                    "selected": Array(selectedIds),
                    "selection_mode": isMultiSelect ? "multi" : "single",
                ]
                onNext(data)
            } label: {
                Text((config.cta_text ?? "Continue").interpolated())
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(selectedIds.isEmpty ? Color.gray : accentColor)
                    .cornerRadius(CGFloat(config.element_style?.corner_radius ?? 14))
            }
            .disabled(selectedIds.isEmpty)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Option card

    private func optionCard(_ option: QuestionOption) -> some View {
        let optId = option.id ?? UUID().uuidString
        let isSelected = selectedIds.contains(optId)
        let cornerRadius = CGFloat(config.element_style?.corner_radius ?? 12)

        return Button {
            if isMultiSelect {
                if isSelected {
                    selectedIds.remove(optId)
                } else {
                    selectedIds.insert(optId)
                }
            } else {
                selectedIds = [optId]
            }
        } label: {
            VStack(spacing: 8) {
                if let icon = option.icon {
                    Text(icon)
                        .font(.system(size: 32))
                }

                Text((option.label ?? "").interpolated())
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(optionTextColor)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let sub = option.subtitle, !sub.isEmpty {
                    Text(sub.interpolated())
                        .font(.caption)
                        .foregroundColor(optionTextColor.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isSelected ? selectedBgColor : optionBgColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isSelected ? selectedBorderColor : optionBorderColor, lineWidth: isSelected ? 2 : 1)
            )
        }
    }
}
