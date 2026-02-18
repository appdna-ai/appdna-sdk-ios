import SwiftUI

/// Star or emoji rating (1-5 by default).
struct CSATQuestionView: View {
    let question: SurveyQuestion
    @Binding var answer: SurveyAnswer?

    private var maxRating: Int {
        question.csat_config?.max_rating ?? 5
    }

    private var style: String {
        question.csat_config?.style ?? "star"
    }

    private var selectedRating: Int? {
        answer?.answer as? Int
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(question.text)
                .font(.headline)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                ForEach(1...maxRating, id: \.self) { rating in
                    Button {
                        answer = SurveyAnswer(question_id: question.id, answer: rating)
                    } label: {
                        if style == "emoji" {
                            Text(emojiFor(rating: rating, max: maxRating))
                                .font(.system(size: 32))
                        } else {
                            Image(systemName: (selectedRating ?? 0) >= rating ? "star.fill" : "star")
                                .font(.system(size: 28))
                                .foregroundColor((selectedRating ?? 0) >= rating ? .yellow : .gray.opacity(0.3))
                        }
                    }
                }
            }
        }
    }

    private func emojiFor(rating: Int, max: Int) -> String {
        let emojis = ["😡", "😕", "😐", "😊", "😍"]
        let index = Int(Double(rating - 1) / Double(max - 1) * Double(emojis.count - 1))
        return emojis[min(index, emojis.count - 1)]
    }
}
