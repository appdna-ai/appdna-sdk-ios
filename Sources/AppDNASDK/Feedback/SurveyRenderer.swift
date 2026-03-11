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
    // SPEC-085: Rich media state
    @State private var showIntro = true
    @State private var showThankYou = false
    @State private var showConfetti = false

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

    /// SPEC-084: Resolve font from theme
    private var themeFont: Font? {
        guard let fontFamily = config.appearance.theme?.font_family else { return nil }
        return FontResolver.font(family: fontFamily, size: nil, weight: nil)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                // SPEC-085: Intro Lottie animation
                if showIntro, let introUrl = config.appearance.theme?.intro_lottie_url {
                    LottieBlockView(block: LottieBlock(
                        lottie_url: introUrl, lottie_json: nil,
                        autoplay: true, loop: false, speed: 1.0,
                        width: nil, height: 120, alignment: "center",
                        play_on_scroll: nil, play_on_tap: nil, color_overrides: nil
                    ))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation { showIntro = false }
                        }
                    }
                }

                // SPEC-085: Thank-you screen with Lottie + confetti
                if showThankYou {
                    VStack(spacing: 16) {
                        if let thankUrl = config.appearance.theme?.thankyou_lottie_url {
                            LottieBlockView(block: LottieBlock(
                                lottie_url: thankUrl, lottie_json: nil,
                                autoplay: true, loop: false, speed: 1.0,
                                width: nil, height: 140, alignment: "center",
                                play_on_scroll: nil, play_on_tap: nil, color_overrides: nil
                            ))
                        }
                        Text("Thank you!")
                            .font(.title2.bold())
                            .foregroundColor(textColor)
                    }
                } else if !showIntro || config.appearance.theme?.intro_lottie_url == nil {
                    // Progress indicator
                    if config.appearance.show_progress && !visibleQuestions.isEmpty {
                        ProgressView(value: Double(currentQuestionIndex + 1), total: Double(visibleQuestions.count))
                            .tint(accentColor)
                    }

                    Spacer()

                    // SPEC-085: Question-level image
                    if currentQuestionIndex < visibleQuestions.count,
                       let imageUrl = visibleQuestions[currentQuestionIndex].image_url {
                        MediaImageView(url: imageUrl, maxHeight: 140, cornerRadius: 8)
                            .padding(.horizontal)
                    }

                    // Current question — SPEC-084: apply style engine + theme font
                    if currentQuestionIndex < visibleQuestions.count {
                        questionView(for: visibleQuestions[currentQuestionIndex])
                            .applyTextStyle(config.appearance.question_text_style)
                            .font(themeFont)
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
                                // SPEC-085: Haptic on step advance
                                HapticEngine.triggerIfEnabled(
                                    config.appearance.theme?.haptic?.triggers.on_step_advance,
                                    config: config.appearance.theme?.haptic
                                )
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
            }
            .padding()
            .background(backgroundColor)
            .applyBlurBackdrop(config.appearance.theme?.blur_backdrop)
            .accentColor(accentColor)
            .onAppear {
                computeVisibleQuestions()
                // Skip intro if no lottie URL
                if config.appearance.theme?.intro_lottie_url == nil {
                    showIntro = false
                }
            }

            // SPEC-085: Confetti overlay on completion
            if showConfetti, let effect = config.appearance.theme?.thankyou_particle_effect {
                ConfettiOverlay(effect: effect)
            }
        }
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
            // SPEC-084: Gap #19 — pass option_style from appearance to option card views
            SingleChoiceView(question: question, answer: binding, optionStyle: config.appearance.option_style)
        case "multi_choice":
            // SPEC-084: Gap #19 — pass option_style from appearance to option card views
            MultiChoiceView(question: question, answer: binding, optionStyle: config.appearance.option_style)
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
        // SPEC-085: Haptic on submit
        HapticEngine.triggerIfEnabled(
            config.appearance.theme?.haptic?.triggers.on_form_submit,
            config: config.appearance.theme?.haptic
        )

        let allAnswers = visibleQuestions.compactMap { answers[$0.id] }

        // SPEC-085: Show thank-you animation + confetti if configured
        if config.appearance.theme?.thankyou_lottie_url != nil || config.appearance.theme?.thankyou_particle_effect != nil {
            withAnimation { showThankYou = true }
            if config.appearance.theme?.thankyou_particle_effect != nil {
                showConfetti = true
                HapticEngine.triggerIfEnabled(.success, config: config.appearance.theme?.haptic)
            }
            // Dismiss after thank-you animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                dismiss()
                completion(.completed(answers: allAnswers))
            }
        } else {
            dismiss()
            completion(.completed(answers: allAnswers))
        }
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

