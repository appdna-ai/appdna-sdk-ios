import SwiftUI

/// Schema-driven SwiftUI view that renders a PaywallConfig.
struct PaywallRenderer: View {
    let config: PaywallConfig
    let onPlanSelected: (PaywallPlan) -> Void
    let onRestore: () -> Void
    let onDismiss: (DismissReason) -> Void

    @State private var selectedPlanId: String?
    @State private var showDismiss = false
    @State private var isPurchasing = false
    @State private var isDismissing = false
    @State private var dragOffset: CGFloat = 0
    // SPEC-085: Particle effect state
    @State private var showConfetti = false

    // SPEC-084: Localization helper
    private func loc(_ key: String, _ fallback: String) -> String {
        LocalizationEngine.resolve(key: key, localizations: config.localizations, defaultLocale: config.default_locale, fallback: fallback)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            backgroundView

            ScrollView {
                VStack(spacing: config.layout.spacing ?? 16) {
                    ForEach(Array(config.sections.enumerated()), id: \.offset) { _, section in
                        sectionView(for: section)
                    }
                }
                .padding(config.layout.padding ?? 20)
            }

            // SPEC-085: Confetti/particle overlay
            if showConfetti, let effect = config.particle_effect {
                ConfettiOverlay(effect: effect)
            }

            // Dismiss control
            if showDismiss {
                let dismissType = config.dismiss?.type ?? "x_button"
                switch dismissType {
                case "text_link":
                    VStack {
                        Spacer()
                        Button {
                            triggerDismiss()
                        } label: {
                            Text(loc("dismiss.text", config.dismiss?.text ?? "No thanks"))
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.bottom, 24)
                    }
                case "swipe_down":
                    VStack {
                        Capsule()
                            .fill(Color.white.opacity(0.5))
                            .frame(width: 36, height: 5)
                            .padding(.top, 8)
                        Spacer()
                    }
                default: // x_button
                    dismissButton
                }
            }
        }
        .dismissAnimation(config.animation?.dismiss_animation, isDismissing: isDismissing)
        .entryAnimation(config.animation?.entry_animation, durationMs: config.animation?.entry_duration_ms)
        .onAppear {
            // Select default plan
            if let sections = config.sections.first(where: { $0.type == "plans" }),
               let plans = sections.data?.plans {
                selectedPlanId = plans.first(where: { $0.isDefault == true })?.id ?? plans.first?.id
            }

            // Handle dismiss delay
            let delay = config.dismiss?.delaySeconds ?? 0
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay)) {
                    withAnimation { showDismiss = true }
                }
            } else {
                showDismiss = true
            }
        }
        .gesture(
            config.dismiss?.type == "swipe_down" ?
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 150 {
                        triggerDismiss()
                    } else {
                        withAnimation { dragOffset = 0 }
                    }
                }
            : nil
        )
        .offset(y: dragOffset)
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundView: some View {
        switch config.background?.type {
        case "gradient":
            if let colors = config.background?.colors, colors.count >= 2 {
                LinearGradient(
                    colors: colors.map { Color(hex: $0) },
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
        case "image":
            if let urlString = config.background?.value, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.black
                }
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
        case "video":
            // SPEC-085: Video background
            ZStack {
                Color.black.ignoresSafeArea()
                if let videoUrlStr = config.background?.video_url ?? config.background?.value,
                   let videoUrl = URL(string: videoUrlStr) {
                    VideoBackgroundView(url: videoUrl)
                        .ignoresSafeArea()
                }
            }
        case "color":
            Color(hex: config.background?.value ?? "#000000")
                .ignoresSafeArea()
        default:
            Color(.systemBackground).ignoresSafeArea()
        }
    }

    // MARK: - Dismiss helpers

    private func triggerDismiss() {
        if config.animation?.dismiss_animation != nil {
            isDismissing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onDismiss(.dismissed)
            }
        } else {
            onDismiss(.dismissed)
        }
    }

    private var dismissButton: some View {
        Button {
            triggerDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.3))
                .clipShape(Circle())
        }
        .padding(16)
        .transition(.opacity)
    }

    // MARK: - Section rendering

    @ViewBuilder
    private func sectionView(for section: PaywallSection) -> some View {
        let staggerDelay = config.animation?.section_stagger_delay_ms ?? 0

        Group {
            switch section.type {
            case "header":
                HeaderSection(data: section.data, loc: loc, sectionStyle: section.style)
                    .applyContainerStyle(section.style?.container)
            case "features":
                FeatureList(features: (section.data?.features ?? []).enumerated().map { i, f in loc("feature.\(i)", f) }, sectionStyle: section.style)
                    .applyContainerStyle(section.style?.container)
            case "plans":
                plansSection(plans: section.data?.plans ?? [], style: section.style)
                    .applyContainerStyle(section.style?.container)
            case "cta":
                CTAButton(
                    cta: section.data?.cta,
                    isPurchasing: isPurchasing,
                    onTap: handleCTATap,
                    loc: loc,
                    sectionStyle: section.style
                )
                .ctaAnimation(config.animation?.cta_animation)
                .applyContainerStyle(section.style?.container)
            case "social_proof":
                socialProofSection(data: section.data, style: section.style)
                    .applyContainerStyle(section.style?.container)
            case "guarantee":
                if let text = section.data?.guaranteeText {
                    let ts = section.style?.elements?["text"]?.textStyle
                    Text(loc("guarantee.text", text))
                        .applyTextStyle(ts)
                        .font(ts == nil ? .caption : nil)
                        .foregroundColor(ts?.color == nil ? .secondary : nil)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .applyContainerStyle(section.style?.container)
                }
            // SPEC-084: Missing sections
            case "image":
                imageSectionView(data: section.data, style: section.style)
            case "spacer":
                Spacer().frame(height: section.data?.spacerHeight ?? 24)
            case "testimonial":
                testimonialSectionView(data: section.data, style: section.style)
            // SPEC-085: Rich media sections
            case "lottie":
                lottieSectionView(data: section.data, style: section.style)
            case "video":
                videoSectionView(data: section.data, style: section.style)
            case "rive":
                riveSectionView(data: section.data, style: section.style)
            default:
                EmptyView()
            }
        }
        .sectionStagger(config.animation?.section_stagger, delayMs: staggerDelay)
    }

    // MARK: - SPEC-084: Social proof with sub-types

    @ViewBuilder
    private func socialProofSection(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        switch data?.subType {
        case "countdown":
            CountdownTimerView(seconds: data?.countdownSeconds ?? 86400, valueTextStyle: style?.elements?["value"]?.textStyle)
        case "trial_badge":
            if let ts = style?.elements?["value"]?.textStyle {
                Text(loc("social_proof.trial_badge", data?.text ?? "Free Trial"))
                    .applyTextStyle(ts)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            } else {
                Text(loc("social_proof.trial_badge", data?.text ?? "Free Trial"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())
            }
        default: // app_rating
            SocialProof(data: data, loc: loc, sectionStyle: style)
        }
    }

    // MARK: - SPEC-084: Image section

    @ViewBuilder
    private func imageSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        if let urlString = data?.imageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxHeight: data?.height ?? 240)
                        .clipShape(RoundedRectangle(cornerRadius: data?.cornerRadius ?? 12))
                default:
                    ProgressView().frame(height: data?.height ?? 240)
                }
            }
            .applyContainerStyle(style?.container)
        }
    }

    // MARK: - SPEC-084: Testimonial section

    private func testimonialSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        let quoteTextStyle = style?.elements?["quote"]?.textStyle
        let authorNameTextStyle = style?.elements?["author_name"]?.textStyle
        let authorRoleTextStyle = style?.elements?["author_role"]?.textStyle

        return VStack(spacing: 12) {
            Text("\u{201C}")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.accentColor)

            if let ts = quoteTextStyle {
                Text(loc("testimonial.quote", data?.quote ?? data?.testimonial ?? ""))
                    .applyTextStyle(ts)
            } else {
                Text(loc("testimonial.quote", data?.quote ?? data?.testimonial ?? ""))
                    .italic()
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.9))
            }

            HStack(spacing: 12) {
                if let avatarUrl = data?.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else if let name = data?.authorName {
                    Circle()
                        .fill(Color.accentColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(initials(name))
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let name = data?.authorName {
                        if let ts = authorNameTextStyle {
                            Text(name)
                                .applyTextStyle(ts)
                        } else {
                            Text(name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                        }
                    }
                    if let role = data?.authorRole {
                        if let ts = authorRoleTextStyle {
                            Text(role)
                                .applyTextStyle(ts)
                        } else {
                            Text(role)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                }
            }
        }
        .applyContainerStyle(style?.container)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first.map { String($0.prefix(1)) } ?? ""
        let last = parts.count > 1 ? String(parts.last!.prefix(1)) : ""
        return (first + last).uppercased()
    }

    // MARK: - SPEC-085: Lottie section

    @ViewBuilder
    private func lottieSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        if let lottieUrl = data?.lottieUrl {
            let block = LottieBlock(
                lottie_url: lottieUrl,
                lottie_json: nil,
                autoplay: true,
                loop: data?.lottieLoop ?? true,
                speed: data?.lottieSpeed ?? 1.0,
                width: nil,
                height: Double(data?.lottieHeight ?? data?.height ?? 180),
                alignment: "center",
                play_on_scroll: nil,
                play_on_tap: nil,
                color_overrides: nil
            )
            LottieBlockView(block: block)
                .applyContainerStyle(style?.container)
        }
    }

    // MARK: - SPEC-085: Video section

    @ViewBuilder
    private func videoSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        if let videoUrl = data?.videoUrl {
            let block = VideoBlock(
                video_url: videoUrl,
                video_thumbnail_url: data?.videoThumbnailUrl ?? data?.imageUrl,
                video_height: Double(data?.videoHeight ?? data?.height ?? 200),
                video_corner_radius: Double(data?.cornerRadius ?? 12),
                autoplay: false,
                loop: false,
                muted: true,
                controls: true,
                inline_playback: true
            )
            VideoBlockView(block: block)
                .applyContainerStyle(style?.container)
        }
    }

    // MARK: - SPEC-085: Rive section

    @ViewBuilder
    private func riveSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        if let riveUrl = data?.riveUrl {
            let block = RiveBlock(
                rive_url: riveUrl,
                artboard: nil,
                state_machine: data?.riveStateMachine,
                autoplay: true,
                height: Double(data?.height ?? 180),
                alignment: "center",
                inputs: nil,
                trigger_on_step_complete: nil
            )
            RiveBlockView(block: block)
                .applyContainerStyle(style?.container)
        }
    }

    // MARK: - Plans

    // SPEC-084: Grid/carousel/stack plan layouts
    @ViewBuilder
    private func plansSection(plans: [PaywallPlan], style: SectionStyleConfig? = nil) -> some View {
        let layoutType = config.layout.type

        VStack(spacing: 12) {
            switch layoutType {
            case "grid":
                // Side-by-side plan cards
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                        PlanCard(
                            plan: plan,
                            isSelected: selectedPlanId == plan.id,
                            onSelect: { selectedPlanId = plan.id; HapticEngine.triggerIfEnabled(config.haptic?.triggers.on_plan_select, config: config.haptic) },
                            planIndex: index,
                            loc: loc,
                            sectionStyle: style
                        )
                        .planSelection(config.animation?.plan_selection_animation, isSelected: selectedPlanId == plan.id)
                    }
                }

            case "carousel":
                // Swipeable horizontal plan cards
                TabView {
                    ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                        PlanCard(
                            plan: plan,
                            isSelected: selectedPlanId == plan.id,
                            onSelect: { selectedPlanId = plan.id; HapticEngine.triggerIfEnabled(config.haptic?.triggers.on_plan_select, config: config.haptic) },
                            planIndex: index,
                            loc: loc,
                            sectionStyle: style
                        )
                        .planSelection(config.animation?.plan_selection_animation, isSelected: selectedPlanId == plan.id)
                        .padding(.horizontal, 8)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 140)

            default: // "stack"
                ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                    PlanCard(
                        plan: plan,
                        isSelected: selectedPlanId == plan.id,
                        onSelect: { selectedPlanId = plan.id; HapticEngine.triggerIfEnabled(config.haptic?.triggers.on_plan_select, config: config.haptic) },
                        planIndex: index,
                        loc: loc,
                        sectionStyle: style
                    )
                    .planSelection(config.animation?.plan_selection_animation, isSelected: selectedPlanId == plan.id)
                }
            }

            Button(loc("restore.text", "Restore Purchases")) {
                onRestore()
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - CTA handler

    private func handleCTATap() {
        guard let planId = selectedPlanId,
              let section = config.sections.first(where: { $0.type == "plans" }),
              let plan = section.data?.plans?.first(where: { $0.id == planId }) else {
            return
        }
        // SPEC-085: Haptic on CTA tap
        HapticEngine.triggerIfEnabled(config.haptic?.triggers.on_button_tap, config: config.haptic)
        // SPEC-085: Trigger particle effect on purchase
        if let effect = config.particle_effect, effect.trigger == "on_purchase" {
            showConfetti = true
        }
        isPurchasing = true
        onPlanSelected(plan)
    }
}

