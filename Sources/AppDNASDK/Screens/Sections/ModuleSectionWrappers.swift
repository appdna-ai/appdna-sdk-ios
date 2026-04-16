import SwiftUI

// MARK: - Module section wrappers
//
// Registers renderers for section types that belong to specific product
// modules (paywalls, surveys, in-app messages, onboarding). Each wrapper
// delegates to a *Impl file with the real rendering logic — kept separate
// so the 24 paywall / 6 survey / 3 message / 3 onboarding branches don't
// live in a single mega-switch.
//
// Sprint C6 (iOS SDK v1.0.52): The paywall, survey, and message wrappers
// used to render a single `Text(section.type)` placeholder. They now
// delegate to real content renderers that reuse the existing module
// components (HeaderSection, BannerView, NPSQuestionView, etc.).

internal enum PaywallSectionWrapper: SectionRenderer {
    static func render(section: ScreenSection, context: SectionContext) -> AnyView {
        AnyView(PaywallSectionWrapperImpl.render(section: section, context: context))
    }
}

internal enum SurveySectionWrapper: SectionRenderer {
    static func render(section: ScreenSection, context: SectionContext) -> AnyView {
        AnyView(SurveySectionWrapperImpl.render(section: section, context: context))
    }
}

internal enum MessageSectionWrapper: SectionRenderer {
    static func render(section: ScreenSection, context: SectionContext) -> AnyView {
        AnyView(MessageSectionWrapperImpl.render(section: section, context: context))
    }
}

// Onboarding section wrapper — unchanged.
internal enum OnboardingSectionWrapper: SectionRenderer {
    static func render(section: ScreenSection, context: SectionContext) -> AnyView {
        switch section.type ?? "unknown" {
        case "onboarding_step":
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

extension SectionRegistry {
    func registerModuleSections() {
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

        let surveyTypes = [
            "survey_question", "survey_nps", "survey_csat",
            "survey_rating", "survey_free_text", "survey_thank_you",
        ]
        for type in surveyTypes {
            register(type, renderer: SurveySectionWrapper.self)
        }

        let messageTypes = ["message_banner", "message_modal", "message_content"]
        for type in messageTypes {
            register(type, renderer: MessageSectionWrapper.self)
        }

        let onboardingTypes = ["onboarding_step", "progress_indicator", "navigation_controls"]
        for type in onboardingTypes {
            register(type, renderer: OnboardingSectionWrapper.self)
        }
    }
}
