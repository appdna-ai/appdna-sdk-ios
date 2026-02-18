import SwiftUI

/// Two-button yes/no question.
struct YesNoView: View {
    let question: SurveyQuestion
    @Binding var answer: SurveyAnswer?

    private var selectedValue: String? {
        answer?.answer as? String
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(question.text)
                .font(.headline)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button {
                    answer = SurveyAnswer(question_id: question.id, answer: "yes")
                } label: {
                    Text("Yes")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedValue == "yes" ? Color.accentColor : Color.gray.opacity(0.1))
                        .foregroundColor(selectedValue == "yes" ? .white : .primary)
                        .cornerRadius(10)
                }

                Button {
                    answer = SurveyAnswer(question_id: question.id, answer: "no")
                } label: {
                    Text("No")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedValue == "no" ? Color.accentColor : Color.gray.opacity(0.1))
                        .foregroundColor(selectedValue == "no" ? .white : .primary)
                        .cornerRadius(10)
                }
            }
        }
    }
}
