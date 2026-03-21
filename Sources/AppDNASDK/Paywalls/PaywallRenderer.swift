import SwiftUI

/// Schema-driven SwiftUI view that renders a PaywallConfig.
struct PaywallRenderer: View {
    let config: PaywallConfig
    let onPlanSelected: (PaywallPlan, _ metadata: [String: Any]) -> Void
    let onRestore: () -> Void
    let onDismiss: (DismissReason) -> Void
    /// AC-037: Callback for promo code validation. Returns true if code is valid, false otherwise.
    var onPromoCodeSubmit: ((String, @escaping (Bool) -> Void) -> Void)? = nil

    @State private var selectedPlanId: String?
    @State private var showDismiss = false
    @State private var isPurchasing = false
    @State private var isDismissing = false
    @State private var dragOffset: CGFloat = 0
    // SPEC-085: Particle effect state
    @State private var showConfetti = false

    // SPEC-084: Localization helper + SPEC-088: Template variable interpolation
    private func loc(_ key: String, _ fallback: String) -> String {
        let localized = LocalizationEngine.resolve(key: key, localizations: config.localizations, defaultLocale: config.default_locale, fallback: fallback)
        return TemplateEngine.shared.interpolate(localized, context: templateContext)
    }

    // SPEC-088: Cached template context (built once per render cycle)
    private var templateContext: TemplateContext {
        TemplateEngine.shared.buildContext()
    }

    // SPEC-089d: Extract sticky_footer section if present
    private var stickyFooterSection: PaywallSection? {
        config.sections.first(where: { $0.type == "sticky_footer" })
    }

    // SPEC-089d: Toggle state for toggle sections
    @State private var toggleStates: [String: Bool] = [:]
    // SPEC-089d: Promo input state
    @State private var promoCode: String = ""
    @State private var promoState: PromoState = .idle

    var body: some View {
        ZStack(alignment: .topTrailing) {
            backgroundView

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: config.layout.spacing ?? 16) {
                        ForEach(Array(config.sections.enumerated()), id: \.offset) { _, section in
                            sectionView(for: section)
                        }
                    }
                    .padding(config.layout.padding ?? 20)
                }

