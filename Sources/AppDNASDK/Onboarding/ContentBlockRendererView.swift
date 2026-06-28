import SwiftUI
import MapKit
import PhotosUI
// MARK: - Content Block Renderer

struct ContentBlockRendererView: View {
    let blocks: [ContentBlock]
    let onAction: (_ action: String, _ actionValue: String?) -> Void
    @Binding var toggleValues: [String: Bool]
    var loc: ((String, String) -> String)? = nil
    /// Step responses collected so far (for visibility conditions & bindings).
    var responses: [String: Any] = [:]
    /// Hook data from `onBeforeStepRender` (for visibility conditions & bindings).
    var hookData: [String: Any]? = nil
    /// Input values for form input blocks. Key = field_id, Value = field value.
    @Binding var inputValues: [String: Any]
    /// Current step index in the onboarding flow (0-based). Used for auto-binding page_indicator and progress_bar.
    var currentStepIndex: Int = 0
    /// Total number of steps in the onboarding flow. Used for auto-binding progress_bar.
    var totalSteps: Int = 1
    /// When true, vertical_align is handled by the parent ThreeZoneStepLayout (zone partitioning),
    /// so BlockPositionModifier should not map vertical_align to frame alignment.
    var isZoneManaged: Bool = false
    /// Scroll offset from parent ScrollView — used for collapse_on_scroll blocks (Sprint 7).
    var scrollOffset: CGFloat = 0

