import SwiftUI

/// Star, heart, or thumb rating (configurable max).
struct RatingQuestionView: View {
    let question: SurveyQuestion
    @Binding var answer: SurveyAnswer?

    private var maxRating: Int {
        question.rating_config?.max_rating ?? 5
    }

    private var style: String {
        question.rating_config?.style ?? "star"
    }

    private var selectedRating: Int? {
        answer?.answer as? Int
    }

    private var filledIcon: String {
        switch style {
        case "heart": return "heart.fill"
        case "thumb": return "hand.thumbsup.fill"
        default: return "star.fill"
        }
    }

    private var emptyIcon: String {
        switch style {
        case "heart": return "heart"
        case "thumb": return "hand.thumbsup"
        default: return "star"
        }
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
                        Image(systemName: (selectedRating ?? 0) >= rating ? filledIcon : emptyIcon)
                            .font(.system(size: 28))
                            .foregroundColor((selectedRating ?? 0) >= rating ? ratingColor : .gray.opacity(0.3))
                    }
                }
            }
        }
    }

    private var ratingColor: Color {
        switch style {
        case "heart": return .red
        case "thumb": return .blue
        default: return .yellow
        }
    }
}
