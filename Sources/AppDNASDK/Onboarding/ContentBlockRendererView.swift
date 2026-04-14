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
        case .wheel_picker: return AnyView(WheelPickerBlockView(block: block))
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
        let fontSize: CGFloat = {
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
        // Apply block.horizontal_align AFTER applyTextStyle so its internal
        // multilineTextAlignment (which defaults to .leading when style.alignment
        // is unset) doesn't wipe out the authored horizontal_align.
        return Text(loc?("block.\(block.id).text", text) ?? text)
            .font(.system(size: fontSize, weight: .bold))
            .applyTextStyle(block.style)
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
        // Same ordering as headingBlock — applyTextStyle first so horizontal_align
        // wins when style.alignment isn't explicitly authored. Customers hit this
        // in row children where the authored center/right was silently dropped.
        return Text(loc?("block.\(block.id).text", text) ?? text)
            .font(.body)
            .applyTextStyle(block.style)
            .multilineTextAlignment(textAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    // MARK: - Image

    private func imageBlock(_ block: ContentBlock) -> some View {
        let cr = CGFloat(block.corner_radius ?? 0)
        let isCircle = (block.corner_radius ?? 0) >= 9999
        let fitMode: ContentMode = (block.image_fit == "contain" || block.image_fit == "fit") ? .fit : .fill
        let imgHeight = CGFloat(block.height ?? 200)

        return Group {
            if let urlString = block.image_url, let url = URL(string: urlString) {
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
        let bgColor = Color(hex: block.bg_color ?? "#6366F1")
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
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
                .foregroundColor(Color(hex: "#6366F1")))
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
            .background(Color(hex: block.badge_bg_color ?? "#6366F1"))
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
                .tint(Color(hex: "#6366F1"))
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
        let activeColor = Color(hex: block.active_color ?? "#6366F1")
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

        return VStack(spacing: btnSpacing) {
            ForEach(Array(providerList.enumerated()), id: \.offset) { _, provider in
                let providerType = provider.type ?? ""
                Button {
                    onAction("social_login", providerType)
                } label: {
                    HStack(spacing: 10) {
                        socialLoginIcon(providerType, iconStyle: provider.icon_style)
                        Text(provider.label ?? socialLoginDefaultLabel(providerType))
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: btnHeight)
                    .foregroundColor(socialLoginTextColor(providerType, style: btnStyle))
                    .background(socialLoginBgColor(providerType, style: btnStyle))
                    .clipShape(RoundedRectangle(cornerRadius: btnRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: btnRadius)
                            .stroke(socialLoginBorderColor(providerType, style: btnStyle), lineWidth: btnStyle == "outlined" ? 1.5 : 0)
                    )
                }
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
        default: return Color(hex: "#6366F1")
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
        let currentCol = Color(hex: block.current_color ?? "#6366F1")
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
        let linkCol = Color(hex: block.link_color ?? "#6366F1")

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
                let attributed = parseMarkdownToAttributedString(content, linkColor: linkCol)
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

    /// Parse subset of markdown (**bold**, *italic*, [link](url)) to AttributedString.
    @available(iOS 15.0, *)
    private func parseMarkdownToAttributedString(_ markdown: String, linkColor: Color) -> AttributedString {
        // Try native markdown parsing first (iOS 15+)
        if var result = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            // Override link color
            for run in result.runs {
                if run.link != nil {
                    let range = run.range
                    result[range].foregroundColor = UIColor(linkColor)
                }
            }
            return result
        }
        // Fallback: plain text
        return AttributedString(markdown)
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
        let fillColor = Color(hex: block.bar_color ?? "#6366F1")
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
                            .fill(fillColor)
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
                            .frame(maxWidth: childFill ? .infinity : nil)
                            .zIndex(child.overflow == "visible" ? 1 : 0)
                    }
                }
            } else {
                HStack(alignment: vAlign, spacing: rowGap) {
                    if let icon = leadingIcon {
                        rowLeadingIconView(icon: icon, size: leadingIconSize, color: leadingIconColor, bgColor: leadingIconBgColor, bgSize: leadingIconBgSize)
                    }
                    ForEach(Array(childBlocks.enumerated()), id: \.element.id) { idx, child in
                        let weight = idx < ratios.count ? ratios[idx] : (ratios.isEmpty ? 1 : ratios.last!)
                        renderBlock(child)
                            .frame(maxWidth: childFill ? .infinity : nil)
                            .layoutPriority(Double(weight))
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
                    .font(.system(size: size * 0.6))
                    .foregroundColor(color ?? .primary)
            } else {
                Text(icon).font(.system(size: size * 0.6))
            }
        }
    }

    /// Parse "1:2" or "1:1:2" into proportional CGFloat weights.
    private func parseColumnRatios(_ str: String?) -> [CGFloat] {
        guard let str, !str.isEmpty else { return [] }
        return str.split(separator: ":").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map { CGFloat($0) }
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
