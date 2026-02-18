import SwiftUI

/// Checkbox-style multi-selection.
struct MultiChoiceView: View {
    let question: SurveyQuestion
    @Binding var answer: SurveyAnswer?

    private var selectedIds: [String] {
        answer?.answer as? [String] ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.text)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            ForEach(question.options ?? [], id: \.id) { option in
                Button {
                    toggleOption(option.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedIds.contains(option.id) ? "checkmark.square.fill" : "square")
                            .foregroundColor(selectedIds.contains(option.id) ? .accentColor : .gray)

                        if let icon = option.icon {
                            Text(icon)
                        }

                        Text(option.text)
                            .foregroundColor(.primary)

                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedIds.contains(option.id) ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func toggleOption(_ id: String) {
        var current = selectedIds
        if let index = current.firstIndex(of: id) {
            current.remove(at: index)
        } else {
            current.append(id)
        }
        answer = SurveyAnswer(question_id: question.id, answer: current)
    }
}
