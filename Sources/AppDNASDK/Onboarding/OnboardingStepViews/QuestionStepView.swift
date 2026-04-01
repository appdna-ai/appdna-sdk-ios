import SwiftUI

/// Question step: title, option grid, single/multi select, CTA.
struct QuestionStepView: View {
    let config: StepConfig
    let onNext: ([String: Any]?) -> Void

    @State private var selectedIds: Set<String> = []

    private var isMultiSelect: Bool {
        config.selection_mode == .multi
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
                    .background(selectedIds.isEmpty ? Color.gray : Color(hex: "#6366F1"))
                    .cornerRadius(14)
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
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 100)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color(hex: "#6366F1").opacity(0.1) : Color(hex: "#F3F4F6"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color(hex: "#6366F1") : Color.clear, lineWidth: 2)
            )
        }
    }
}