                // SPEC-089d: Sticky footer pinned to bottom
                if let footer = stickyFooterSection {
                    stickyFooterView(data: footer.data, style: footer.style)
                }
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
            // SPEC-089d: 12 new paywall section types
            case "countdown":
                countdownSectionView(data: section.data, style: section.style)
                    .applyContainerStyle(section.style?.container)
            case "legal":
                legalSectionView(data: section.data, style: section.style)
                    .applyContainerStyle(section.style?.container)
            case "divider":
                dividerSectionView(data: section.data, style: section.style)
            case "sticky_footer":
                EmptyView() // Rendered outside ScrollView — see stickyFooterOverlay
            case "card":
                cardSectionView(data: section.data, style: section.style)
            case "carousel":
                carouselSectionView(data: section.data, style: section.style)
                    .applyContainerStyle(section.style?.container)
            case "timeline":
                timelineSectionView(data: section.data, style: section.style)
                    .applyContainerStyle(section.style?.container)
            case "icon_grid":
                iconGridSectionView(data: section.data, style: section.style)
                    .applyContainerStyle(section.style?.container)
            case "comparison_table":
                comparisonTableSectionView(data: section.data, style: section.style)
                    .applyContainerStyle(section.style?.container)
            case "promo_input":
                promoInputSectionView(data: section.data, style: section.style)
                    .applyContainerStyle(section.style?.container)
            case "toggle":
                toggleSectionView(data: section.data, style: section.style)
                    .applyContainerStyle(section.style?.container)
            case "reviews_carousel":
                reviewsCarouselSectionView(data: section.data, style: section.style)
                    .applyContainerStyle(section.style?.container)
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
                        let interpolatedName = loc("testimonial.author_name", name)
                        if let ts = authorNameTextStyle {
                            Text(interpolatedName)
                                .applyTextStyle(ts)
                        } else {
                            Text(interpolatedName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                        }
                    }
                    if let role = data?.authorRole {
                        let interpolatedRole = loc("testimonial.author_role", role)
                        if let ts = authorRoleTextStyle {
                            Text(interpolatedRole)
                                .applyTextStyle(ts)
                        } else {
                            Text(interpolatedRole)
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

    // MARK: - SPEC-089d: Countdown section (AC-028)

    @ViewBuilder
    private func countdownSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        let duration = data?.durationSeconds ?? data?.countdownSeconds ?? 3600
        let textColor = data?.color ?? data?.accentColor ?? "#FFFFFF"
        let valueTextStyle = style?.elements?["value"]?.textStyle
        CountdownTimerView(seconds: duration, valueTextStyle: valueTextStyle)
    }

    // MARK: - SPEC-089d: Legal section (AC-029)

    @ViewBuilder
    private func legalSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        let textColor = Color(hex: data?.color ?? "#999999")
        let size = data?.fontSize ?? 11
        let textAlignment: TextAlignment = {
            switch data?.alignment {
            case "left": return .leading
            case "right": return .trailing
            default: return .center
            }
        }()

        VStack(spacing: 8) {
            if let text = data?.text {
                // Parse markdown-style links: [text](url)
                Text(parseMarkdownLinks(text))
                    .font(.system(size: size))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(textAlignment)
                    .tint(Color(hex: data?.accentColor ?? "#6366F1"))
            }

            if let links = data?.links, !links.isEmpty {
                HStack(spacing: 16) {
                    ForEach(links, id: \.label) { link in
                        if let url = URL(string: link.url) {
                            Link(link.label, destination: url)
                                .font(.system(size: size))
                                .foregroundColor(Color(hex: data?.accentColor ?? "#6366F1"))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func parseMarkdownLinks(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        // Simple markdown link parser: [label](url)
        let pattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        // Reconstruct attributed string with links
        var attrStr = AttributedString()
        var remaining = text
        while let match = regex.firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)) {
            guard let labelRange = Range(match.range(at: 1), in: remaining),
                  let urlRange = Range(match.range(at: 2), in: remaining),
                  let fullRange = Range(match.range, in: remaining) else { break }
            // Add text before the match
            let beforeText = String(remaining[remaining.startIndex..<fullRange.lowerBound])
            attrStr.append(AttributedString(beforeText))
            // Add the link
            let label = String(remaining[labelRange])
            let urlString = String(remaining[urlRange])
            var linkAttr = AttributedString(label)
            if let url = URL(string: urlString) {
                linkAttr.link = url
            }
            attrStr.append(linkAttr)
            remaining = String(remaining[fullRange.upperBound...])
        }
        if !remaining.isEmpty {
            attrStr.append(AttributedString(remaining))
        }
        return attrStr.characters.isEmpty ? result : attrStr
    }

    // MARK: - SPEC-089d: Divider section (AC-030)

    @ViewBuilder
    private func dividerSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        let dividerColor = Color(hex: data?.color ?? "#333333")
        let thickness = data?.thickness ?? 1
        let lineStyle = data?.lineStyle ?? "solid"
        let mTop = data?.marginTop ?? 8
        let mBottom = data?.marginBottom ?? 8
        let mH = data?.marginHorizontal ?? 0

        VStack(spacing: 0) {
            if let labelText = data?.labelText {
                // Divider with centered label
                HStack(spacing: 12) {
                    dividerLine(color: dividerColor, thickness: thickness, style: lineStyle)
                    Text(labelText)
                        .font(.system(size: data?.labelFontSize ?? 12))
                        .foregroundColor(Color(hex: data?.labelColor ?? "#999999"))
                        .padding(.horizontal, 8)
                        .background(Color(hex: data?.labelBgColor ?? "#000000"))
                    dividerLine(color: dividerColor, thickness: thickness, style: lineStyle)
                }
            } else {
                dividerLine(color: dividerColor, thickness: thickness, style: lineStyle)
            }
        }
        .padding(.top, mTop)
        .padding(.bottom, mBottom)
        .padding(.horizontal, mH)
    }

    @ViewBuilder
    private func dividerLine(color: Color, thickness: CGFloat, style: String) -> some View {
        switch style {
        case "dashed":
            Line()
                .stroke(style: StrokeStyle(lineWidth: thickness, dash: [6, 3]))
                .foregroundColor(color)
                .frame(height: thickness)
        case "dotted":
            Line()
                .stroke(style: StrokeStyle(lineWidth: thickness, dash: [2, 2]))
                .foregroundColor(color)
                .frame(height: thickness)
        default: // solid
            Rectangle()
                .fill(color)
                .frame(height: thickness)
        }
    }

    // MARK: - SPEC-089d: Sticky footer (AC-031)

    @ViewBuilder
    private func stickyFooterView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        let bgColor = Color(hex: data?.backgroundColor ?? "#000000")

        VStack(spacing: 8) {
            // CTA button
            if let ctaText = data?.ctaText {
                Button {
                    handleCTATap()
                } label: {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(loc("sticky_footer.cta", ctaText))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Color(hex: data?.ctaTextColor ?? "#FFFFFF"))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color(hex: data?.ctaBgColor ?? "#6366F1"))
                .clipShape(RoundedRectangle(cornerRadius: data?.ctaCornerRadius ?? 14))
                .disabled(isPurchasing)
            }

            // Secondary action
            if let secondaryText = data?.secondaryText {
                Button {
                    switch data?.secondaryAction {
                    case "restore":
                        onRestore()
                    case "link":
                        if let urlStr = data?.secondaryUrl, let url = URL(string: urlStr) {
                            #if canImport(UIKit)
                            UIApplication.shared.open(url)
                            #endif
                        }
                    default:
                        break
                    }
                } label: {
                    Text(loc("sticky_footer.secondary", secondaryText))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Legal text
            if let legalText = data?.legalText {
                Text(loc("sticky_footer.legal", legalText))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, data?.padding ?? 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            Group {
                if data?.blurBackground == true {
                    Rectangle().fill(.ultraThinMaterial)
                } else {
                    bgColor
                }
            }
        )
        .applyContainerStyle(style?.container)
    }

    // MARK: - SPEC-089d: Card section (AC-032)

    @ViewBuilder
    private func cardSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        let radius = data?.cornerRadius ?? 16

        VStack(alignment: .leading, spacing: 12) {
            if let title = data?.title {
                Text(loc("card.title", title))
                    .font(.headline)
                    .foregroundColor(.white)
            }

            if let subtitle = data?.subtitle {
                Text(loc("card.subtitle", subtitle))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }

            // Render child text/body if present
            if let text = data?.text {
                Text(loc("card.body", text))
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(data?.padding ?? 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: data?.backgroundColor ?? "#1A1A2E"))
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(Color(hex: data?.borderColor ?? "#333333"), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .applyContainerStyle(style?.container)
    }

    // MARK: - SPEC-089d: Carousel section (AC-033)

    @ViewBuilder
    private func carouselSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        if let pages = data?.pages, !pages.isEmpty {
            CarouselView(
                pages: pages,
                config: config,
                autoScroll: data?.autoScroll ?? false,
                autoScrollIntervalMs: data?.autoScrollIntervalMs ?? 3000,
                showIndicators: data?.showIndicators ?? true,
                indicatorColor: data?.indicatorColor ?? "#666666",
                indicatorActiveColor: data?.indicatorActiveColor ?? "#FFFFFF",
                height: data?.height,
                loc: loc
            )
        }
    }

    // MARK: - SPEC-089d: Timeline section (AC-034)

    @ViewBuilder
    private func timelineSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        let items = data?.items ?? []
        let isCompact = data?.compact ?? false
        let showLine = data?.showLine ?? true

        VStack(spacing: isCompact ? 12 : 24) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 16) {
                    // Left: status indicator + connecting line
                    VStack(spacing: 0) {
                        let statusColor = timelineStatusColor(
                            status: item.status ?? "upcoming",
                            completedColor: data?.completedColor ?? "#22C55E",
                            currentColor: data?.currentColor ?? "#6366F1",
                            upcomingColor: data?.upcomingColor ?? "#666666"
                        )

                        ZStack {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 24, height: 24)
                            if item.status == "completed" {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }

                        if showLine && index < items.count - 1 {
                            Rectangle()
                                .fill(Color(hex: data?.lineColor ?? "#333333"))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 24)

                    // Right: content
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = item.title {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                        }
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.bottom, isCompact ? 0 : 8)
                }
            }
        }
    }

