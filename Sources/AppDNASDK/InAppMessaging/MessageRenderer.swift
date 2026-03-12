import SwiftUI

/// Routes to the appropriate message view based on message_type.
/// SPEC-088: Interpolates all text fields via TemplateEngine before rendering.
struct MessageRenderer: View {
    let messageId: String
    let config: MessageConfig
    let onCTATap: () -> Void
    let onDismiss: () -> Void

    /// Interpolated content with template variables resolved (SPEC-088).
    private var interpolatedContent: MessageContent {
        let ctx = TemplateEngine.shared.buildContext()
        let e = TemplateEngine.shared
        return MessageContent(
            title: config.content.title.map { e.interpolate($0, context: ctx) },
            body: config.content.body.map { e.interpolate($0, context: ctx) },
            image_url: config.content.image_url,
            cta_text: config.content.cta_text.map { e.interpolate($0, context: ctx) },
            cta_action: config.content.cta_action,
            dismiss_text: config.content.dismiss_text.map { e.interpolate($0, context: ctx) },
            background_color: config.content.background_color,
            banner_position: config.content.banner_position,
            auto_dismiss_seconds: config.content.auto_dismiss_seconds,
            text_color: config.content.text_color,
            button_color: config.content.button_color,
            corner_radius: config.content.corner_radius,
            secondary_cta_text: config.content.secondary_cta_text.map { e.interpolate($0, context: ctx) },
            lottie_url: config.content.lottie_url,
            rive_url: config.content.rive_url,
            rive_state_machine: config.content.rive_state_machine,
            video_url: config.content.video_url,
            video_thumbnail_url: config.content.video_thumbnail_url,
            cta_icon: config.content.cta_icon,
            secondary_cta_icon: config.content.secondary_cta_icon,
            haptic: config.content.haptic,
            particle_effect: config.content.particle_effect,
            blur_backdrop: config.content.blur_backdrop
        )
    }

    var body: some View {
        let content = interpolatedContent
        switch config.message_type {
        case .banner:
            BannerView(content: content, onCTATap: onCTATap, onDismiss: onDismiss)
        case .modal:
            ModalView(content: content, onCTATap: onCTATap, onDismiss: onDismiss)
        case .fullscreen:
            FullscreenView(content: content, onCTATap: onCTATap, onDismiss: onDismiss)
        case .tooltip:
            TooltipView(content: content, onCTATap: onCTATap, onDismiss: onDismiss)
        }
    }
}
