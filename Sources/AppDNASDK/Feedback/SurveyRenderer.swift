import SwiftUI
import UIKit

/// Renders surveys as SwiftUI views and presents them in the appropriate style.
final class SurveyRenderer {

    func present(config: SurveyConfig, onQuestionAnswered: ((String, SurveyQuestion, SurveyAnswer) -> Void)? = nil, completion: @escaping (SurveyResult) -> Void) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
                  let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                Log.warning("No root view controller available for survey presentation")
                return
            }

            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }

            var view = SurveyContainerView(config: config, completion: completion)
            view.onQuestionAnswered = onQuestionAnswered
            let hostingVC = UIHostingController(rootView: view)

            switch config.appearance.presentation {
            case "fullscreen":
                hostingVC.modalPresentationStyle = .fullScreen
            case "modal":
                hostingVC.modalPresentationStyle = .pageSheet
            default: // bottom_sheet
                if #available(iOS 16.0, *) {
                    hostingVC.modalPresentationStyle = .pageSheet
                    if let sheet = hostingVC.sheetPresentationController {
                        sheet.detents = [.medium(), .large()]
                        sheet.prefersGrabberVisible = true
                    }
                } else {
                    hostingVC.modalPresentationStyle = .pageSheet
                }
            }

            hostingVC.view.backgroundColor = .clear
            topVC.present(hostingVC, animated: true)
        }
    }
}

// MARK: - Survey Container View

struct SurveyContainerView: View {
    let config: SurveyConfig
    let completion: (SurveyResult) -> Void
    var onQuestionAnswered: ((String, SurveyQuestion, SurveyAnswer) -> Void)?

    @State private var currentQuestionIndex = 0
    @State private var answers: [String: SurveyAnswer] = [:] // keyed by question_id
    @State private var visibleQuestions: [SurveyQuestion] = []
    @SwiftUI.Environment(\.dismiss) private var dismiss

    private var backgroundColor: Color {
        Color(hex: config.appearance.theme?.background_color ?? "#FFFFFF")
    }

    private var textColor: Color {
        Color(hex: config.appearance.theme?.text_color ?? "#1a1a1a")
    }

    private var accentColor: Color {
        Color(hex: config.appearance.theme?.accent_color ?? "#6366f1")
    }

    private var buttonColor: Color {
        Color(hex: config.appearance.theme?.button_color ?? "#6366f1")
    }

    var body: some View {
        VStack(spacing: 16) {
            // Progress indicator
            if config.appearance.show_progress && !visibleQuestions.isEmpty {
                ProgressView(value: Double(currentQuestionIndex + 1), total: Double(visibleQuestions.count))
                    .tint(accentColor)
            }

            Spacer()

            // Current question
            if currentQuestionIndex < visibleQuestions.count {
                questionView(for: visibleQuestions[currentQuestionIndex])
                    .foregroundColor(textColor)
            }

            Spacer()

            // Navigation buttons
            HStack {
                if currentQuestionIndex > 0 {
                    Button("Back") {
                        currentQuestionIndex -= 1
                    }
                    .foregroundColor(accentColor)
                }

                Spacer()

                if currentQuestionIndex < visibleQuestions.count - 1 {
                    Button("Next") {
                        advanceQuestion()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(canAdvance ? buttonColor : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(!canAdvance)
                } else {
                    Button("Submit") {
                        submitSurvey()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(canAdvance ? buttonColor : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(!canAdvance)
                }
            }

            // Dismiss button
            if config.appearance.dismiss_allowed {
                Button("Not now") {
                    let answered = answers.count
                    dismiss()
                    completion(.dismissed(answeredCount: answered))
                }
                .foregroundColor(.secondary)
                .font(.footnote)
            }
        }
        .padding()
        .background(backgroundColor)
        .accentColor(accentColor)
        .onAppear { computeVisibleQuestions() }
    }

    // MARK: - Question routing

    @ViewBuilder
    func questionView(for question: SurveyQuestion) -> some View {
        let binding = answerBinding(for: question)

        switch question.type {
        case "nps":
            NPSQuestionView(question: question, answer: binding)
        case "csat":
            CSATQuestionView(question: question, answer: binding)
        case "rating":
            RatingQuestionView(question: question, answer: binding)
        case "single_choice":
            SingleChoiceView(question: question, answer: binding)
        case "multi_choice":
            MultiChoiceView(question: question, answer: binding)
        case "free_text":
            FreeTextView(question: question, answer: binding)
        case "yes_no":
            YesNoView(question: question, answer: binding)
        case "emoji_scale":
            EmojiScaleView(question: question, answer: binding)
        default:
            EmptyView()
        }
    }

    // MARK: - Logic

    private var canAdvance: Bool {
        guard currentQuestionIndex < visibleQuestions.count else { return false }
        let q = visibleQuestions[currentQuestionIndex]
        if q.required {
            return answers[q.id] != nil
        }
        return true
    }

    private func advanceQuestion() {
        computeVisibleQuestions()
        if currentQuestionIndex < visibleQuestions.count - 1 {
            currentQuestionIndex += 1
        }
    }

    private func submitSurvey() {
        let allAnswers = visibleQuestions.compactMap { answers[$0.id] }
        dismiss()
        completion(.completed(answers: allAnswers))
    }

    func computeVisibleQuestions() {
        visibleQuestions = config.questions.filter { question in
            guard let showIf = question.show_if else { return true }
            guard let prevAnswer = answers[showIf.question_id] else { return false }

            return showIf.answer_in.contains(where: { condValue in
                matches(prevAnswer.answer, condValue.value)
            })
        }
    }

    private func matches(_ answer: Any, _ condValue: Any) -> Bool {
        "\(answer)" == "\(condValue)"
    }

    private func answerBinding(for question: SurveyQuestion) -> Binding<SurveyAnswer?> {
        Binding(
            get: { answers[question.id] },
            set: { newValue in
                answers[question.id] = newValue
                // Track individual question answer
                if let answer = newValue {
                    onQuestionAnswered?(config.name, question, answer)
                }
                // Recompute visible questions when answers change (for conditional show_if)
                computeVisibleQuestions()
            }
        )
    }
}

