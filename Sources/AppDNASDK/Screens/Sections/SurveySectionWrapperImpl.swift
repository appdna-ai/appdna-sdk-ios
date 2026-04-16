import SwiftUI

// MARK: - Survey section renderer (Screens SDUI)
//
// Sprint C6 (iOS SDK v1.0.52): Replaces the placeholder SurveySectionWrapper
// with real renderers that reuse the SurveyViews sub-views (NPS, CSAT,
// rating, single/multi choice, free text) introduced by SurveyRenderer.
//
// Supported section types:
//   survey_question  — generic question, dispatches on `type` field in data
//   survey_nps       — 0-10 likelihood scale
//   survey_csat      — satisfaction scale
//   survey_rating    — star/heart/thumb rating
//   survey_free_text — multi-line input
//   survey_thank_you — thank-you message + completion action
//
// Each renderer dispatches the captured answer through a `survey_answer`
// SectionAction.custom event so the host flow can persist it alongside
// any other state it tracks. `survey_thank_you` dispatches `.next` when
// the CTA is tapped so the flow advances.

enum SurveySectionWrapperImpl {

    static func decodeQuestion(_ raw: [String: AnyCodable]?) -> SurveyQuestion? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        do {
            let json = try JSONEncoder().encode(raw)
            return try JSONDecoder().decode(SurveyQuestion.self, from: json)
        } catch {
            return nil
        }
    }

    @ViewBuilder
    static func render(section: ScreenSection, context: SectionContext) -> some View {
        switch section.type ?? "unknown" {
        case "survey_thank_you":
            SurveyThankYouView(section: section, context: context)
        default:
            SurveyQuestionView(section: section, context: context)
        }
    }

    static func resolvedQuestionType(section: ScreenSection) -> String {
        if let t = section.data?["type"]?.value as? String, !t.isEmpty { return t }
        switch section.type ?? "" {
        case "survey_nps":       return "nps"
        case "survey_csat":      return "csat"
        case "survey_rating":    return "rating"
        case "survey_free_text": return "free_text"
        default:                 return "free_text"
        }
    }
}

private struct SurveyQuestionView: View {
    let section: ScreenSection
    let context: SectionContext

    @State private var answer: SurveyAnswer?

    var body: some View {
        let question = buildQuestion()
        // SectionContext is a value type so we can't mutate `responses`
        // from here; instead we dispatch a `survey_answer` custom action
        // with the stringified value. Host flows that need the typed
        // answer can subscribe to the action and record it themselves.
        let binding = Binding<SurveyAnswer?>(
            get: { answer },
            set: { newValue in
                answer = newValue
                if let nv = newValue {
                    let key = section.id ?? question.id ?? ""
                    let stringValue = "\(nv.answer)"
                    context.onAction(.custom(type: "survey_answer:\(key)", value: stringValue))
                }
            }
        )

        VStack(alignment: .leading, spacing: 12) {
            switch question.type ?? "" {
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
                if let text = question.text {
                    Text(text).font(.body)
                }
            }
        }
    }

    private func buildQuestion() -> SurveyQuestion {
        if let decoded = SurveySectionWrapperImpl.decodeQuestion(section.data) {
            if decoded.type == nil || decoded.type?.isEmpty == true {
                return SurveyQuestion(
                    id: decoded.id ?? section.id,
                    type: SurveySectionWrapperImpl.resolvedQuestionType(section: section),
                    text: decoded.text,
                    required: decoded.required,
                    show_if: decoded.show_if,
                    nps_config: decoded.nps_config,
                    csat_config: decoded.csat_config,
                    rating_config: decoded.rating_config,
                    options: decoded.options,
                    emoji_config: decoded.emoji_config,
                    free_text_config: decoded.free_text_config,
                    image_url: decoded.image_url
                )
            }
            return decoded
        }
        let text = section.data?["text"]?.value as? String
        return SurveyQuestion(
            id: section.id,
            type: SurveySectionWrapperImpl.resolvedQuestionType(section: section),
            text: text,
            required: nil,
            show_if: nil,
            nps_config: nil,
            csat_config: nil,
            rating_config: nil,
            options: nil,
            emoji_config: nil,
            free_text_config: nil,
            image_url: nil
        )
    }
}

private struct SurveyThankYouView: View {
    let section: ScreenSection
    let context: SectionContext

    var body: some View {
        let title = (section.data?["title"]?.value as? String) ?? "Thank you!"
        let body = (section.data?["body"]?.value as? String)
            ?? (section.data?["text"]?.value as? String)
        let ctaText = (section.data?["cta_text"]?.value as? String) ?? "Done"

        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(hex: "#22C55E"))
            Text(title).font(.title2.bold()).multilineTextAlignment(.center)
            if let body = body {
                Text(body).font(.body).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            Button {
                context.onAction(.next)
            } label: {
                Text(ctaText)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "#6366F1"))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}