    var body: some View {
        let visibleBlocks = blocks.filter { block in
            evaluateVisibilityCondition(
                block.visibility_condition,
                responses: responses,
                hookData: hookData
            )
        }
        // Entrance animation cap: max 10 animated blocks per step
        let animatedBlockIds: Set<String> = {
            var ids = Set<String>()
            for block in visibleBlocks {
                if ids.count >= 10 { break }
                if let anim = block.entrance_animation, anim.type != "none" {
                    ids.insert(block.id)
                }
            }
            return ids
        }()

        VStack(spacing: 12) {
            ForEach(visibleBlocks) { block in
                let shouldAnimate = animatedBlockIds.contains(block.id)
                let resolvedBlock = resolveBlockBindings(block, hookData: hookData, responses: responses)
                let shouldCollapse = resolvedBlock.collapse_on_scroll == true
                // Collapse threshold: how many points of scroll before this block hides
                let collapseThreshold = CGFloat(
                    (cfgDouble(resolvedBlock.field_config?["collapse_threshold"])) ?? 50
                )
                let collapseProgress = shouldCollapse ? min(max(scrollOffset / collapseThreshold, 0), 1) : 0

                // Input blocks: skip element_height at the wrapper level — it's
                // applied INSIDE each input view (to the field container directly).
                // Otherwise the field stays tiny inside a tall empty wrapper.
                let isInputBlock = resolvedBlock.type.rawValue.hasPrefix("input_")
                let effectiveHeight = isInputBlock ? nil : resolvedBlock.element_height
                let isExpandableBlock = resolvedBlock.type == .input_select

                renderBlock(resolvedBlock, animate: shouldAnimate)
                    .applyRelativeSizing(width: resolvedBlock.element_width, height: effectiveHeight, useMinHeight: isExpandableBlock)
                    .applyBlockContainerStyle(resolvedBlock)
                    // Sprint 7: Scroll-collapse — ONLY applied to blocks with collapse_on_scroll.
                    // .clipped() and .frame(maxHeight:) must NOT touch non-collapsible blocks
                    // because they clip dropdowns, overlays, and overflow content.
                    .if(shouldCollapse) { view in
                        view
                            .opacity(Double(1 - collapseProgress))
                            .frame(maxHeight: collapseProgress >= 1 ? 0 : .infinity)
                            .clipped()
                            .animation(.easeInOut(duration: 0.15), value: collapseProgress >= 1)
                    }
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: ContentBlock, animate: Bool = false) -> some View {
        let content = renderBlockContent(block)
            .applyBlockStyle(block.block_style)
            .applyBlockPosition(
                verticalAlign: block.vertical_align,
                horizontalAlign: block.horizontal_align,
                verticalOffset: block.vertical_offset,
                horizontalOffset: block.horizontal_offset,
                isZoneManaged: isZoneManaged
            )

        if animate, let anim = block.entrance_animation {
            EntranceAnimationWrapper(animation: anim) {
                AnyView(content)
            }
        } else {
            content
        }
    }

    /// AC-064/065/066: Resolves dynamic bindings and template strings on a block.
    /// Returns a new block with resolved text fields and binding overrides.
    private func resolveBlockBindings(_ block: ContentBlock, hookData: [String: Any]?, responses: [String: Any]) -> ContentBlock {
        guard block.bindings != nil || containsTemplates(block) else { return block }

        // Since ContentBlock is a struct with let properties, we use JSON round-trip to create a mutable copy.
        // This is the simplest approach without refactoring the entire model to use var properties.
        guard let data = try? JSONEncoder().encode(block),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return block
        }

        // AC-066: Resolve bindings map — override block properties from data context
        if let bindings = block.bindings {
            for (property, path) in bindings {
                if let resolved = resolveDotPath(path, responses: responses, hookData: hookData, userTraits: nil, sessionData: nil) {
                    json[property] = resolved
                }
            }
        }

        // AC-064: Resolve template strings in text fields
        if let text = json["text"] as? String, text.contains("{{") {
            json["text"] = resolveTemplateString(text, hookData: hookData, responses: responses)
        }
        if let label = json["field_label"] as? String, label.contains("{{") {
            json["field_label"] = resolveTemplateString(label, hookData: hookData, responses: responses)
        }
        if let placeholder = json["field_placeholder"] as? String, placeholder.contains("{{") {
            json["field_placeholder"] = resolveTemplateString(placeholder, hookData: hookData, responses: responses)
        }
        if let badgeText = json["badge_text"] as? String, badgeText.contains("{{") {
            json["badge_text"] = resolveTemplateString(badgeText, hookData: hookData, responses: responses)
        }
        if let toggleLabel = json["toggle_label"] as? String, toggleLabel.contains("{{") {
            json["toggle_label"] = resolveTemplateString(toggleLabel, hookData: hookData, responses: responses)
        }

        // Decode back to ContentBlock
        if let updatedData = try? JSONSerialization.data(withJSONObject: json),
           let resolved = try? JSONDecoder().decode(ContentBlock.self, from: updatedData) {
            return resolved
        }
        return block
    }

    /// Check if a block contains `{{...}}` template patterns in its text fields.
    private func containsTemplates(_ block: ContentBlock) -> Bool {
        if let text = block.text, text.contains("{{") { return true }
        if let label = block.field_label, label.contains("{{") { return true }
        if let placeholder = block.field_placeholder, placeholder.contains("{{") { return true }
        if let badgeText = block.badge_text, badgeText.contains("{{") { return true }
        if let toggleLabel = block.toggle_label, toggleLabel.contains("{{") { return true }
        return false
    }

    /// Uses AnyView type erasure to avoid exponential Swift type-checking
    /// on the 45-case switch statement (was causing 30+ min compile times).
    private func renderBlockContent(_ block: ContentBlock) -> AnyView {
        switch block.type {
        case .heading: return AnyView(headingBlock(block))
        case .text: return AnyView(textBlock(block))
        case .image: return AnyView(imageBlock(block))
        case .media_gallery: return AnyView(mediaGalleryBlock(block))
        case .section_background: return AnyView(sectionBackgroundBlock(block))
        case .carousel: return AnyView(CarouselBlockView(block: block, onAction: onAction, toggleValues: $toggleValues, inputValues: $inputValues))
        case .otp_input: return AnyView(otpInputBlock(block))
        case .warning_banner: return AnyView(warningBannerBlock(block))
        case .password_strength: return AnyView(passwordStrengthBlock(block))
        case .speech_bubble: return AnyView(speechBubbleBlock(block))
        case .feedback_panel: return AnyView(feedbackPanelBlock(block))
        case .summary_screen: return AnyView(summaryScreenBlock(block))
        case .press_hold_confirm: return AnyView(pressHoldConfirmBlock(block))
        case .health_connect: return AnyView(healthConnectBlock(block))
        case .button: return AnyView(buttonBlock(block))
        case .spacer: return AnyView(Spacer().frame(height: CGFloat(block.spacer_height ?? 16)))
        case .list: return AnyView(listBlock(block))
        case .divider: return AnyView(dividerBlock(block))
        case .badge: return AnyView(badgeBlock(block))
        case .icon: return AnyView(iconBlock(block))
        case .toggle: return AnyView(toggleBlock(block))
        case .video: return AnyView(videoBlock(block))
        case .lottie: return AnyView(lottieBlock(block))
        case .rive: return AnyView(riveBlock(block))
        case .page_indicator: return AnyView(pageIndicatorBlock(block))
        case .wheel_picker: return AnyView(WheelPickerBlockView(block: block, inputValues: $inputValues))
        case .pulsing_avatar: return AnyView(PulsingAvatarBlockView(block: block))
        case .social_login: return AnyView(socialLoginBlock(block))
        case .timeline: return AnyView(timelineBlock(block))
        case .animated_loading: return AnyView(AnimatedLoadingBlockView(block: block, onAction: onAction))
        case .star_background: return AnyView(StarBackgroundBlockView(block: block))
        case .countdown_timer: return AnyView(CountdownTimerBlockView(block: block, onAction: onAction))
        case .rating: return AnyView(RatingBlockView(block: block, onAction: onAction))
        case .rich_text: return AnyView(richTextBlock(block))
        case .progress_bar: return AnyView(progressBarBlock(block))
        case .stack: return AnyView(stackBlock(block))
        case .custom_view: return AnyView(customViewBlock(block))
        case .date_wheel_picker: return AnyView(DateWheelPickerBlockView(block: block, inputValues: $inputValues))
        case .circular_gauge: return AnyView(CircularGaugeBlockView(block: block))
        case .row: return AnyView(rowBlock(block))
        case .pricing_card: return AnyView(PricingCardBlockView(block: block, onAction: onAction))
        case .input_text: return AnyView(FormInputTextBlock(block: block, inputValues: $inputValues, keyboardType: .default))
        case .input_textarea: return AnyView(FormInputTextAreaBlock(block: block, inputValues: $inputValues))
        case .input_number: return AnyView(FormInputTextBlock(block: block, inputValues: $inputValues, keyboardType: .numberPad))
        case .input_email: return AnyView(FormInputTextBlock(block: block, inputValues: $inputValues, keyboardType: .emailAddress))
        case .input_phone: return AnyView(FormInputTextBlock(block: block, inputValues: $inputValues, keyboardType: .phonePad))
        case .input_url: return AnyView(FormInputTextBlock(block: block, inputValues: $inputValues, keyboardType: .URL))
        case .input_password: return AnyView(FormInputPasswordBlock(block: block, inputValues: $inputValues))
        case .input_date: return AnyView(FormInputDateBlock(block: block, inputValues: $inputValues, components: .date))
        case .input_time: return AnyView(FormInputDateBlock(block: block, inputValues: $inputValues, components: .hourAndMinute))
        case .input_datetime: return AnyView(FormInputDateBlock(block: block, inputValues: $inputValues, components: [.date, .hourAndMinute]))
        case .input_select: return AnyView(FormInputSelectBlock(block: block, inputValues: $inputValues))
        case .input_slider: return AnyView(FormInputSliderBlock(block: block, inputValues: $inputValues))
        case .input_toggle: return AnyView(FormInputToggleBlock(block: block, inputValues: $inputValues))
        case .input_stepper: return AnyView(FormInputStepperBlock(block: block, inputValues: $inputValues))
        case .input_segmented: return AnyView(FormInputSegmentedBlock(block: block, inputValues: $inputValues))
        case .input_rating: return AnyView(FormInputRatingBlock(block: block, inputValues: $inputValues))
        case .input_range_slider: return AnyView(FormInputRangeSliderBlock(block: block, inputValues: $inputValues))
        case .input_chips: return AnyView(FormInputChipsBlock(block: block, inputValues: $inputValues))
        case .input_location: return AnyView(FormInputLocationPlaceholderBlock(block: block, inputValues: $inputValues))
        case .input_image_picker: return AnyView(FormInputImagePickerPlaceholderBlock(block: block, inputValues: $inputValues))
        case .input_color: return AnyView(FormInputColorBlock(block: block, inputValues: $inputValues))
        case .input_signature: return AnyView(FormInputSignatureBlock(block: block, inputValues: $inputValues))
        case .unknown: return AnyView(EmptyView())
        }
    }

    // MARK: - Stub Placeholder (SPEC-089d)

    /// Placeholder view for new block types whose full renderers are not yet implemented.
    /// Renders a subtle label in DEBUG builds; EmptyView in release builds.
    @ViewBuilder
    private func stubBlockPlaceholder(_ typeName: String) -> some View {
        #if DEBUG
        Text("[\(typeName)]")
            .font(.caption2)
            .foregroundColor(.secondary.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
        #else
        EmptyView()
        #endif
    }

    // MARK: - Heading

    private func headingBlock(_ block: ContentBlock) -> some View {
        let fallbackSize: CGFloat = {
            switch block.level ?? 1 {
            case 1: return 28
            case 2: return 22
            case 3: return 18
            default: return 28
            }
        }()

        let text = block.text ?? ""
        let textAlignment: TextAlignment = {
            switch block.horizontal_align {
            case "center": return .center
            case "right": return .trailing
            default: return .leading
            }
        }()
        let frameAlignment: Alignment = {
            switch block.horizontal_align {
            case "center": return .center
            case "right": return .trailing
            default: return .leading
            }
        }()
        // IMPORTANT: apply the resolved font DIRECTLY on `Text(...)` so SwiftUI
        // treats it as the Text-specific .font() overload (which wins over any
        // ambient .font() env modifier from parent containers and over the
        // env .font() applied later by `.applyTextStyle`). Previously we
        // chained `.font(.system(...)).applyTextStyle(block.style)` — but
        // applyTextStyle is `extension View` so its inner `.font(font)` uses
        // the View env-modifier overload, which does NOT override the direct
        // `.font()` already baked into the Text. Result: author-set font_size
        // and font_weight were silently ignored in nested rows (q4.png).
        let styleFont = FontResolver.font(
            family: block.style?.font_family,
            size: block.style?.font_size ?? Double(fallbackSize),
            weight: block.style?.font_weight ?? 700
        )
        let styleColor: Color = (block.style?.color).map { Color(hex: $0) } ?? .primary
        return Text(loc?("block.\(block.id).text", text) ?? text)
            .font(styleFont)
            .foregroundColor(styleColor)
            .applyTextStyleDecorations(block.style)
            .multilineTextAlignment(textAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    // MARK: - Text

    private func textBlock(_ block: ContentBlock) -> some View {
        let text = block.text ?? ""
        let textAlignment: TextAlignment = {
            switch block.horizontal_align {
            case "center": return .center
            case "right": return .trailing
            default: return .leading
            }
        }()
        let frameAlignment: Alignment = {
            switch block.horizontal_align {
            case "center": return .center
            case "right": return .trailing
            default: return .leading
            }
        }()
        // See headingBlock for the SwiftUI font-precedence rationale — we
        // resolve the font here and apply it directly on Text(...).
        let styleFont = FontResolver.font(
            family: block.style?.font_family,
            size: block.style?.font_size ?? 16,
            weight: block.style?.font_weight ?? 400
        )
        let styleColor: Color = (block.style?.color).map { Color(hex: $0) } ?? .primary
        return Text(loc?("block.\(block.id).text", text) ?? text)
            .font(styleFont)
            .foregroundColor(styleColor)
            .applyTextStyleDecorations(block.style)
            .multilineTextAlignment(textAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    // MARK: - Image

    // EPIC-4b — section_background: vertical proportional color zones painted behind overlaid content.
    // Zones + arrangement come through field_config (parity with Android, which is at the JVM arg limit).
    @ViewBuilder
    private func sectionBackgroundBlock(_ block: ContentBlock) -> some View {
        let zonesRaw = (block.field_config?["background_zones"]?.value as? [Any]) ?? []
        let zones: [(CGFloat, Color)] = zonesRaw.compactMap { item in
            guard let m = item as? [String: Any] else { return nil }
            let w = (m["weight"] as? Double) ?? Double((m["weight"] as? Int) ?? 1)
            return (CGFloat(w), Color(hex: (m["color"] as? String) ?? "#000000"))
        }
        let totalW = max(zones.reduce(0) { $0 + $1.0 }, 0.0001)
        let children = block.children ?? block.stack_children ?? []
        let arrangement = (block.field_config?["content_arrangement"]?.value as? String) ?? "space_between"
        let height = CGFloat(block.height ?? 480)
        ZStack {
            // Background: vertical weighted color zones.
            GeometryReader { geo in
                VStack(spacing: 0) {
                    ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                        zone.1.frame(maxWidth: .infinity).frame(height: geo.size.height * zone.0 / totalW)
                    }
                }
            }
            // Foreground: content overlaid on the zones.
            VStack(spacing: 12) {
                if arrangement == "center" || arrangement == "bottom" { Spacer() }
                ForEach(Array(children.enumerated()), id: \.offset) { idx, child in
                    if arrangement == "space_between" && idx > 0 { Spacer() }
                    renderBlock(child)
                }
                if arrangement == "center" || arrangement == "top" { Spacer() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    // EPIC-3 — media_gallery: horizontal scrollable row of image tiles (rounded, fixed size, placeholder bg).
    @ViewBuilder
    private func mediaGalleryBlock(_ block: ContentBlock) -> some View {
        let images = block.gallery_images ?? []
        let itemW = CGFloat(block.gallery_item_width ?? 140)
        let itemH = CGFloat(block.gallery_item_height ?? 180)
        let cr = CGFloat(block.gallery_corner_radius ?? 12)
        let spacing = CGFloat(block.gallery_spacing ?? 10)
        let galleryAlignment: Alignment = block.gallery_align == "start" ? .leading : (block.gallery_align == "end" ? .trailing : .center)
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, urlString in
                        ZStack {
                            Color(hex: "#2A2A2E")
                            if let url = URL(string: urlString) {
                                BundledAsyncPhaseImage(url: url) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    }
                                }
                            }
                        }
                        .frame(width: itemW, height: itemH)
                        .clipShape(RoundedRectangle(cornerRadius: cr))
                    }
                }
                .padding(.horizontal, 2)
                // EPIC-3 — settable align (start/center/end) when tiles fit; scrolls when they overflow.
                .frame(minWidth: geo.size.width, alignment: galleryAlignment)
            }
        }
        .frame(height: itemH)
    }

    private func imageBlock(_ block: ContentBlock) -> some View {
        let cr = CGFloat(block.corner_radius ?? 0)
        let isCircle = (block.corner_radius ?? 0) >= 9999
        let fitMode: ContentMode = (block.image_fit == "contain" || block.image_fit == "fit") ? .fit : .fill
        let imgHeight = CGFloat(block.height ?? 200)

        return Group {
            if block.image_frame == "phone", let urlString = block.image_url, let url = URL(string: urlString) {
                phoneMockup(url: url, height: imgHeight, alt: block.alt)
            } else if let urlString = block.image_url, let url = URL(string: urlString) {
                BundledAsyncPhaseImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        if isCircle {
                            image.resizable()
                                .aspectRatio(contentMode: fitMode)
                                .frame(maxHeight: imgHeight)
                                .clipShape(Circle())
                                .accessibilityLabel(block.alt ?? "Image")
                        } else {
                            image.resizable()
                                .aspectRatio(contentMode: fitMode)
                                .frame(maxHeight: imgHeight)
                                .clipShape(RoundedRectangle(cornerRadius: cr))
                                .accessibilityLabel(block.alt ?? "Image")
                        }
                    case .failure:
                        imagePlaceholder
                    default:
                        ProgressView().frame(height: CGFloat(block.height ?? 200))
                    }
                }
            } else {
                // No image URL — render nothing (don't show broken placeholder)
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// EPIC-3 — phone mockup: device bezel + dynamic-island notch, image as the "screen".
    private func phoneMockup(url: URL, height: CGFloat, alt: String?) -> some View {
        ZStack(alignment: .top) {
            BundledAsyncPhaseImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color(hex: "#2A2A2E")
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 30))
            Capsule()
                .fill(Color.black)
                .frame(width: 96, height: 26)
                .padding(.top, 8)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 40).fill(Color(hex: "#101012")))
        .frame(maxWidth: 260)
        .accessibilityLabel(alt ?? "Image")
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.gray.opacity(0.2))
            .frame(height: 120)
            .overlay(Image(systemName: "photo").foregroundColor(.gray))
    }

