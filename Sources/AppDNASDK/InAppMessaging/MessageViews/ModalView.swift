import SwiftUI

/// Centered modal message with overlay backdrop.
struct ModalView: View {
    let content: MessageContent
    let onCTATap: () -> Void
    let onDismiss: () -> Void

    @State private var showConfetti = false

    var body: some View {
        ZStack {
            // Backdrop — SPEC-085: blur backdrop support
            if let blurConfig = content.blur_backdrop {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .background(.ultraThinMaterial)
                    .blur(radius: CGFloat(blurConfig.radius ?? 0) / 3)
                    .onTapGesture { onDismiss() }
            } else {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }
            }

            // Modal card
            VStack(spacing: 16) {
                // Dismiss button
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                    }
                }
                .padding(.trailing, -4)

                // SPEC-085: Lottie hero (takes priority over image)
                if let lottieUrl = content.lottie_url {
                    LottieBlockView(block: LottieBlock(
                        lottie_url: lottieUrl, lottie_json: nil,
                        autoplay: true, loop: true, speed: 1.0,
                        width: nil, height: 160, alignment: "center",
                        play_on_scroll: nil, play_on_tap: nil, color_overrides: nil
                    ))
                }
                // SPEC-085: Rive hero
                else if let riveUrl = content.rive_url {
                    RiveBlockView(block: RiveBlock(
                        rive_url: riveUrl, artboard: nil,
                        state_machine: content.rive_state_machine,
                        autoplay: true, height: 160, alignment: "center",
                        inputs: nil, trigger_on_step_complete: nil
                    ))
                }
                // Optional image
                else if let urlString = content.image_url, let url = URL(string: urlString) {
                    BundledAsyncPhaseImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                // Title — SPEC-084: apply text_color
                if let title = content.title {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundColor(content.text_color.map { Color(hex: $0) } ?? .primary)
                        .multilineTextAlignment(.center)
                }

                // Body — SPEC-084: apply text_color
                if let body = content.body {
                    Text(body)
                        .font(.body)
                        .foregroundColor(content.text_color.map { Color(hex: $0).opacity(0.7) } ?? .secondary)
                        .multilineTextAlignment(.center)
                }

                // CTA button — SPEC-084: apply button_color, corner_radius
                if let ctaText = content.cta_text {
                    Button {
                        HapticEngine.triggerIfEnabled(content.haptic?.triggers?.on_button_tap, config: content.haptic)
                        onCTATap()
                    } label: {
                        HStack(spacing: 6) {
                            // SPEC-085: CTA icon
                            if let icon = content.cta_icon {
                                IconView(ref: icon, size: 16)
                            }
                            Text(ctaText)
                        }
                        .font(.headline)
                        .foregroundColor(Color(hex: content.button_text_color ?? "#FFFFFF"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(hex: content.button_color ?? "#6366F1"))
                        .cornerRadius(CGFloat(content.button_corner_radius ?? 8))
                    }
                }

                // Secondary CTA (Gap #18)
                if let secondaryText = content.secondary_cta_text {
                    Button(action: { onDismiss() }) {
                        HStack(spacing: 4) {
                            if let icon = content.secondary_cta_icon {
                                IconView(ref: icon, size: 12)
                            }
                            Text(secondaryText)
                        }
                        .font(.caption)
                        .foregroundColor(content.text_color.map { Color(hex: $0).opacity(0.6) } ?? .secondary)
                    }
                }

                // Dismiss text
                if let dismissText = content.dismiss_text {
                    Button(dismissText, action: onDismiss)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: CGFloat(content.corner_radius ?? 12))
                    .fill(Color(hex: content.background_color ?? "#FFFFFF"))
            )
            .applyBlurBackdrop(content.blur_backdrop)
            .padding(.horizontal, 32)

            // SPEC-085: Confetti overlay
            if showConfetti, let effect = content.particle_effect {
                ConfettiOverlay(effect: effect)
            }
        }
        .onAppear {
            // SPEC-085: Haptic on appear
            HapticEngine.triggerIfEnabled(content.haptic?.triggers?.on_button_tap, config: content.haptic)
            // SPEC-085: Particle effect on appear
            if let effect = content.particle_effect, effect.trigger == "on_appear" {
                showConfetti = true
            }
        }
    }
}