    private func timelineStatusColor(status: String, completedColor: String, currentColor: String, upcomingColor: String) -> Color {
        switch status {
        case "completed": return Color(hex: completedColor)
        case "current": return Color(hex: currentColor)
        default: return Color(hex: upcomingColor)
        }
    }

    // MARK: - SPEC-089d: Icon grid section (AC-035)

    @ViewBuilder
    private func iconGridSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        let items = data?.items ?? []
        let columnCount = data?.columns ?? 3
        let gridSpacing = data?.spacing ?? 16
        let iconSz = data?.iconSize ?? 32
        let iconClr = data?.iconColor ?? "#6366F1"

        let gridColumns = Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columnCount)

        LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 8) {
                    if let icon = item.icon {
                        // Check if it's an emoji or SF Symbol
                        if icon.count <= 2 && icon.unicodeScalars.allSatisfy({ $0.value > 127 }) {
                            Text(icon)
                                .font(.system(size: iconSz))
                        } else {
                            Image(systemName: icon)
                                .font(.system(size: iconSz * 0.6))
                                .foregroundColor(Color(hex: iconClr))
                                .frame(width: iconSz, height: iconSz)
                        }
                    }

                    if let label = item.label ?? item.title {
                        let ts = style?.elements?["title"]?.textStyle
                        if let ts = ts {
                            Text(label).applyTextStyle(ts)
                        } else {
                            Text(label)
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                        }
                    }

                    if let desc = item.description ?? item.subtitle {
                        let ds = style?.elements?["description"]?.textStyle
                        if let ds = ds {
                            Text(desc).applyTextStyle(ds)
                        } else {
                            Text(desc)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - SPEC-089d: Comparison table section (AC-036)

    @ViewBuilder
    private func comparisonTableSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        let cols = data?.tableColumns ?? []
        let rows = data?.tableRows ?? []
        let checkClr = Color(hex: data?.checkColor ?? "#22C55E")
        let crossClr = Color(hex: data?.crossColor ?? "#EF4444")
        let highlightClr = Color(hex: data?.highlightColor ?? "#6366F1")
        let borderClr = Color(hex: data?.borderColor ?? "#333333")
        let radius = data?.cornerRadius ?? 12

        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                // Feature column header (empty)
                Text("")
                    .frame(maxWidth: .infinity)

                ForEach(Array(cols.enumerated()), id: \.offset) { colIdx, col in
                    Text(col.label)
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(col.highlighted == true ? highlightClr.opacity(0.15) : Color.clear)
                }
            }
            .background(Color.white.opacity(0.05))

            Divider().background(borderClr)

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    Text(row.feature)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)

                    ForEach(Array(row.values.enumerated()), id: \.offset) { valIdx, value in
                        Group {
                            switch value.lowercased() {
                            case "check":
                                Image(systemName: "checkmark")
                                    .foregroundColor(checkClr)
                                    .font(.caption.weight(.bold))
                            case "cross":
                                Image(systemName: "xmark")
                                    .foregroundColor(crossClr)
                                    .font(.caption.weight(.bold))
                            case "partial":
                                Image(systemName: "minus")
                                    .foregroundColor(.yellow)
                                    .font(.caption.weight(.bold))
                            default:
                                Text(value)
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            valIdx < cols.count && cols[valIdx].highlighted == true
                                ? highlightClr.opacity(0.08)
                                : Color.clear
                        )
                    }
                }

                if rowIdx < rows.count - 1 {
                    Divider().background(borderClr.opacity(0.3))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(borderClr, lineWidth: 1)
        )
    }

    // MARK: - SPEC-089d: Promo input section (AC-037)

    @ViewBuilder
    private func promoInputSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        HStack(spacing: 8) {
            TextField(data?.placeholder ?? "Promo code", text: $promoCode)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .foregroundColor(.white)
                .font(.subheadline)

            Button {
                // AC-037: Submit promo code via delegate callback
                promoState = .loading
                if let onPromoCodeSubmit = onPromoCodeSubmit {
                    onPromoCodeSubmit(promoCode) { isValid in
                        DispatchQueue.main.async {
                            promoState = isValid ? .success : .error
                        }
                    }
                } else {
                    // No delegate configured — basic non-empty check fallback
                    promoState = promoCode.isEmpty ? .error : .success
                }
            } label: {
                if case .loading = promoState {
                    ProgressView().tint(.white)
                } else {
                    Text(loc("promo.button", data?.buttonText ?? "Apply"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(hex: data?.accentColor ?? "#6366F1"))
            .cornerRadius(8)
            .disabled(promoState == .loading)
        }

        // Status messages
        switch promoState {
        case .success:
            Text(data?.successText ?? "Code applied!")
                .font(.caption)
                .foregroundColor(.green)
        case .error:
            Text(data?.errorText ?? "Invalid code")
                .font(.caption)
                .foregroundColor(.red)
        default:
            EmptyView()
        }
    }

    // MARK: - SPEC-089d: Toggle section (AC-038)

    @ViewBuilder
    private func toggleSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        let key = data?.label ?? "toggle"
        let isOn = Binding<Bool>(
            get: { toggleStates[key] ?? data?.defaultValue ?? false },
            set: { toggleStates[key] = $0 }
        )

        HStack(spacing: 12) {
            if let iconName = data?.icon {
                Image(systemName: iconName)
                    .foregroundColor(Color(hex: data?.accentColor ?? "#6366F1"))
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let label = data?.label {
                    Text(loc("toggle.label", label))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(Color(hex: data?.labelColorVal ?? "#FFFFFF"))
                }
                if let desc = data?.description {
                    Text(loc("toggle.description", desc))
                        .font(.caption)
                        .foregroundColor(Color(hex: data?.descriptionColor ?? "#999999"))
                }
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color(hex: data?.onColor ?? "#6366F1"))
        }
    }

    // MARK: - SPEC-089d: Reviews carousel section (AC-039)

    @ViewBuilder
    private func reviewsCarouselSectionView(data: PaywallSectionData?, style: SectionStyleConfig?) -> some View {
        if let reviews = data?.reviews, !reviews.isEmpty {
            ReviewsCarouselView(
                reviews: reviews,
                autoScroll: data?.autoScroll ?? true,
                autoScrollIntervalMs: data?.autoScrollIntervalMs ?? 4000,
                showRatingStars: data?.showRatingStars ?? true,
                starColor: data?.starColor ?? "#FBBF24",
                textStyle: style?.elements?["text"]?.textStyle,
                authorStyle: style?.elements?["author"]?.textStyle,
                cardStyle: style?.elements?["card"],
                loc: loc
            )
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
        // AC-038: Include toggle states in purchase metadata
        var metadata: [String: Any] = [:]
        if !toggleStates.isEmpty {
            metadata["toggle_states"] = toggleStates
        }
        if !promoCode.isEmpty && promoState == .success {
            metadata["promo_code"] = promoCode
        }
        onPlanSelected(plan, metadata)
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

// MARK: - SPEC-089d: Promo state enum

enum PromoState: Equatable {
    case idle
    case loading
    case success
    case error
}

// MARK: - SPEC-089d: Line shape for dashed/dotted dividers

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - SPEC-089d: Carousel sub-view (AC-033)

struct CarouselView: View {
    let pages: [PaywallCarouselPage]
    let config: PaywallConfig
    let autoScroll: Bool
    let autoScrollIntervalMs: Int
    let showIndicators: Bool
    let indicatorColor: String
    let indicatorActiveColor: String
    let height: CGFloat?
    let loc: (String, String) -> String

    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    VStack(spacing: 8) {
                        if let children = page.children {
                            ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                                // Render child sections (simplified: render text/title if present)
                                if let title = child.data?.title {
                                    Text(title)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                                if let subtitle = child.data?.subtitle {
                                    Text(subtitle)
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                if let imageUrl = child.data?.imageUrl, let url = URL(string: imageUrl) {
                                    AsyncImage(url: url) { image in
                                        image.resizable().scaledToFit()
                                    } placeholder: {
                                        ProgressView()
                                    }
                                    .frame(maxHeight: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                    .tag(index)
                    .padding(.horizontal, 4)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: showIndicators ? .always : .never))
            .frame(height: height ?? 200)

            // Custom indicators (when show_indicators is true but we want custom colors)
            if showIndicators {
                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { idx in
                        Circle()
                            .fill(idx == currentPage
                                  ? Color(hex: indicatorActiveColor)
                                  : Color(hex: indicatorColor))
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .onAppear {
            guard autoScroll else { return }
            Timer.scheduledTimer(withTimeInterval: Double(autoScrollIntervalMs) / 1000.0, repeats: true) { _ in
                withAnimation {
                    currentPage = (currentPage + 1) % max(pages.count, 1)
                }
            }
        }
    }
}

// MARK: - SPEC-089d: Reviews carousel sub-view (AC-039)

struct ReviewsCarouselView: View {
    let reviews: [PaywallReview]
    let autoScroll: Bool
    let autoScrollIntervalMs: Int
    let showRatingStars: Bool
    let starColor: String
    let textStyle: TextStyleConfig?
    let authorStyle: TextStyleConfig?
    let cardStyle: ElementStyleConfig?
    let loc: (String, String) -> String

    @State private var currentReview = 0

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $currentReview) {
                ForEach(Array(reviews.enumerated()), id: \.offset) { index, review in
                    VStack(spacing: 12) {
                        // Star rating
                        if showRatingStars, let rating = review.rating {
                            HStack(spacing: 2) {
                                ForEach(0..<5, id: \.self) { star in
                                    Image(systemName: Double(star) < rating ? "star.fill" : "star")
                                        .font(.caption)
                                        .foregroundColor(Color(hex: starColor))
                                }
                            }
                        }

                        // Quote text
                        if let ts = textStyle {
                            Text("\u{201C}\(review.text)\u{201D}")
                                .applyTextStyle(ts)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("\u{201C}\(review.text)\u{201D}")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .italic()
                        }

                        // Author
                        HStack(spacing: 8) {
                            if let avatarUrl = review.avatarUrl, let url = URL(string: avatarUrl) {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Circle().fill(Color.gray.opacity(0.3))
                                }
                                .frame(width: 28, height: 28)
                                .clipShape(Circle())
                            }

                            if let as_ = authorStyle {
                                Text(review.author).applyTextStyle(as_)
                            } else {
                                Text(review.author)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }

                            if let date = review.date {
                                Text(date)
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                    }
                    .padding(16)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 180)

            // Page dots
            HStack(spacing: 6) {
                ForEach(0..<reviews.count, id: \.self) { idx in
                    Circle()
                        .fill(idx == currentReview ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .onAppear {
            guard autoScroll else { return }
            Timer.scheduledTimer(withTimeInterval: Double(autoScrollIntervalMs) / 1000.0, repeats: true) { _ in
                withAnimation {
                    currentReview = (currentReview + 1) % max(reviews.count, 1)
                }
            }
        }
    }
}
