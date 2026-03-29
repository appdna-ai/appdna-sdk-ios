import SwiftUI

/// Radio-button style single selection.
struct SingleChoiceView: View {
    let question: SurveyQuestion
    @Binding var answer: SurveyAnswer?
    // SPEC-084: Gap #19 — option_style from SurveyAppearance applied to each option card
    var optionStyle: ElementStyleConfig? = nil

    private var selectedId: String? {
        answer?.answer as? String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.text ?? "")
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            ForEach(question.options ?? [], id: \.id) { option in
                Button {
                    answer = SurveyAnswer(question_id: question.id ?? "", answer: option.id ?? "")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedId == option.id ? "circle.inset.filled" : "circle")
                            .foregroundColor(selectedId == option.id ? .accentColor : .gray)

                        if let icon = option.icon {
                            Text(icon)
                        }

                        Text(option.text ?? "")
                            .foregroundColor(.primary)

                        Spacer()
                    }
                    .padding(.vertical, optionStyle == nil ? 8 : 0)
                    .padding(.horizontal, optionStyle == nil ? 12 : 0)
                    // SPEC-084: Apply option_style if provided, otherwise fall back to default card border
                    .applyContainerStyleOrDefault(optionStyle, isSelected: selectedId == option.id)
                }
            }
        }
    }
}