    // MARK: - Button (with outline variant — SPEC-089d §3.18)

    private func buttonBlock(_ block: ContentBlock) -> some View {
        let btnVariant = block.variant ?? "primary"
        let radius = CGFloat(block.button_corner_radius ?? 12)
        let bgColor = Color(hex: block.bg_color ?? (AppDNA.brandAccentHex ?? "#6366F1"))
        let txtColor = Color(hex: block.text_color ?? "#FFFFFF")
        let labelText = loc?("block.\(block.id).text", block.text ?? "Continue") ?? block.text ?? "Continue"
        let fgColor = btnVariant == "outline" ? bgColor : (btnVariant == "text" ? bgColor : txtColor)

        return Button {
            onAction(block.action ?? "next", block.action_value)
        } label: {
            HStack(spacing: 8) {
                // Gap 6: icon_emoji
                if let emoji = block.icon_emoji, !emoji.isEmpty {
                    Text(emoji)
                }
                // Gap 6: image_url icon
                if let imageUrl = block.image_url, let url = URL(string: imageUrl) {
                    BundledAsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20)
                    } placeholder: {
                        EmptyView()
                    }
                }
                Text(labelText)
                    .font(.body.weight(.semibold))
                    .applyTextStyle(block.style)
            }
            .foregroundColor(fgColor)
            // EPIC-6 — apply authored button_height (resize the button) instead of only intrinsic padding.
            .padding(.vertical, block.button_height == nil ? 14 : 0)
            .frame(maxWidth: .infinity)
            .frame(height: block.button_height.map { CGFloat($0) })
            .background(buttonBackground(block: block, btnVariant: btnVariant, bgColor: bgColor))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                btnVariant == "outline"
                    ? RoundedRectangle(cornerRadius: radius).stroke(bgColor, lineWidth: 1.5)
                    : nil
            )
        }
        .applyPressedStyle(block.pressed_style)
    }

    /// Gap 5: Button background — gradient or solid color.
    @ViewBuilder
    private func buttonBackground(block: ContentBlock, btnVariant: String, bgColor: Color) -> some View {
        if btnVariant == "outline" || btnVariant == "text" {
            Color.clear
        } else if let grad = block.block_style?.background_gradient {
            LinearGradient(
                colors: [Color(hex: grad.start ?? "#000000"), Color(hex: grad.end ?? "#FFFFFF")],
                startPoint: gradientStartPointForButton(angle: grad.angle ?? 0),
                endPoint: gradientEndPointForButton(angle: grad.angle ?? 0)
            )
        } else {
            bgColor
        }
    }

    private func gradientStartPointForButton(angle: Double) -> UnitPoint {
        let rads = angle * .pi / 180
        return UnitPoint(x: 0.5 - sin(rads) / 2, y: 0.5 + cos(rads) / 2)
    }

    private func gradientEndPointForButton(angle: Double) -> UnitPoint {
        let rads = angle * .pi / 180
        return UnitPoint(x: 0.5 + sin(rads) / 2, y: 0.5 - cos(rads) / 2)
    }

    // EPIC-11 — OTP / code-input: a row of N single-character boxes (verification codes). Value from
    // inputValues[field_id] or field_config.otp_value (snapshot/preview seed). Parity with Android.
    private func otpInputBlock(_ block: ContentBlock) -> some View {
        let rawLen = (block.field_config?["otp_length"]?.value as? Int)
            ?? cfgDouble(block.field_config?["otp_length"]).map { Int($0) } ?? 6
        let length = min(max(rawLen, 2), 10)
        let fieldId = block.field_id ?? block.id
        let value = (inputValues[fieldId] as? String)
            ?? (block.field_config?["otp_value"]?.value as? String) ?? ""
        let accent = Color(hex: block.active_color ?? (AppDNA.brandAccentHex ?? "#6366F1"))
        let boxBg = Color(hex: block.bg_color ?? "#1F2937")
        let chars = Array(value)
        return HStack(spacing: 8) {
            ForEach(0..<length, id: \.self) { i in
                let ch: Character? = i < chars.count ? chars[i] : nil
                let isActive = i == chars.count
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(boxBg)
                    if let ch = ch {
                        Text(String(ch)).font(.system(size: 22, weight: .semibold)).foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isActive ? accent : (ch != nil ? accent.opacity(0.5) : Color.gray.opacity(0.35)),
                                lineWidth: (isActive || ch != nil) ? 2 : 1)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // EPIC-11 — warning/info banner: tinted rounded card + leading icon + message. Parity with Android.
    private func warningBannerBlock(_ block: ContentBlock) -> some View {
        let variant = (block.field_config?["banner_variant"]?.value as? String) ?? "warning"
        let accentHex: String
        let defaultIcon: String
        switch variant {
        case "error": accentHex = "#EF4444"; defaultIcon = "⛔"
        case "info": accentHex = "#3B82F6"; defaultIcon = "ℹ️"
        case "success": accentHex = "#10B981"; defaultIcon = "✓"
        default: accentHex = "#F59E0B"; defaultIcon = "⚠️"
        }
        let accent = Color(hex: block.active_color ?? accentHex)
        let icon = (block.field_config?["banner_icon"]?.value as? String) ?? defaultIcon
        let text = loc?("block.\(block.id).text", block.text ?? "") ?? block.text ?? ""
        return HStack(spacing: 10) {
            Text(icon).font(.system(size: 18))
            Text(text).font(.system(size: 14, weight: .medium)).foregroundColor(.white)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.45), lineWidth: 1))
    }

    // EPIC-11 — password-strength meter: 4 segment bars + label, red→amber→yellow→green ramp. Parity w/ Android.
    private func passwordStrengthBlock(_ block: ContentBlock) -> some View {
        let rawLevel = (block.field_config?["strength_level"]?.value as? Int)
            ?? cfgDouble(block.field_config?["strength_level"]).map { Int($0) } ?? 0
        let level = min(max(rawLevel, 0), 4)
        let colorHex: String
        let defLabel: String
        switch level {
        case 1: colorHex = "#EF4444"; defLabel = "Weak"
        case 2: colorHex = "#F59E0B"; defLabel = "Fair"
        case 3: colorHex = "#EAB308"; defLabel = "Good"
        case 4: colorHex = "#10B981"; defLabel = "Strong"
        default: colorHex = "#6B7280"; defLabel = ""
        }
        let accent = Color(hex: block.active_color ?? colorHex)
        let label = (block.field_config?["strength_label"]?.value as? String) ?? defLabel
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i < level ? accent : Color(hex: "#374151"))
                        .frame(height: 6)
                }
            }
            if !label.isEmpty {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // EPIC-11 — speech bubble (mascot dialogue): rounded card + downward tail triangle. Parity with Android.
    private func speechBubbleBlock(_ block: ContentBlock) -> some View {
        let bubbleColor = Color(hex: block.bg_color ?? "#FFFFFF")
        let textColor = Color(hex: block.text_color ?? "#111827")
        let tailPos = (block.field_config?["bubble_tail"]?.value as? String) ?? "left"
        let text = loc?("block.\(block.id).text", block.text ?? "") ?? block.text ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(bubbleColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            HStack(spacing: 0) {
                if tailPos == "left" { Spacer().frame(width: 24) }
                if tailPos == "center" || tailPos == "right" { Spacer() }
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: 18, y: 0))
                    p.addLine(to: CGPoint(x: 9, y: 9))
                    p.closeSubpath()
                }
                .fill(bubbleColor)
                .frame(width: 18, height: 9)
                if tailPos == "right" { Spacer().frame(width: 24) }
                if tailPos == "center" || tailPos == "left" { Spacer() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // EPIC-11 — quiz feedback panel (Duolingo correct/wrong): tinted panel + circled icon + headline + detail.
    private func feedbackPanelBlock(_ block: ContentBlock) -> some View {
        let state = (block.field_config?["feedback_state"]?.value as? String) ?? "correct"
        let accentHex: String
        let icon: String
        let defHead: String
        switch state {
        case "wrong": accentHex = "#EF4444"; icon = "✗"; defHead = "Not quite"
        case "info": accentHex = "#3B82F6"; icon = "ℹ"; defHead = "Heads up"
        default: accentHex = "#10B981"; icon = "✓"; defHead = "Great job!"
        }
        let accent = Color(hex: block.active_color ?? accentHex)
        let headline = loc?("block.\(block.id).text", block.text ?? defHead) ?? block.text ?? defHead
        let detail = block.field_config?["feedback_detail"]?.value as? String
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(accent).frame(width: 40, height: 40)
                Text(icon).font(.system(size: 20, weight: .bold)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.system(size: 17, weight: .bold)).foregroundColor(accent)
                if let detail = detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 14)).foregroundColor(.white.opacity(0.85))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // EPIC-11 — session summary screen (Duolingo end-of-lesson): optional headline + 2-column stat-card grid.
    private func summaryScreenBlock(_ block: ContentBlock) -> some View {
        let statsRaw = (block.field_config?["summary_stats"]?.value as? [Any]) ?? []
        let stats: [[String: Any]] = statsRaw.compactMap { $0 as? [String: Any] }
        let headline = loc?("block.\(block.id).text", block.text ?? "") ?? block.text ?? ""
        let defaultAccent = AppDNA.brandAccentHex ?? "#6366F1"
        let rows: [[[String: Any]]] = stride(from: 0, to: stats.count, by: 2).map {
            Array(stats[$0..<min($0 + 2, stats.count)])
        }
        return VStack(spacing: 12) {
            if !headline.isEmpty {
                Text(headline).font(.system(size: 22, weight: .bold)).foregroundColor(.white).frame(maxWidth: .infinity)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowStats in
                HStack(spacing: 12) {
                    ForEach(Array(rowStats.enumerated()), id: \.offset) { _, m in
                        let value = (m["value"] as? String) ?? ""
                        let label = (m["label"] as? String) ?? ""
                        let color = Color(hex: (m["color"] as? String) ?? defaultAccent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(value).font(.system(size: 24, weight: .bold)).foregroundColor(color)
                            Text(label).font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(hex: "#1F2937"))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    if rowStats.count == 1 { Spacer().frame(maxWidth: .infinity) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // EPIC-11 — press-and-hold-to-confirm: a pill that fills left→right as the user holds. Parity with Android.
    private func pressHoldConfirmBlock(_ block: ContentBlock) -> some View {
        let progress = min(max(cfgDouble(block.field_config?["hold_progress"]) ?? 0, 0), 1)
        let accent = Color(hex: block.active_color ?? (AppDNA.brandAccentHex ?? "#6366F1"))
        let text = loc?("block.\(block.id).text", block.text ?? "Hold to confirm") ?? block.text ?? "Hold to confirm"
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: "#1F2937"))
                Rectangle().fill(accent).frame(width: geo.size.width * CGFloat(progress))
                Text(text)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity)
    }

    // EPIC-11 — Health/HealthKit connect: a tappable card (icon + title + subtitle + chevron/✓). Native connect
    // flow is host-driven via onAction("health_connect"). Parity with Android.
    private func healthConnectBlock(_ block: ContentBlock) -> some View {
        // EPIC-11 — provider is PLATFORM-FIXED: iOS always shows Apple Health (Google Fit is Android-only).
        let connected = (block.field_config?["connected"]?.value as? Bool) ?? false
        let icon = "❤️"
        let defLabel = "Connect Apple Health"
        let iconBgHex = "#FF2D55"
        let label = loc?("block.\(block.id).text", block.text ?? defLabel) ?? block.text ?? defLabel
        let subtitle = (block.field_config?["health_subtitle"]?.value as? String) ?? "Sync steps, workouts & vitals"
        return Button {
            onAction("health_connect", nil)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color(hex: iconBgHex).opacity(0.18)).frame(width: 44, height: 44)
                    Text(icon).font(.system(size: 22))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    Text(subtitle).font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                if connected {
                    Text("✓").font(.system(size: 20, weight: .bold)).foregroundColor(Color(hex: "#10B981"))
                } else {
                    Text("›").font(.system(size: 26)).foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "#1F2937"))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private func listBlock(_ block: ContentBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array((block.items ?? []).enumerated()), id: \.offset) { index, item in
                HStack(spacing: 10) {
                    listMarker(style: block.list_style ?? "bullet", index: index)
                    // SPEC-084 Gap #9: localize each list item using block id + index key
                    Text(loc?("block.\(block.id).item.\(index)", item) ?? item)
                        .applyTextStyle(block.style)
                }
            }
        }
    }

    private func listMarker(style: String, index: Int) -> AnyView {
        switch style {
        case "numbered":
            return AnyView(Text("\(index + 1).")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary))
        case "check":
            return AnyView(Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundColor(Color(hex: (AppDNA.brandAccentHex ?? "#6366F1"))))
        default:
            return AnyView(Circle()
                .fill(Color.primary.opacity(0.5))
                .frame(width: 6, height: 6))
        }
    }

    // MARK: - Divider

    private func dividerBlock(_ block: ContentBlock) -> some View {
        Rectangle()
            .fill(Color(hex: block.divider_color ?? "#E5E7EB"))
            .frame(height: CGFloat(block.divider_thickness ?? 1))
            .padding(.vertical, CGFloat(block.divider_margin_y ?? 8))
    }

    // MARK: - Badge

    private func badgeBlock(_ block: ContentBlock) -> some View {
        Text(loc?("block.\(block.id).badge", block.badge_text ?? "") ?? block.badge_text ?? "")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color(hex: block.badge_bg_color ?? (AppDNA.brandAccentHex ?? "#6366F1")))
            .foregroundColor(Color(hex: block.badge_text_color ?? "#FFFFFF"))
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(block.badge_corner_radius ?? 999)))
    }

    // MARK: - Icon

    private func iconBlock(_ block: ContentBlock) -> some View {
        let alignment: Alignment = {
            switch block.icon_alignment {
            case "left": return .leading
            case "right": return .trailing
            default: return .center
            }
        }()

        return Group {
            // SPEC-085: Support IconReference (structured icon) or plain emoji string
            if let iconRef = block.icon_ref {
                IconView(ref: iconRef, size: CGFloat(block.icon_size ?? 32))
            } else {
                Text(block.icon_emoji ?? "")
                    .font(.system(size: CGFloat(block.icon_size ?? 32)))
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    // MARK: - Toggle

    private func toggleBlock(_ block: ContentBlock) -> some View {
        let binding = Binding<Bool>(
            get: { toggleValues[block.id] ?? (block.toggle_default ?? false) },
            set: { toggleValues[block.id] = $0 }
        )

        return VStack(alignment: .leading, spacing: 4) {
            Toggle(loc?("block.\(block.id).label", block.toggle_label ?? "") ?? block.toggle_label ?? "", isOn: binding)
                .tint(Color(hex: (AppDNA.brandAccentHex ?? "#6366F1")))
            if let desc = block.toggle_description {
                Text(loc?("block.\(block.id).description", desc) ?? desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Video (SPEC-085: Full VideoBlockView with playback)

    private func videoBlock(_ block: ContentBlock) -> some View {
        let effectiveHeight = CGFloat(block.video_height ?? block.height ?? 200)
        let effectiveCornerRadius = CGFloat(block.video_corner_radius ?? block.corner_radius ?? 8)

        return Group {
            // SPEC-085: Use VideoBlockView for full playback when video_url is present
            if let videoUrl = block.video_url {
                let videoBlock = VideoBlock(
                    video_url: videoUrl,
                    video_thumbnail_url: block.video_thumbnail_url ?? block.image_url,
                    video_height: Double(effectiveHeight),
                    video_corner_radius: Double(effectiveCornerRadius),
                    autoplay: block.autoplay,
                    loop: block.loop,
                    muted: block.muted,
                    controls: block.controls,
                    inline_playback: true
                )
                VideoBlockView(block: videoBlock)
            } else if let thumbUrl = block.video_thumbnail_url ?? block.image_url,
                      let url = URL(string: thumbUrl) {
                // Fallback: thumbnail-only display when no video_url
                BundledAsyncPhaseImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        ZStack {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxHeight: effectiveHeight)
                                .clipShape(RoundedRectangle(cornerRadius: effectiveCornerRadius))
                                .accessibilityLabel(block.alt ?? "Video")
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.9))
                                .shadow(radius: 4)
                        }
                    default:
                        ProgressView().frame(height: effectiveHeight)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: effectiveCornerRadius)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: effectiveHeight)
                    .overlay(Image(systemName: "play.circle").font(.largeTitle).foregroundColor(.gray))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Lottie (SPEC-085)

    private func lottieBlock(_ block: ContentBlock) -> some View {
        Group {
            if let lottieUrl = block.lottie_url {
                let lottieData = LottieBlock(
                    lottie_url: lottieUrl,
                    lottie_json: nil,
                    autoplay: block.autoplay ?? true,
                    loop: block.loop ?? true,
                    speed: block.lottie_speed ?? 1.0,
                    width: block.lottie_width,
                    height: block.lottie_height ?? block.height ?? 160,
                    alignment: block.icon_alignment ?? "center",
                    play_on_scroll: block.play_on_scroll,
                    play_on_tap: block.play_on_tap,
                    color_overrides: nil
                )
                LottieBlockView(block: lottieData)
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Rive (SPEC-085)

    private func riveBlock(_ block: ContentBlock) -> some View {
        Group {
            if let riveUrl = block.rive_url {
                let riveData = RiveBlock(
                    rive_url: riveUrl,
                    artboard: block.artboard,
                    state_machine: block.state_machine,
                    autoplay: block.autoplay ?? true,
                    height: block.height ?? 160,
                    alignment: block.icon_alignment ?? "center",
                    inputs: nil,
                    trigger_on_step_complete: block.trigger_on_step_complete
                )
                RiveBlockView(block: riveData)
            } else {
                EmptyView()
            }
        }
    }

    // MARK: - Page Indicator (SPEC-089d AC-012)

    private func pageIndicatorBlock(_ block: ContentBlock) -> some View {
        let dotCount = block.dot_count ?? totalSteps
        // AC-012: Auto-bind active_index to current step index when not explicitly set
        let activeIdx = block.active_index ?? currentStepIndex
        let dotSize = CGFloat(block.dot_size ?? 8)
        let dotSpacing = CGFloat(block.dot_spacing ?? 8)
        let activeW = block.active_dot_width.map { CGFloat($0) }
        let activeColor = Color(hex: block.active_color ?? (AppDNA.brandAccentHex ?? "#6366F1"))
        let inactiveColor = Color(hex: block.inactive_color ?? "#D1D5DB")

        let align: Alignment = {
            switch block.alignment {
            case "left": return .leading
            case "right": return .trailing
            default: return .center
            }
        }()

        return HStack(spacing: dotSpacing) {
            ForEach(0..<dotCount, id: \.self) { index in
                if index == activeIdx {
                    Capsule()
                        .fill(activeColor)
                        .frame(width: activeW ?? dotSize, height: dotSize)
                } else {
                    Circle()
                        .fill(inactiveColor)
                        .frame(width: dotSize, height: dotSize)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: align)
        .accessibilityLabel("Page \(activeIdx + 1) of \(dotCount)")
    }

    // MARK: - Social Login (SPEC-089d AC-015)

    private func socialLoginBlock(_ block: ContentBlock) -> some View {
        let providerList = (block.providers ?? []).filter { $0.enabled != false }
        let btnStyle = block.button_style ?? "filled"
        let btnHeight = CGFloat(block.button_height ?? 50)
        let btnSpacing = CGFloat(block.spacing ?? 12)
        let btnRadius = CGFloat(block.button_corner_radius ?? 12)

        // SPEC-089e amendment — when email_login_placement == "below_inputs"
        // the email provider renders first, then a spacer, then the other
        // providers. This is the expected layout when the social_login block
        // sits directly under email+password input blocks.
        let placement = block.email_login_placement ?? "with_providers"
        let emailSpacer = CGFloat(block.email_cta_spacing_below ?? 16)
        let (topGroup, bottomGroup): ([SocialProviderConfig], [SocialProviderConfig]) = {
            if placement == "below_inputs", let emailIdx = providerList.firstIndex(where: { ($0.type ?? "") == "email" }) {
                var rest = providerList
                let email = rest.remove(at: emailIdx)
                return ([email], rest)
            }
            return (providerList, [])
        }()

        return VStack(spacing: btnSpacing) {
            ForEach(Array(topGroup.enumerated()), id: \.offset) { _, provider in
                socialLoginButton(provider, btnStyle: btnStyle, btnHeight: btnHeight, blockRadius: btnRadius)
            }
            if placement == "below_inputs" && !topGroup.isEmpty && !bottomGroup.isEmpty {
                // Subtract the VStack's own spacing so the visual gap between the
                // email button and the first OAuth button equals emailSpacer.
                Color.clear.frame(height: max(0, emailSpacer - btnSpacing))
            }
            ForEach(Array(bottomGroup.enumerated()), id: \.offset) { _, provider in
                socialLoginButton(provider, btnStyle: btnStyle, btnHeight: btnHeight, blockRadius: btnRadius)
            }

            // Optional divider between social login and other options
            if block.show_divider == true {
                HStack(spacing: 12) {
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                    Text(loc?("block.\(block.id).divider", block.divider_text ?? "or") ?? block.divider_text ?? "or")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                }
            }
        }
    }

    /// One social-login button with per-provider color/radius overrides applied.
    /// SPEC-089e amendment — any nil override falls back to the brand default
    /// (Apple=black, Google=#4285F4, email=#6366F1, etc.).
    private func socialLoginButton(_ provider: SocialProviderConfig, btnStyle: String, btnHeight: CGFloat, blockRadius: CGFloat) -> some View {
        let providerType = provider.type ?? ""
        let radius = CGFloat(provider.corner_radius ?? Double(blockRadius))
        let bgColor: Color = {
            if let hex = provider.bg_color, !hex.isEmpty { return Color(hex: hex) }
            return socialLoginBgColor(providerType, style: btnStyle)
        }()
        let textColor: Color = {
            if let hex = provider.text_color, !hex.isEmpty { return Color(hex: hex) }
            return socialLoginTextColor(providerType, style: btnStyle)
        }()
        let borderColor: Color = {
            if let hex = provider.border_color, !hex.isEmpty { return Color(hex: hex) }
            return socialLoginBorderColor(providerType, style: btnStyle)
        }()
        let borderWidth: CGFloat = {
            if let w = provider.border_width { return CGFloat(w) }
            return btnStyle == "outlined" ? 1.5 : 0
        }()
        return Button {
            // The email provider in a social_login block is not actually OAuth — emit
            // `email_login` so hosts can branch their auth handler cleanly. We also
            // dual-emit the legacy `social_login` action this release so existing
            // handlers that switch on `social_login` + value=="email" keep working.
            // The legacy emit will be removed in v1.1.0.
            if providerType == "email" {
                onAction("email_login", providerType)
                onAction("social_login", providerType) // deprecated; remove in v1.1.0
            } else {
                onAction("social_login", providerType)
            }
        } label: {
            HStack(spacing: 10) {
                // SPEC-419 — no glyph for the email provider (parity with Android): the
                // envelope rendered awkwardly on the brand-tinted "Continue with Email"
                // button and its reserved spacing offset the label. Plain centered CTA.
                if providerType != "email" {
                    socialLoginIcon(providerType, iconStyle: provider.icon_style)
                }
                Text(provider.label ?? socialLoginDefaultLabel(providerType))
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: btnHeight)
            .foregroundColor(textColor)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
        }
    }

    // Social login helpers

    /// Social login icon with configurable style.
    /// icon_style: "default", "monochrome_light" (white icons), "monochrome_dark" (black icons),
    ///             "filled" (colored bg), "outline" (border only).
    private func socialLoginIcon(_ type: String, iconStyle: String? = nil) -> AnyView {
        let style = iconStyle ?? "default"
        // Monochrome styles force icon color; default uses provider-native colors
        let monoColor: Color? = style == "monochrome_light" ? .white
            : style == "monochrome_dark" ? .black
            : nil

        switch type {
        case "apple":
            return AnyView(Image(systemName: "applelogo")
                .font(.body.weight(.medium))
                .foregroundColor(monoColor))
        case "google":
            if let mono = monoColor {
                return AnyView(Text("G")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(mono))
            }
            return AnyView(Text("G")
                .font(.system(size: 18, weight: .bold, design: .rounded)))
        case "email":
            return AnyView(Image(systemName: "envelope.fill")
                .font(.body)
                .foregroundColor(monoColor))
        case "facebook":
            return AnyView(Text("f")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(monoColor ?? Color(hex: "#1877F2")))
        case "github":
            return AnyView(Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.body)
                .foregroundColor(monoColor))
        default:
            return AnyView(Image(systemName: "person.fill")
                .font(.body)
                .foregroundColor(monoColor))
        }
    }

    private func socialLoginDefaultLabel(_ type: String) -> String {
        switch type {
        case "apple": return "Continue with Apple"
        case "google": return "Continue with Google"
        case "email": return "Continue with Email"
        case "facebook": return "Continue with Facebook"
        case "github": return "Continue with GitHub"
        default: return "Continue"
        }
    }

    private func socialLoginBgColor(_ type: String, style: String) -> Color {
        if style == "outlined" || style == "minimal" { return .clear }
        switch type {
        case "apple": return .black
        case "google": return Color(hex: "#4285F4") // Google brand blue
        case "facebook": return Color(hex: "#1877F2")
        case "github": return Color(hex: "#24292E")
        default: return Color(hex: (AppDNA.brandAccentHex ?? "#6366F1"))
        }
    }

    private func socialLoginTextColor(_ type: String, style: String) -> Color {
        if style == "outlined" || style == "minimal" {
            return type == "apple" ? .primary : .primary
        }
        switch type {
        case "apple": return .white
        case "google": return .white // White text on Google brand blue
        case "facebook": return .white
        case "github": return .white
        default: return .white
        }
    }

    private func socialLoginBorderColor(_ type: String, style: String) -> Color {
        if style != "outlined" { return .clear }
        switch type {
        case "google": return Color(hex: "#DADCE0")
        default: return Color.gray.opacity(0.4)
        }
    }

    // MARK: - Timeline (SPEC-089d AC-016)

    private func timelineBlock(_ block: ContentBlock) -> some View {
        let itemList = block.timeline_items ?? []
        let isCompact = block.compact ?? false
        let showConnector = block.show_line ?? true
        let completedCol = Color(hex: block.completed_color ?? "#22C55E")
        let currentCol = Color(hex: block.current_color ?? (AppDNA.brandAccentHex ?? "#6366F1"))
        let upcomingCol = Color(hex: block.upcoming_color ?? "#D1D5DB")

        return VStack(alignment: .leading, spacing: isCompact ? 0 : 8) {
            ForEach(Array(itemList.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 16) {
                    // Left column: status indicator + connecting line
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(timelineStatusColor(item.status ?? "upcoming", completed: completedCol, current: currentCol, upcoming: upcomingCol))
                                .frame(width: 28, height: 28)

                            if item.status == "completed" {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            } else if item.status == "current" {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 10, height: 10)
                            }
                        }

                        if showConnector && index < itemList.count - 1 {
                            Rectangle()
                                .fill(Color(hex: block.line_color ?? "#E5E7EB"))
                                .frame(width: 2)
                                .frame(minHeight: isCompact ? 20 : 32)
                        }
                    }

                    // Right column: title + subtitle
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title ?? "")
                            .font(.subheadline.weight(.semibold))
                            .applyTextStyle(block.title_style)
                            .foregroundColor(item.status == "upcoming" ? .secondary : .primary)

                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .applyTextStyle(block.subtitle_style)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.bottom, isCompact ? 8 : 12)

                    Spacer()
                }
            }
        }
    }

    private func timelineStatusColor(_ status: String, completed: Color, current: Color, upcoming: Color) -> Color {
        switch status {
        case "completed": return completed
        case "current": return current
        default: return upcoming
        }
    }

    // MARK: - Rich Text (SPEC-089d AC-020)

    private func richTextBlock(_ block: ContentBlock) -> some View {
        let content = block.markdown_content ?? block.text ?? ""
        let isLegal = block.rich_text_variant == "legal"
        let linkCol = Color(hex: block.link_color ?? (AppDNA.brandAccentHex ?? "#6366F1"))

        // SPEC-205 adjacent fix: honor `base_style.alignment` for rich_text.
        // Previously both `.multilineTextAlignment` and the outer frame alignment
        // were hardcoded based ONLY on `rich_text_variant == "legal"`, which
        // meant authored center/right alignment was silently dropped — most
        // visible inside `child_row` where the frame fills the cell and the
        // left-alignment overrode the authored value. Now: authored alignment
        // wins; legal keeps its center default when author didn't set one.
        let authored = block.base_style?.alignment
        let textAlign: TextAlignment = {
            switch authored {
            case "center": return .center
            case "right": return .trailing
            case "left": return .leading
            default: return isLegal ? .center : .leading
            }
        }()
        let frameAlign: Alignment = {
            switch authored {
            case "center": return .center
            case "right": return .trailing
            case "left": return .leading
            default: return isLegal ? .center : .leading
            }
        }()

        return Group {
            if #available(iOS 15.0, *) {
                let textCol: Color? = block.base_style?.color.map { Color(hex: $0) }
                let attributed = parseMarkdownToAttributedString(content, linkColor: linkCol, textColor: textCol)
                Text(attributed)
                    .font(isLegal ? .caption : .body)
                    .foregroundColor(isLegal ? .secondary : .primary)
                    .applyTextStyle(block.base_style)
                    // Apply AFTER applyTextStyle — its internal multilineTextAlignment
                    // would otherwise override ours when base_style.alignment is unset.
                    .multilineTextAlignment(textAlign)
                    .frame(maxWidth: .infinity, alignment: frameAlign)
            } else {
                // Fallback: render as plain text, stripping markdown tokens
                Text(stripMarkdown(content))
                    .font(isLegal ? .caption : .body)
                    .foregroundColor(isLegal ? .secondary : .primary)
                    .applyTextStyle(block.base_style)
                    .multilineTextAlignment(textAlign)
                    .frame(maxWidth: .infinity, alignment: frameAlign)
            }
        }
    }

    /// Parse subset of markdown (**bold**, *italic*, [link](url), ++underline++)
    /// to AttributedString. `++text++` is a custom extension — native
    /// CommonMark has no underline syntax, but the parser leaves `++`
    /// pairs verbatim so we can post-process them here.
    @available(iOS 15.0, *)
    private func parseMarkdownToAttributedString(_ markdown: String, linkColor: Color, textColor: Color? = nil) -> AttributedString {
        // EPIC-9 two fixes: (1) `.inlineOnlyPreservingWhitespace` STOPS at the first paragraph
        // break (\n\n), so multi-paragraph content previously rendered only its first line — parse
        // each line separately and rejoin with newlines. (2) `Text(AttributedString)` ignores the
        // `.foregroundColor` view modifier because the markdown runs carry their own label color —
        // so force the authored `base_style.color` onto every non-link run (matches Android).
        let lines = markdown.components(separatedBy: "\n")
        var result = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { result.append(AttributedString("\n")) }
            if var parsed = try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                for run in parsed.runs {
                    if run.link != nil {
                        parsed[run.range].foregroundColor = UIColor(linkColor)
                        parsed[run.range].underlineStyle = .single  // match Android's underlined links
                    } else if let textColor {
                        parsed[run.range].foregroundColor = UIColor(textColor)
                    }
                }
                result.append(parsed)
            } else {
                result.append(AttributedString(line))
            }
        }
        // Apply AppDNA-specific `++underline++` after native parsing.
        applyUnderlineMarkers(&result)
        return result
    }

    /// Post-process `++text++` markers in the parsed AttributedString:
    /// apply `.underlineStyle = .single` to the inner range and remove
    /// the `++` marker characters. Collects ranges forward, then mutates
    /// back-to-front so prior deletions don't invalidate later indices.
    @available(iOS 15.0, *)
    private func applyUnderlineMarkers(_ attr: inout AttributedString) {
        var marks: [(Range<AttributedString.Index>, Range<AttributedString.Index>)] = []
        var cursor = attr.startIndex
        while cursor < attr.endIndex {
            guard let openRange = attr[cursor...].range(of: "++") else { break }
            let afterOpen = openRange.upperBound
            guard afterOpen < attr.endIndex,
                  let closeRange = attr[afterOpen...].range(of: "++") else { break }
            marks.append((openRange, closeRange))
            cursor = closeRange.upperBound
        }
        for (openRange, closeRange) in marks.reversed() {
            let innerRange = openRange.upperBound..<closeRange.lowerBound
            attr[innerRange].underlineStyle = .single
            attr.removeSubrange(closeRange)
            attr.removeSubrange(openRange)
        }
    }

    /// Strip markdown tokens for pre-iOS 15 fallback.
    private func stripMarkdown(_ text: String) -> String {
        var result = text
        // Bold: **text** or __text__
        result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "__(.+?)__", with: "$1", options: .regularExpression)
        // Italic: *text* or _text_
        result = result.replacingOccurrences(of: "\\*(.+?)\\*", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "_(.+?)_", with: "$1", options: .regularExpression)
        // Links: [text](url)
        result = result.replacingOccurrences(of: "\\[(.+?)\\]\\(.+?\\)", with: "$1", options: .regularExpression)
        return result
    }

    // MARK: - Progress Bar (SPEC-089d AC-021)

    private func progressBarBlock(_ block: ContentBlock) -> some View {
        let variant = block.progress_variant ?? "continuous"
        // AC-021: Auto-bind to step index when no explicit values set
        let totalSegs = block.total_segments ?? totalSteps
        let filledSegs: Int = {
            if let explicit = block.filled_segments { return explicit }
            if block.progress_value != nil { return block.filled_segments ?? 1 }
            // Auto-bind: current step index + 1 (1-based fill)
            return currentStepIndex + 1
        }()
        let barH = CGFloat(block.bar_height ?? 6)
        let barRadius = CGFloat(block.corner_radius ?? 3)
        let fillColor = Color(hex: block.bar_color ?? (AppDNA.brandAccentHex ?? "#6366F1"))
        // EPIC-2 — multiple progress colors at once (horizontal gradient across the fill).
        let gradCols = (block.bar_gradient_colors ?? []).map { Color(hex: $0) }
        let fillStyle: AnyShapeStyle = gradCols.count >= 2
            ? AnyShapeStyle(LinearGradient(colors: gradCols, startPoint: .leading, endPoint: .trailing))
            : AnyShapeStyle(fillColor)
        let trackCol = Color(hex: block.track_color ?? "#E5E7EB")
        let gap = CGFloat(block.segment_gap ?? 4)

        return VStack(spacing: 8) {
            if block.show_label == true {
                Text("Step \(filledSegs) of \(totalSegs)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if variant == "segmented" {
                // Segmented: individual rounded bars
                HStack(spacing: gap) {
                    ForEach(0..<totalSegs, id: \.self) { index in
                        RoundedRectangle(cornerRadius: barRadius)
                            .fill(index < filledSegs ? fillColor : trackCol)
                            .frame(height: barH)
                    }
                }
            } else {
                // Continuous: single track + fill
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: barRadius)
                            .fill(trackCol)
                            .frame(height: barH)

                        let fraction = totalSegs > 0 ? CGFloat(filledSegs) / CGFloat(totalSegs) : 0
                        RoundedRectangle(cornerRadius: barRadius)
                            .fill(fillStyle)
                            .frame(width: geometry.size.width * min(fraction, 1.0), height: barH)
                    }
                }
                .frame(height: barH)
            }
        }
    }

    // MARK: - Stack (ZStack container — SPEC-089d AC-024)

    @ViewBuilder
    private func stackBlock(_ block: ContentBlock) -> some View {
        let childBlocks = (block.children ?? []).sorted { ($0.z_index ?? 0) < ($1.z_index ?? 0) }
        let align: Alignment = {
            switch block.alignment {
            case "top_left", "topLeading": return .topLeading
            case "top", "topCenter": return .top
            case "top_right", "topTrailing": return .topTrailing
            case "left", "leading": return .leading
            case "right", "trailing": return .trailing
            case "bottom_left", "bottomLeading": return .bottomLeading
            case "bottom", "bottomCenter": return .bottom
            case "bottom_right", "bottomTrailing": return .bottomTrailing
            default: return .center
            }
        }()

        ZStack(alignment: align) {
            ForEach(childBlocks) { child in
                renderBlock(child)
            }
        }
    }

    // MARK: - Row (HStack container — SPEC-089d AC-025)

    @ViewBuilder
    private func rowBlock(_ block: ContentBlock) -> some View {
        let childBlocks = block.children ?? block.stack_children ?? []
        let rowGap = CGFloat(block.gap ?? 8)
        let direction = block.row_direction ?? "horizontal"
        let childFill = block.row_child_fill ?? true

        // Column ratios: "1:2", "1:1:2", "2:3" — proportional widths for horizontal layout.
        // Each number is a flex weight. Children map 1:1 to ratios; extra children get equal weight.
        let ratioStr = (block.field_config?["column_ratios"]?.value as? String) ?? block.column_ratios
        let ratios: [CGFloat] = parseColumnRatios(ratioStr)

        // Row background: opacity + blur (same as select options)
        let rowBgOpacity = CGFloat((cfgDouble(block.field_config?["background_opacity"])) ?? 1.0)
        let rowUseBlur = (block.field_config?["blur_background"]?.value as? Bool) == true
        let rowBorderW = CGFloat((cfgDouble(block.field_config?["border_width"])) ?? 0)
        let rowBorderCol = (block.field_config?["border_color"]?.value as? String).map { Color(hex: $0) }
        let rowBgCol = (block.field_config?["bg_color"]?.value as? String).map { Color(hex: $0) }
        let rowCornerR = CGFloat((cfgDouble(block.field_config?["corner_radius"])) ?? 0)

        // Leading icon slot (for info-card pattern: icon + children layout)
        let leadingIcon = block.field_config?["leading_icon"]?.value as? String
        let leadingIconSize = CGFloat((cfgDouble(block.field_config?["leading_icon_size"])) ?? 24)
        let leadingIconColor = (block.field_config?["leading_icon_color"]?.value as? String).map { Color(hex: $0) }
        let leadingIconBgColor = (block.field_config?["leading_icon_bg_color"]?.value as? String).map { Color(hex: $0) }
        let leadingIconBgSize = CGFloat((cfgDouble(block.field_config?["leading_icon_bg_size"])) ?? (leadingIconSize + 16))

        // Vertical alignment for HStack, horizontal for VStack
        let vAlign: VerticalAlignment = {
            switch block.align_items {
            case "top": return .top
            case "bottom": return .bottom
            default: return .center
            }
        }()
        let hAlign: HorizontalAlignment = {
            switch block.align_items {
            case "leading", "start": return .leading
            case "trailing", "end": return .trailing
            default: return .center
            }
        }()

        Group {
            if direction == "vertical" {
                VStack(alignment: hAlign, spacing: rowGap) {
                    if let icon = leadingIcon {
                        rowLeadingIconView(icon: icon, size: leadingIconSize, color: leadingIconColor, bgColor: leadingIconBgColor, bgSize: leadingIconBgSize)
                    }
                    ForEach(childBlocks) { child in
                        renderBlock(child)
                            .applyRelativeSizing(width: child.element_width, height: child.element_height)
                            .frame(maxWidth: childFill ? .infinity : nil)
                            .zIndex(child.overflow == "visible" ? 1 : 0)
                    }
                }
            } else if !ratios.isEmpty {
                // Ratio-driven horizontal row — explicit proportional
                // widths. Leading icon (if present) sits outside the
                // proportional block since it has its own intrinsic
                // size; the ratio applies only to the actual children.
                HStack(alignment: vAlign, spacing: rowGap) {
                    if let icon = leadingIcon {
                        rowLeadingIconView(icon: icon, size: leadingIconSize, color: leadingIconColor, bgColor: leadingIconBgColor, bgSize: leadingIconBgSize)
                    }
                    ProportionalHStack(ratios: ratios, spacing: rowGap, alignment: vAlign) {
                        ForEach(childBlocks) { child in
                            renderBlock(child)
                                .applyRelativeSizing(width: child.element_width, height: child.element_height)
                                .zIndex(child.overflow == "visible" ? 1 : 0)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: vAlign, spacing: rowGap) {
                    if let icon = leadingIcon {
                        rowLeadingIconView(icon: icon, size: leadingIconSize, color: leadingIconColor, bgColor: leadingIconBgColor, bgSize: leadingIconBgSize)
                    }
                    ForEach(childBlocks) { child in
                        renderBlock(child)
                            .applyRelativeSizing(width: child.element_width, height: child.element_height)
                            .frame(maxWidth: childFill ? .infinity : nil)
                            .zIndex(child.overflow == "visible" ? 1 : 0)
                    }
                }
            }
        }
        // Row container styling: bg, border, blur, opacity
        .if(rowBgCol != nil || rowBorderW > 0 || rowUseBlur) { view in
            view
                .padding(rowBorderW > 0 ? 12 : 0)
                .background {
                    ZStack {
                        if rowUseBlur {
                            RoundedRectangle(cornerRadius: rowCornerR).fill(.ultraThinMaterial)
                        }
                        if let bg = rowBgCol {
                            RoundedRectangle(cornerRadius: rowCornerR).fill(bg.opacity(rowBgOpacity))
                        }
                        if rowBorderW > 0, let bc = rowBorderCol {
                            RoundedRectangle(cornerRadius: rowCornerR).strokeBorder(bc, lineWidth: rowBorderW)
                        }
                    }
                }
        }
    }

    /// Leading icon with optional circle background (for screenshot 11 info-card rows).
    @ViewBuilder
    private func rowLeadingIconView(icon: String, size: CGFloat, color: Color?, bgColor: Color?, bgSize: CGFloat) -> some View {
        ZStack {
            if let bgColor {
                Circle()
                    .fill(bgColor.opacity(0.15))
                    .frame(width: bgSize, height: bgSize)
            }
            if UIImage(systemName: icon) != nil {
                Image(systemName: icon)
                    // SPEC-419 — render the glyph at the CONFIGURED leading_icon_size (was
                    // size * 0.6, which shrank a 24pt setting to a tiny 14pt glyph). Now the
                    // console's leading_icon_size IS the glyph point size, so it scales
                    // directly. .fixedSize() keeps it from being clipped/compressed when the
                    // icon is enlarged.
                    .font(.system(size: size))
                    .foregroundColor(color ?? .primary)
                    .fixedSize()
            } else {
                Text(icon).font(.system(size: size)).fixedSize()
            }
        }
        // Reserve at least the glyph's own footprint (and the bg circle when present) so a
        // larger icon is never cut by a tight row/frame.
        .frame(minWidth: bgColor != nil ? bgSize : size, minHeight: bgColor != nil ? bgSize : size)
    }

    /// Parse "1:2" or "1:1:2" into proportional CGFloat weights.
    private func parseColumnRatios(_ str: String?) -> [CGFloat] {
        guard let str, !str.isEmpty else { return [] }
        return str.split(separator: ":").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { CGFloat($0) }
    }

    /// Proportional horizontal layout for row children. Previously the
    /// renderer used `.layoutPriority(weight)` which SwiftUI interprets
    /// as "first in line for ideal size when space is tight" — it is NOT
    /// a proportional width ratio. On a row like [image, text] with
    /// ratios "1:2" that meant the text's higher priority squeezed the
    /// image down to near-zero width → the image silently disappeared
    /// from the render.
    ///
    /// This Layout assigns each child an explicit fraction of the
    /// available width via the real weights, so "1:2" produces a true
    /// 1/3 and 2/3 split regardless of the child's intrinsic size.
    private struct ProportionalHStack: Layout {
        let ratios: [CGFloat]
        let spacing: CGFloat
        let alignment: VerticalAlignment

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let proposedWidth = proposal.width ?? 0
            // Propose each child its fractional width and take the tallest.
            let widths = allocate(width: proposedWidth, count: subviews.count)
            var maxH: CGFloat = 0
            for (idx, sv) in subviews.enumerated() {
                let w = idx < widths.count ? widths[idx] : 0
                let h = sv.sizeThatFits(ProposedViewSize(width: w, height: proposal.height)).height
                if h > maxH { maxH = h }
            }
            return CGSize(width: proposedWidth, height: maxH)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let widths = allocate(width: bounds.width, count: subviews.count)
            var x = bounds.minX
            for (idx, sv) in subviews.enumerated() {
                let w = idx < widths.count ? widths[idx] : 0
                let anchorY: CGFloat
                switch alignment {
                case .top: anchorY = bounds.minY
                case .bottom: anchorY = bounds.maxY
                default: anchorY = bounds.midY
                }
                sv.place(
                    at: CGPoint(x: x, y: anchorY),
                    anchor: (alignment == .top) ? .topLeading : ((alignment == .bottom) ? .bottomLeading : .leading),
                    proposal: ProposedViewSize(width: w, height: bounds.height)
                )
                x += w + spacing
            }
        }

        private func allocate(width: CGFloat, count: Int) -> [CGFloat] {
            guard count > 0 else { return [] }
            let gapTotal = spacing * CGFloat(max(count - 1, 0))
            let avail = max(width - gapTotal, 0)
            // Extend/truncate ratios to match child count. If fewer ratios
            // than children, extra children each get the last ratio's
            // weight (matches existing behavior at the HStack call site).
            var weights: [CGFloat] = []
            for i in 0..<count {
                if i < ratios.count {
                    weights.append(ratios[i])
                } else {
                    weights.append(ratios.last ?? 1)
                }
            }
            let total = weights.reduce(0, +)
            guard total > 0 else { return Array(repeating: avail / CGFloat(count), count: count) }
            return weights.map { avail * ($0 / total) }
        }
    }

    // MARK: - Custom View (SPEC-089d AC-026)

    @ViewBuilder
    private func customViewBlock(_ block: ContentBlock) -> some View {
        let key = block.view_key ?? ""
        if let factory = AppDNA.registeredCustomViews[key] {
            factory()
                .frame(
                    maxWidth: .infinity,
                    maxHeight: block.height.map { CGFloat($0) }
                )
        } else if let placeholderUrl = block.placeholder_image_url, let url = URL(string: placeholderUrl) {
            BundledAsyncPhaseImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .failure:
                    placeholderTextView(block.placeholder_text ?? "[\(key)]")
                default:
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: block.height.map { CGFloat($0) })
        } else {
            placeholderTextView(block.placeholder_text ?? "[\(key)]")
        }
    }

    private func placeholderTextView(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(8)
    }
}
