import SwiftUI

// MARK: - Paywall Section Wrappers (24 types)
// These wrap existing PaywallRenderer section views as SDUI section registry entries.

internal enum PaywallSectionWrapper: SectionRenderer {
    static func render(section: ScreenSection, context: SectionContext) -> AnyView {
        // Paywall sections delegate to the existing paywall section renderer
        // The section.data contains PaywallSectionData-compatible JSON
        return AnyView(
            VStack(spacing: 8) {
                Text("[\(section.type ?? "unknown")]")
                    .font(.caption)
                    .foregroundColor(.secondary)
                // In production, this would call the actual PaywallRenderer section view
                // For now, render a placeholder that shows the section type
                if let title = section.data?["title"]?.value as? String {
                    Text(title).font(.headline)
                }
                if let subtitle = section.data?["subtitle"]?.value as? String {
                    Text(subtitle).font(.subheadline).foregroundColor(.secondary)
                }
            }
            .padding()
        )
    }
}

// MARK: - Survey Section Wrappers (6 types)

internal enum SurveySectionWrapper: SectionRenderer {
    static func render(section: ScreenSection, context: SectionContext) -> AnyView {
        return AnyView(
            VStack(spacing: 8) {
                if let questionText = section.data?["text"]?.value as? String {
                    Text(questionText).font(.body)
                }
                // Survey sections capture responses into context.responses
                // In production, this would render the actual survey question UI
                Text("[\(section.type ?? "unknown") section]")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        )
    }
}

// MARK: - Message Section Wrappers (3 types)

internal enum MessageSectionWrapper: SectionRenderer {
    static func render(section: ScreenSection, context: SectionContext) -> AnyView {
        return AnyView(
            VStack(spacing: 8) {
                if let title = section.data?["title"]?.value as? String {
                    Text(title).font(.headline)
                }
                if let body = section.data?["body"]?.value as? String {
                    Text(body).font(.body)
                }
            }
            .padding()
        )
    }
}

// MARK: - Onboarding Section Wrappers (3 types)

internal enum OnboardingSectionWrapper: SectionRenderer {
    static func render(section: ScreenSection, context: SectionContext) -> AnyView {
        switch section.type ?? "unknown" {
        case "onboarding_step":
            // Render content blocks from step config
            let blocks = section.data?["content_blocks"]?.value
            if blocks != nil {
                return ContentBlocksSectionRenderer.render(
                    section: ScreenSection(
                        id: section.id,
                        type: "content_blocks",
                        data: ["blocks": section.data?["content_blocks"] ?? AnyCodable([])],
                        style: section.style,
                        visibility_condition: section.visibility_condition,
                        entrance_animation: section.entrance_animation,
                        a11y: section.a11y
                    ),
                    context: context
                )
            }
            return AnyView(EmptyView())

        case "progress_indicator":
            let current = section.data?["current"]?.value as? Int ?? context.currentScreenIndex
            let total = section.data?["total"]?.value as? Int ?? context.totalScreens
            return AnyView(
                HStack(spacing: 4) {
                    ForEach(0..<total, id: \.self) { i in
                        Capsule()
                            .fill(i <= current ? Color.blue : Color.gray.opacity(0.3))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 20)
            )

        case "navigation_controls":
            let showBack = section.data?["show_back"]?.value as? Bool ?? true
            let showSkip = section.data?["show_skip"]?.value as? Bool ?? false
            let ctaText = section.data?["cta_text"]?.value as? String ?? "Next"

            return AnyView(
                HStack {
                    if showBack {
                        Button("Back") { context.onAction(.back) }
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if showSkip {
                        Button("Skip") { context.onAction(.next) }
                            .foregroundColor(.secondary)
                    }
                    Button(ctaText) { context.onAction(.next) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            )

        default:
            return AnyView(EmptyView())
        }
    }
}

// MARK: - Registration Extension

extension SectionRegistry {
    func registerModuleSections() {
        // Paywall sections (24 types)
        let paywallTypes = [
            "paywall_header", "paywall_features", "paywall_plans", "paywall_cta",
            "paywall_social_proof", "paywall_guarantee", "paywall_testimonial",
            "paywall_countdown", "paywall_legal", "paywall_comparison",
            "paywall_promo", "paywall_reviews", "paywall_toggle",
            "paywall_icon_grid", "paywall_carousel", "paywall_card",
            "paywall_timeline", "paywall_image", "paywall_video",
            "paywall_lottie", "paywall_rive", "paywall_spacer",
            "paywall_divider", "paywall_sticky_footer",
        ]
        for type in paywallTypes {
            register(type, renderer: PaywallSectionWrapper.self)
        }

        // Survey sections (6 types)
        let surveyTypes = [
            "survey_question", "survey_nps", "survey_csat",
            "survey_rating", "survey_free_text", "survey_thank_you",
        ]
        for type in surveyTypes {
            register(type, renderer: SurveySectionWrapper.self)
        }

        // Message sections (3 types)
        let messageTypes = ["message_banner", "message_modal", "message_content"]
        for type in messageTypes {
            register(type, renderer: MessageSectionWrapper.self)
        }

        // Onboarding sections (3 types)
        let onboardingTypes = ["onboarding_step", "progress_indicator", "navigation_controls"]
        for type in onboardingTypes {
            register(type, renderer: OnboardingSectionWrapper.self)
        }
    }
}
