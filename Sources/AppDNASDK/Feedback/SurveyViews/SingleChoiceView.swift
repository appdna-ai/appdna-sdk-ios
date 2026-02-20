import SwiftUI

/// Radio-button style single selection.
struct SingleChoiceView: View {
    let question: SurveyQuestion
    @Binding var answer: SurveyAnswer?

    private var selectedId: String? {
        answer?.answer as? String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.text)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            ForEach(question.options ?? [], id: \.id) { option in
                Button {
                    answer = SurveyAnswer(question_id: question.id, answer: option.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selectedId == option.id ? "circle.inset.filled" : "circle")
                            .foregroundColor(selectedId == option.id ? .accentColor : .gray)

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
                            .stroke(selectedId == option.id ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
    }
}