// MARK: - Countdown timer (SPEC-084 social proof sub-type)

struct CountdownTimerView: View {
    let seconds: Int
    var valueTextStyle: TextStyleConfig? = nil
    @State private var remaining: Int

    init(seconds: Int, valueTextStyle: TextStyleConfig? = nil) {
        self.seconds = seconds
        self.valueTextStyle = valueTextStyle
        self._remaining = State(initialValue: seconds)
    }

    var body: some View {
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let secs = remaining % 60

        HStack(spacing: 4) {
            timeUnit(hours, label: "h")
            Text(":").foregroundColor(.white.opacity(0.6))
            timeUnit(minutes, label: "m")
            Text(":").foregroundColor(.white.opacity(0.6))
            timeUnit(secs, label: "s")
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                if remaining > 0 {
                    remaining -= 1
                } else {
                    timer.invalidate()
                }
            }
        }
    }

    private func timeUnit(_ value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            if let ts = valueTextStyle {
                Text(String(format: "%02d", value))
                    .applyTextStyle(ts)
                    .monospacedDigit()
            } else {
                Text(String(format: "%02d", value))
                    .font(.title2.monospacedDigit().bold())
                    .foregroundColor(.white)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(minWidth: 40)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - SPEC-085: Video background view

import AVKit

struct VideoBackgroundView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .disabled(true)  // No controls for background
                    .onAppear {
                        player.isMuted = true
                        player.play()
                        // Loop the video
                        NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: player.currentItem,
                            queue: .main
                        ) { _ in
                            player.seek(to: .zero)
                            player.play()
                        }
                    }
            } else {
                Color.black
            }
        }
        .onAppear {
            player = AVPlayer(url: url)
        }
    }
}
