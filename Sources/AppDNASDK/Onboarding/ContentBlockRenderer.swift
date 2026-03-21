import SwiftUI

// MARK: - Content Block Type

public enum ContentBlockType: String, Codable {
    case heading, text, image, button, spacer, list, divider, badge, icon, toggle, video
    // SPEC-085: Rich media block types
    case lottie, rive
    // SPEC-089d Phase A: New onboarding block types
    case page_indicator, wheel_picker, pulsing_avatar, social_login
    case timeline, animated_loading, star_background, countdown_timer
    case rating, rich_text, progress_bar
    // SPEC-089d Phase F: Container & advanced block types
    case stack, custom_view, date_wheel_picker, circular_gauge, row
    // SPEC-089d Nurrai
    case pricing_card
    // SPEC-089d Phase 3: Form input block types (22 types)
    case input_text, input_textarea, input_number, input_email, input_phone
    case input_password, input_date, input_time, input_datetime
    case input_select, input_slider, input_toggle, input_stepper, input_segmented
    case input_location, input_rating, input_range_slider, input_image_picker
    case input_color, input_url, input_chips, input_signature
    // Catch-all for future/unknown block types — prevents decoding failures
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ContentBlockType(rawValue: rawValue) ?? .unknown
    }
}

// MARK: - Block Style Design Tokens (SPEC-089d §6.1)

/// Per-block styling: background, border, shadow, padding, margin, opacity.
public struct BlockStyle: Codable {
    public var background_color: String?
    public var background_gradient: BlockGradientStyle?
    public var border_color: String?
    public var border_width: Double?
    public var border_style: String?   // solid, dashed, dotted
    public var border_radius: Double?
    public var shadow: BlockShadowStyle?
    public var padding_top: Double?
    public var padding_right: Double?
    public var padding_bottom: Double?
    public var padding_left: Double?
    public var margin_top: Double?
    public var margin_bottom: Double?
    public var opacity: Double?
}

/// Shadow definition for block_style.
public struct BlockShadowStyle: Codable {
    public var x: Double
    public var y: Double
    public var blur: Double
    public var spread: Double
    public var color: String
}

/// Gradient definition for block_style background.
public struct BlockGradientStyle: Codable {
    public var angle: Double
    public var start: String
    public var end: String
}

// MARK: - Block Style ViewModifier (SPEC-089d §6.1)

/// Applies `block_style` design tokens to any content block view.
struct BlockStyleModifier: ViewModifier {
    let style: BlockStyle?

    func body(content: Content) -> some View {
        if let s = style {
            content
                // Inner padding
                .padding(.top, CGFloat(s.padding_top ?? 0))
                .padding(.trailing, CGFloat(s.padding_right ?? 0))
                .padding(.bottom, CGFloat(s.padding_bottom ?? 0))
                .padding(.leading, CGFloat(s.padding_left ?? 0))
                // Background
                .background(backgroundView(s))
                // Border
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(s.border_radius ?? 0)))
                .overlay(
                    RoundedRectangle(cornerRadius: CGFloat(s.border_radius ?? 0))
                        .stroke(
                            Color(hex: s.border_color ?? "transparent"),
                            style: borderStrokeStyle(s)
                        )
                )
                // Shadow
                .shadow(
                    color: Color(hex: s.shadow?.color ?? "transparent"),
                    radius: CGFloat(s.shadow?.blur ?? 0) / 2,
                    x: CGFloat(s.shadow?.x ?? 0),
                    y: CGFloat(s.shadow?.y ?? 0)
                )
                // Opacity
                .opacity(s.opacity ?? 1.0)
                // Outer margin
                .padding(.top, CGFloat(s.margin_top ?? 0))
                .padding(.bottom, CGFloat(s.margin_bottom ?? 0))
        } else {
            content
        }
    }

    @ViewBuilder
    private func backgroundView(_ s: BlockStyle) -> some View {
        if let gradient = s.background_gradient {
            LinearGradient(
                colors: [Color(hex: gradient.start), Color(hex: gradient.end)],
                startPoint: gradientStartPoint(angle: gradient.angle),
                endPoint: gradientEndPoint(angle: gradient.angle)
            )
        } else if let bgColor = s.background_color {
            Color(hex: bgColor)
        } else {
            Color.clear
        }
    }

    private func borderStrokeStyle(_ s: BlockStyle) -> StrokeStyle {
        let lineWidth = CGFloat(s.border_width ?? 0)
        switch s.border_style {
        case "dashed":
            return StrokeStyle(lineWidth: lineWidth, dash: [8, 4])
        case "dotted":
            return StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [2, 4])
        default: // solid
            return StrokeStyle(lineWidth: lineWidth)
        }
    }

    private func gradientStartPoint(angle: Double) -> UnitPoint {
        let rads = angle * .pi / 180
        return UnitPoint(x: 0.5 - sin(rads) / 2, y: 0.5 + cos(rads) / 2)
    }

    private func gradientEndPoint(angle: Double) -> UnitPoint {
        let rads = angle * .pi / 180
        return UnitPoint(x: 0.5 + sin(rads) / 2, y: 0.5 - cos(rads) / 2)
    }
}

extension View {
    /// Apply block_style design tokens (SPEC-089d §6.1).
    func applyBlockStyle(_ style: BlockStyle?) -> some View {
        modifier(BlockStyleModifier(style: style))
    }
}

// MARK: - Visibility Condition (SPEC-089d §6.3)

/// Condition that determines whether a block should be rendered.
public struct VisibilityCondition: Codable {
    public let type: String       // always, when_equals, when_not_equals, when_not_empty, when_empty, when_gt, when_lt, expression
    public let variable: String?  // dot-path e.g. "responses.step1.age"
    public let value: AnyCodable? // comparison value
    public let expression: String? // for complex expressions
}

/// Evaluates a visibility condition against the current data context.
func evaluateVisibilityCondition(
    _ condition: VisibilityCondition?,
    responses: [String: Any],
    hookData: [String: Any]?,
    userTraits: [String: Any]? = nil,
    sessionData: [String: Any]? = nil
) -> Bool {
    guard let cond = condition else { return true }

    switch cond.type {
    case "always":
        return true
    case "when_equals":
        let resolved = resolveDotPath(cond.variable, responses: responses, hookData: hookData, userTraits: userTraits, sessionData: sessionData)
        let expected = cond.value?.value
        return valuesEqual(resolved, expected)
    case "when_not_equals":
        let resolved = resolveDotPath(cond.variable, responses: responses, hookData: hookData, userTraits: userTraits, sessionData: sessionData)
        let expected = cond.value?.value
        return !valuesEqual(resolved, expected)
    case "when_not_empty":
        let resolved = resolveDotPath(cond.variable, responses: responses, hookData: hookData, userTraits: userTraits, sessionData: sessionData)
        return resolved != nil && "\(resolved!)" != ""
    case "when_empty":
        let resolved = resolveDotPath(cond.variable, responses: responses, hookData: hookData, userTraits: userTraits, sessionData: sessionData)
        return resolved == nil || "\(resolved!)" == ""
    case "when_gt":
        let resolved = resolveDotPath(cond.variable, responses: responses, hookData: hookData, userTraits: userTraits, sessionData: sessionData)
        return compareNumeric(resolved, cond.value?.value) == .orderedDescending
    case "when_lt":
        let resolved = resolveDotPath(cond.variable, responses: responses, hookData: hookData, userTraits: userTraits, sessionData: sessionData)
        return compareNumeric(resolved, cond.value?.value) == .orderedAscending
    default:
        return true // unknown condition types default to visible
    }
}

/// Resolves a dot-path variable from the evaluation context.
private func resolveDotPath(
    _ path: String?,
    responses: [String: Any],
    hookData: [String: Any]?,
    userTraits: [String: Any]?,
    sessionData: [String: Any]?
) -> Any? {
    guard let path = path, !path.isEmpty else { return nil }
    let parts = path.split(separator: ".").map(String.init)
    guard parts.count >= 2 else { return nil }

    let root: [String: Any]?
    switch parts[0] {
    case "responses": root = responses
    case "hook_data": root = hookData
    case "user": root = userTraits
    case "session": root = sessionData
    default: root = nil
    }

    guard var current: Any = root else { return nil }
    for part in parts.dropFirst() {
        if let dict = current as? [String: Any], let next = dict[part] {
            current = next
        } else {
            return nil
        }
    }
    return current
}

/// Compares two values as strings for equality.
private func valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
    if a == nil && b == nil { return true }
    guard let a = a, let b = b else { return false }
    return "\(a)" == "\(b)"
}

/// Compares two values numerically.
private func compareNumeric(_ a: Any?, _ b: Any?) -> ComparisonResult {
    let numA = toDouble(a)
    let numB = toDouble(b)
    guard let na = numA, let nb = numB else { return .orderedSame }
    if na < nb { return .orderedAscending }
    if na > nb { return .orderedDescending }
    return .orderedSame
}

private func toDouble(_ value: Any?) -> Double? {
    guard let v = value else { return nil }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let s = v as? String { return Double(s) }
    return nil
}

// MARK: - Entrance Animation (SPEC-089d §6.4)

/// Configuration for entrance animation on a content block.
public struct EntranceAnimation: Codable {
    public let type: String       // none, fade_in, slide_up, slide_down, slide_left, slide_right, scale_up, scale_down, bounce, flip
    public let duration_ms: Int?  // 100-2000
    public let delay_ms: Int?     // 0-5000
    public let easing: String?    // linear, ease, ease_in, ease_out, ease_in_out, spring
    public let spring_damping: Double? // 0.1-1.0
}

// MARK: - Pressed Style (SPEC-089d §6.5)

/// Style to apply when an interactive element is pressed.
public struct PressedStyle: Codable {
    public let bg_color: String?
    public let text_color: String?
    public let scale: Double?    // 0.85-1.0
    public let opacity: Double?  // 0.5-1.0
}

// MARK: - Form Field Style (SPEC-089d §5.2)

/// Custom visual styling for form input blocks.
public struct FormFieldBlockStyle: Codable {
    public let background_color: String?
    public let border_color: String?
    public let border_width: Double?
    public let corner_radius: Double?
    public let height: String?           // sm, md, lg
    public let text_color: String?
    public let placeholder_color: String?
    public let font_size: Double?
    public let font_weight: String?
    public let focused_border_color: String?
    public let focused_background_color: String?
    public let label_color: String?
    public let label_font_size: Double?
    public let error_border_color: String?
    public let error_text_color: String?
    public let track_color: String?
    public let fill_color: String?
    public let thumb_color: String?
    public let toggle_on_color: String?
    public let toggle_off_color: String?
}

/// Option for select, chips, and segmented inputs.
public struct InputOption: Codable, Identifiable {
    public let value: String
    public let label: String
    public var id: String { value }
}

// MARK: - Relative Sizing Helper (SPEC-089d §6.7)

/// Parses a size string and returns a frame modifier.
enum SizeValue {
    case fill
    case auto_
    case percent(CGFloat)
    case px(CGFloat)

    static func parse(_ str: String?) -> SizeValue? {
        guard let s = str?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return nil }
        if s == "fill" { return .fill }
        if s == "auto" { return .auto_ }
        if s.hasSuffix("%"), let num = Double(s.dropLast()) { return .percent(CGFloat(num) / 100.0) }
        if s.hasSuffix("px"), let num = Double(s.dropLast(2)) { return .px(CGFloat(num)) }
        if let num = Double(s) { return .px(CGFloat(num)) }
        return nil
    }
}

// MARK: - Template String Resolution (SPEC-089d §6.6)

/// Resolves `{{variable}}` template strings in text.
func resolveTemplateString(
    _ text: String,
    hookData: [String: Any]?,
    responses: [String: Any],
    sessionData: [String: Any]? = nil,
    userTraits: [String: Any]? = nil
) -> String {
    var result = text
    let pattern = "\\{\\{\\s*([a-zA-Z0-9_.]+)\\s*\\}\\}"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
    let nsRange = NSRange(text.startIndex..., in: text)
    let matches = regex.matches(in: text, range: nsRange)

    // Iterate in reverse to preserve ranges
    for match in matches.reversed() {
        guard let fullRange = Range(match.range, in: result),
              let pathRange = Range(match.range(at: 1), in: result) else { continue }
        let path = String(result[pathRange])
        let resolved = resolveDotPath(path, responses: responses, hookData: hookData, userTraits: userTraits, sessionData: sessionData)
        if let resolved = resolved {
            result.replaceSubrange(fullRange, with: "\(resolved)")
        }
    }
    return result
}

// MARK: - 2D Positioning Modifier (SPEC-089d §6.2)

/// Applies vertical/horizontal alignment + offset positioning to a content block.
struct BlockPositionModifier: ViewModifier {
    let verticalAlign: String?
    let horizontalAlign: String?
    let verticalOffset: Double?
    let horizontalOffset: Double?

    func body(content: Content) -> some View {
        let hasPositioning = verticalAlign != nil || horizontalAlign != nil
            || verticalOffset != nil || horizontalOffset != nil

        if hasPositioning {
            content
                .frame(
                    maxWidth: .infinity,
                    alignment: mapAlignment(horizontal: horizontalAlign, vertical: verticalAlign)
                )
                .offset(
                    x: CGFloat(horizontalOffset ?? 0),
                    y: CGFloat(verticalOffset ?? 0)
                )
        } else {
            content
        }
    }

    private func mapAlignment(horizontal: String?, vertical: String?) -> Alignment {
        let h: HorizontalAlignment = {
            switch horizontal {
            case "left": return .leading
            case "right": return .trailing
            default: return .center
            }
        }()
        let v: VerticalAlignment = {
            switch vertical {
            case "top": return .top
            case "bottom": return .bottom
            default: return .center
            }
        }()
        return Alignment(horizontal: h, vertical: v)
    }
}

extension View {
    /// Apply 2D positioning (SPEC-089d §6.2).
    func applyBlockPosition(
        verticalAlign: String?,
        horizontalAlign: String?,
        verticalOffset: Double?,
        horizontalOffset: Double?
    ) -> some View {
        modifier(BlockPositionModifier(
            verticalAlign: verticalAlign,
            horizontalAlign: horizontalAlign,
            verticalOffset: verticalOffset,
            horizontalOffset: horizontalOffset
        ))
    }
}

// MARK: - Entrance Animation Wrapper (SPEC-089d §6.4)

/// Wraps a content block with entrance animation.
struct EntranceAnimationWrapper<Content: View>: View {
    let animation: EntranceAnimation
    let content: () -> Content

    @State private var isVisible = false

    var body: some View {
        content()
            .opacity(animationType.usesOpacity ? (isVisible ? 1 : 0) : 1)
            .offset(x: offsetX, y: offsetY)
            .scaleEffect(scaleValue)
            .rotation3DEffect(
                .degrees(animationType == .flip ? (isVisible ? 0 : 90) : 0),
                axis: (x: 1, y: 0, z: 0)
            )
            .onAppear {
                let delaySeconds = Double(animation.delay_ms ?? 0) / 1000.0
                DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) {
                    withAnimation(swiftUIAnimation) {
                        isVisible = true
                    }
                }
            }
    }

    private enum AnimType: Equatable {
        case none, fadeIn, slideUp, slideDown, slideLeft, slideRight
        case scaleUp, scaleDown, bounce, flip

        var usesOpacity: Bool {
            switch self {
            case .fadeIn, .scaleUp, .scaleDown, .bounce, .flip: return true
            default: return false
            }
        }
    }

    private var animationType: AnimType {
        switch animation.type {
        case "fade_in": return .fadeIn
        case "slide_up": return .slideUp
        case "slide_down": return .slideDown
        case "slide_left": return .slideLeft
        case "slide_right": return .slideRight
        case "scale_up": return .scaleUp
        case "scale_down": return .scaleDown
        case "bounce": return .bounce
        case "flip": return .flip
        default: return .none
        }
    }

    private var offsetX: CGFloat {
        switch animationType {
        case .slideLeft: return isVisible ? 0 : -50
        case .slideRight: return isVisible ? 0 : 50
        default: return 0
        }
    }

    private var offsetY: CGFloat {
        switch animationType {
        case .slideUp: return isVisible ? 0 : 50
        case .slideDown: return isVisible ? 0 : -50
        default: return 0
        }
    }

    private var scaleValue: CGFloat {
        switch animationType {
        case .scaleUp: return isVisible ? 1 : 0.5
        case .scaleDown: return isVisible ? 1 : 1.5
        case .bounce: return isVisible ? 1 : 0.3
        default: return 1
        }
    }

    private var swiftUIAnimation: Animation {
        let duration = Double(animation.duration_ms ?? 300) / 1000.0
        switch animation.easing {
        case "spring":
            return .spring(dampingFraction: animation.spring_damping ?? 0.7)
        case "ease_in":
            return .easeIn(duration: duration)
        case "ease_out":
            return .easeOut(duration: duration)
        case "ease_in_out":
            return .easeInOut(duration: duration)
        case "ease":
            return .easeInOut(duration: duration)
        default:
            return .linear(duration: duration)
        }
    }
}

// MARK: - Pressed Style ViewModifier (SPEC-089d §6.5)

/// Applies press/tap state visual feedback to interactive elements.
struct PressedStyleModifier: ViewModifier {
    let pressedStyle: PressedStyle?

    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        if let ps = pressedStyle {
            content
                .scaleEffect(isPressed ? CGFloat(ps.scale ?? 0.97) : 1.0)
                .opacity(isPressed ? (ps.opacity ?? 0.9) : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isPressed)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isPressed) { _, state, _ in
                            state = true
                        }
                )
        } else {
            content
        }
    }
}

extension View {
    /// Apply press/tap state styling (SPEC-089d §6.5).
    func applyPressedStyle(_ style: PressedStyle?) -> some View {
        modifier(PressedStyleModifier(pressedStyle: style))
    }
}

// MARK: - Relative Sizing ViewModifier (SPEC-089d §6.7)

/// Applies relative sizing (element_width, element_height) to a content block.
struct RelativeSizingModifier: ViewModifier {
    let width: String?
    let height: String?

    func body(content: Content) -> some View {
        content
            .modifier(WidthModifier(size: SizeValue.parse(width)))
            .modifier(HeightModifier(size: SizeValue.parse(height)))
    }

    struct WidthModifier: ViewModifier {
        let size: SizeValue?
        func body(content: Content) -> some View {
            switch size {
            case .fill:
                content.frame(maxWidth: .infinity)
            case .px(let val):
                content.frame(width: val)
            case .percent(let fraction):
                GeometryReader { geo in
                    content.frame(width: geo.size.width * fraction)
                }
            case .auto_, .none:
                content
            }
        }
    }

    struct HeightModifier: ViewModifier {
        let size: SizeValue?
        func body(content: Content) -> some View {
            switch size {
            case .fill:
                content.frame(maxHeight: .infinity)
            case .px(let val):
                content.frame(height: val)
            case .percent(let fraction):
                GeometryReader { geo in
                    content.frame(height: geo.size.height * fraction)
                }
            case .auto_, .none:
                content
            }
        }
    }
}

extension View {
    /// Apply relative sizing (SPEC-089d §6.7).
    func applyRelativeSizing(width: String?, height: String?) -> some View {
        modifier(RelativeSizingModifier(width: width, height: height))
    }
}

// MARK: - Nested Codable types for SPEC-089d block fields

/// A single timeline item for the `timeline` block.
public struct TimelineItemConfig: Codable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let icon: String?
    public let status: String  // completed | current | upcoming
}

/// A social login provider entry for the `social_login` block.
public struct SocialProviderConfig: Codable {
    public let type: String    // apple, google, email, facebook, github
    public let label: String?
    public let enabled: Bool?
}

/// A single item for the `animated_loading` checklist.
public struct LoadingItemConfig: Codable {
    public let label: String
    public let duration_ms: Int?
    public let icon: String?
}

/// Countdown label overrides.
public struct CountdownLabelsConfig: Codable {
    public let days: String?
    public let hours: String?
    public let minutes: String?
    public let seconds: String?
}

/// A pricing plan entry for the `pricing_card` block.
public struct PricingPlanConfig: Codable, Identifiable {
    public let id: String
    public let label: String
    public let price: String
    public let period: String
    public let badge: String?
    public let is_highlighted: Bool?
}

/// A date wheel picker column for the `date_wheel_picker` block.
public struct DateWheelColumnConfig: Codable {
    public let type: String   // day | month | year | custom
    public let label: String?
    public let values: [String]?
}

/// Star/particle background config for `star_background` block.
public struct StarParticle {
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
    var speed: CGFloat
}

// MARK: - Content Block model

public struct ContentBlock: Codable, Identifiable {
    public let id: String
    public let type: ContentBlockType
    // Common
    public let text: String?
    public let style: TextStyleConfig?
    // Heading
    public let level: Int?
    // Image / Video
    public let image_url: String?
    public let alt: String?
    public let corner_radius: Double?
    public let height: Double?
    // Button
    public let variant: String?
    public let action: String?     // next, skip, link, permission
    public let action_value: String?  // URL for link, permission type for permission
    public let bg_color: String?
    public let text_color: String?
    public let button_corner_radius: Double?
    // Spacer
    public let spacer_height: Double?
    // List
    public let items: [String]?
    public let list_style: String?   // bullet, numbered, check
    // Divider
    public let divider_color: String?
    public let divider_thickness: Double?
    public let divider_margin_y: Double?
    // Badge
    public let badge_text: String?
    public let badge_bg_color: String?
    public let badge_text_color: String?
    public let badge_corner_radius: Double?
    // Icon
    public let icon_emoji: String?
    public let icon_size: Double?
    public let icon_alignment: String?
    // Toggle
    public let toggle_label: String?
    public let toggle_description: String?
    public let toggle_default: Bool?
    // Video
    public let video_url: String?
    public let video_thumbnail_url: String?
    public let video_height: Double?
    public let video_corner_radius: Double?
    // SPEC-085: Video playback options
    public let autoplay: Bool?
    public let loop: Bool?
    public let muted: Bool?
    public let controls: Bool?
    // SPEC-085: Lottie
    public let lottie_url: String?
    public let lottie_speed: Double?
    public let lottie_width: Double?
    public let lottie_height: Double?
    public let play_on_scroll: Bool?
    public let play_on_tap: Bool?
    // SPEC-085: Rive
    public let rive_url: String?
    public let artboard: String?
    public let state_machine: String?
    public let trigger_on_step_complete: String?
    // SPEC-085: Icon reference (structured icon)
    public let icon_ref: IconReference?

    // SPEC-089d §6.1: Per-block style design tokens
    public let block_style: BlockStyle?

    // SPEC-089d §6.2: 2D positioning
    public let vertical_align: String?
    public let horizontal_align: String?
    public let vertical_offset: Double?
    public let horizontal_offset: Double?

    // SPEC-089d Phase A: page_indicator fields
    public let dot_count: Int?
    public let active_index: Int?
    public let active_color: String?
    public let inactive_color: String?
    public let dot_size: Double?
    public let dot_spacing: Double?
    public let active_dot_width: Double?
    public let alignment: String?

    // SPEC-089d Phase A: social_login fields
    public let providers: [SocialProviderConfig]?
    public let button_style: String?       // filled, outlined, minimal
    public let button_height: Double?
    public let spacing: Double?
    public let show_divider: Bool?
    public let divider_text: String?

    // SPEC-089d Phase A: countdown_timer fields
    public let timer_variant: String?      // digital, circular, flip, bar
    public let duration_seconds: Int?
    public let show_days: Bool?
    public let show_hours: Bool?
    public let show_minutes: Bool?
    public let show_seconds: Bool?
    public let labels: CountdownLabelsConfig?
    public let on_expire_action: String?   // hide, show_expired_text, auto_advance
    public let expired_text: String?
    public let accent_color: String?
    public let font_size: Double?

    // SPEC-089d Phase A: rating fields
    public let max_stars: Int?
    public let default_rating: Double?
    public let star_size: Double?
    public let filled_color: String?
    public let empty_color: String?
    public let allow_half: Bool?
    public let field_id: String?
    public let rating_label: String?

    // SPEC-089d Phase A: rich_text fields
    public let markdown_content: String?
    public let rich_text_variant: String?  // default, legal
    public let base_style: TextStyleConfig?
    public let link_color: String?

    // SPEC-089d Phase A: progress_bar fields
    public let progress_variant: String?   // continuous, segmented
    public let progress_value: Double?
    public let total_segments: Int?
    public let filled_segments: Int?
    public let bar_height: Double?
    public let bar_color: String?
    public let track_color: String?
    public let show_label: Bool?
    public let segment_gap: Double?

    // SPEC-089d Phase A: timeline fields
    public let timeline_items: [TimelineItemConfig]?
    public let line_color: String?
    public let completed_color: String?
    public let current_color: String?
    public let upcoming_color: String?
    public let show_line: Bool?
    public let compact: Bool?
    public let title_style: TextStyleConfig?
    public let subtitle_style: TextStyleConfig?

    // SPEC-089d Phase A: animated_loading fields
    public let loading_variant: String?    // circular, linear, checklist
    public let loading_items: [LoadingItemConfig]?
    public let progress_color: String?
    public let check_color: String?
    public let total_duration_ms: Int?
    public let auto_advance: Bool?
    public let show_percentage: Bool?

    // SPEC-089d Phase F: circular_gauge fields
    public let gauge_value: Double?
    public let max_value: Double?
    public let sublabel: String?
    public let stroke_width: Double?
    public let label_color: String?
    public let label_font_size: Double?
    public let animate: Bool?
    public let animation_duration_ms: Int?

    // SPEC-089d Phase F: date_wheel_picker fields
    public let columns: [DateWheelColumnConfig]?
    public let default_date_value: String?
    public let min_date: String?
    public let max_date: String?
    public let highlight_color: String?
    public let haptic_on_scroll: Bool?

    // SPEC-089d Phase F: stack / row fields (container blocks)
    public let children: [ContentBlock]?
    public let z_index: Double?
    public let gap: Double?
    public let wrap: Bool?
    public let justify: String?
    public let align_items: String?

    // SPEC-089d Phase F: custom_view fields
    public let view_key: String?
    public let custom_config: [String: AnyCodable]?
    public let placeholder_image_url: String?
    public let placeholder_text: String?

    // SPEC-089d Phase F: star_background fields
    public let particle_type: String?      // stars, sparkles, dots, snow, bokeh
    public let density: String?            // sparse, medium, dense
    public let speed: String?              // slow, medium, fast
    public let secondary_color: String?
    public let size_range: [Double]?
    public let fullscreen: Bool?

    // SPEC-089d Phase F: wheel_picker fields
    public let min_value: Double?
    public let max_value_picker: Double?
    public let step_value: Double?
    public let default_picker_value: Double?
    public let unit: String?
    public let unit_position: String?
    public let visible_items: Int?

    // SPEC-089d Phase F: pulsing_avatar fields
    public let pulse_color: String?
    public let pulse_ring_count: Int?
    public let pulse_speed: Double?
    public let border_width: Double?
    public let border_color: String?

    // SPEC-089d Nurrai: pricing_card fields
    public let pricing_plans: [PricingPlanConfig]?
    public let pricing_layout: String?     // stack, side_by_side

    // SPEC-089d Phase 3: Form input common fields
    public let field_label: String?
    public let field_placeholder: String?
    public let field_required: Bool?
    public let field_style: FormFieldBlockStyle?
    public let field_options: [InputOption]?
    // Form input specific config
    public let field_config: [String: AnyCodable]?

    // SPEC-089d §6.3: Visibility condition
    public let visibility_condition: VisibilityCondition?

    // SPEC-089d §6.4: Entrance animation
    public let entrance_animation: EntranceAnimation?

    // SPEC-089d §6.5: Press/tap state
    public let pressed_style: PressedStyle?

    // SPEC-089d §6.6: Dynamic bindings
    public let bindings: [String: String]?

    // SPEC-089d §6.7: Relative sizing
    public let element_width: String?
    public let element_height: String?

    enum CodingKeys: String, CodingKey {
        case id, type, text, style, level
        case image_url, alt, corner_radius, height
        case variant, action, action_value, bg_color, text_color, button_corner_radius
        case spacer_height, items, list_style
        case divider_color, divider_thickness, divider_margin_y
        case badge_text, badge_bg_color, badge_text_color, badge_corner_radius
        case icon_emoji, icon_size, icon_alignment
        case toggle_label, toggle_description, toggle_default
        case video_url, video_thumbnail_url, video_height, video_corner_radius
        case autoplay, loop, muted, controls
        case lottie_url, lottie_speed, lottie_width, lottie_height
        case play_on_scroll, play_on_tap
        case rive_url, artboard, state_machine, trigger_on_step_complete
        case icon_ref
        case block_style
        case vertical_align, horizontal_align, vertical_offset, horizontal_offset
        // SPEC-089d Phase A: new block fields
        case dot_count, active_index, active_color, inactive_color
        case dot_size, dot_spacing, active_dot_width, alignment
        case providers, button_style, button_height, spacing
        case show_divider, divider_text
        case timer_variant, duration_seconds
        case show_days, show_hours, show_minutes, show_seconds
        case labels, on_expire_action, expired_text, accent_color, font_size
        case max_stars, default_rating, star_size, filled_color, empty_color
        case allow_half, field_id, rating_label
        case markdown_content, rich_text_variant, base_style, link_color
        case progress_variant, progress_value, total_segments, filled_segments
        case bar_height, bar_color, track_color, show_label, segment_gap
        case timeline_items, line_color, completed_color, current_color
        case upcoming_color, show_line, compact, title_style, subtitle_style
        case loading_variant, loading_items, progress_color, check_color
        case total_duration_ms, auto_advance, show_percentage
        // SPEC-089d Phase F: new block fields
        case gauge_value, max_value, sublabel, stroke_width
        case label_color, label_font_size, animate, animation_duration_ms
        case columns, default_date_value, min_date, max_date
        case highlight_color, haptic_on_scroll
        case children, z_index, gap, wrap, justify, align_items
        case view_key, custom_config, placeholder_image_url, placeholder_text
        case particle_type, density, speed, secondary_color, size_range, fullscreen
        case min_value, max_value_picker, step_value, default_picker_value
        case unit, unit_position, visible_items
        case pulse_color, pulse_ring_count, pulse_speed, border_width, border_color
        case pricing_plans, pricing_layout
        // SPEC-089d Phase 3: form input + advanced styling fields
        case field_label, field_placeholder, field_required, field_style, field_options, field_config
        case visibility_condition, entrance_animation, pressed_style, bindings
        case element_width, element_height
    }
}

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

    var body: some View {
        let visibleBlocks = blocks.filter { block in
            evaluateVisibilityCondition(
                block.visibility_condition,
                responses: responses,
                hookData: hookData
            )
        }
        // Entrance animation cap: max 10 animated blocks per step
        // Pre-compute which block IDs should be animated (first 10 with animations)
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

        VStack(alignment: .leading, spacing: 12) {
            ForEach(visibleBlocks) { block in
                let shouldAnimate = animatedBlockIds.contains(block.id)
                let resolvedBlock = resolveBlockBindings(block, hookData: hookData, responses: responses)
                renderBlock(resolvedBlock, animate: shouldAnimate)
                    .applyRelativeSizing(width: resolvedBlock.element_width, height: resolvedBlock.element_height)
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
                horizontalOffset: block.horizontal_offset
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

    @ViewBuilder
    private func renderBlockContent(_ block: ContentBlock) -> some View {
        switch block.type {
        case .heading:
            headingBlock(block)
        case .text:
            textBlock(block)
        case .image:
            imageBlock(block)
        case .button:
            buttonBlock(block)
        case .spacer:
            Spacer().frame(height: CGFloat(block.spacer_height ?? 16))
        case .list:
            listBlock(block)
        case .divider:
            dividerBlock(block)
        case .badge:
            badgeBlock(block)
        case .icon:
            iconBlock(block)
        case .toggle:
            toggleBlock(block)
        case .video:
            videoBlock(block)
        // SPEC-085: Rich media block types
        case .lottie:
            lottieBlock(block)
        case .rive:
            riveBlock(block)
        // SPEC-089d Phase A: New onboarding block renderers
        case .page_indicator:
            pageIndicatorBlock(block)
        case .wheel_picker:
            WheelPickerBlockView(block: block)
        case .pulsing_avatar:
            PulsingAvatarBlockView(block: block)
        case .social_login:
            socialLoginBlock(block)
        case .timeline:
            timelineBlock(block)
        case .animated_loading:
            AnimatedLoadingBlockView(block: block, onAction: onAction)
        case .star_background:
            StarBackgroundBlockView(block: block)
        case .countdown_timer:
            CountdownTimerBlockView(block: block, onAction: onAction)
        case .rating:
            RatingBlockView(block: block, onAction: onAction)
        case .rich_text:
            richTextBlock(block)
        case .progress_bar:
            progressBarBlock(block)
        // SPEC-089d Phase F: Container & advanced block types
        case .stack:
            stackBlock(block)
        case .custom_view:
            customViewBlock(block)
        case .date_wheel_picker:
            DateWheelPickerBlockView(block: block)
        case .circular_gauge:
            CircularGaugeBlockView(block: block)
        case .row:
            rowBlock(block)
        // SPEC-089d Nurrai
        case .pricing_card:
            PricingCardBlockView(block: block, onAction: onAction)
        // SPEC-089d Phase 3: Form input block renderers (22 types)
        case .input_text:
            FormInputTextBlock(block: block, inputValues: $inputValues, keyboardType: .default)
        case .input_textarea:
            FormInputTextAreaBlock(block: block, inputValues: $inputValues)
        case .input_number:
            FormInputTextBlock(block: block, inputValues: $inputValues, keyboardType: .numberPad)
        case .input_email:
            FormInputTextBlock(block: block, inputValues: $inputValues, keyboardType: .emailAddress)
        case .input_phone:
            FormInputTextBlock(block: block, inputValues: $inputValues, keyboardType: .phonePad)
        case .input_url:
            FormInputTextBlock(block: block, inputValues: $inputValues, keyboardType: .URL)
        case .input_password:
            FormInputPasswordBlock(block: block, inputValues: $inputValues)
        case .input_date:
            FormInputDateBlock(block: block, inputValues: $inputValues, components: .date)
        case .input_time:
            FormInputDateBlock(block: block, inputValues: $inputValues, components: .hourAndMinute)
        case .input_datetime:
            FormInputDateBlock(block: block, inputValues: $inputValues, components: [.date, .hourAndMinute])
        case .input_select:
            FormInputSelectBlock(block: block, inputValues: $inputValues)
        case .input_slider:
            FormInputSliderBlock(block: block, inputValues: $inputValues)
        case .input_toggle:
            FormInputToggleBlock(block: block, inputValues: $inputValues)
        case .input_stepper:
            FormInputStepperBlock(block: block, inputValues: $inputValues)
        case .input_segmented:
            FormInputSegmentedBlock(block: block, inputValues: $inputValues)
        case .input_rating:
            FormInputRatingBlock(block: block, inputValues: $inputValues)
        case .input_range_slider:
            FormInputRangeSliderBlock(block: block, inputValues: $inputValues)
        case .input_chips:
            FormInputChipsBlock(block: block, inputValues: $inputValues)
        case .input_location:
            FormInputLocationPlaceholderBlock(block: block, inputValues: $inputValues)
        case .input_image_picker:
            FormInputImagePickerPlaceholderBlock(block: block)
        case .input_color:
            FormInputColorBlock(block: block, inputValues: $inputValues)
        case .input_signature:
            FormInputSignatureBlock(block: block, inputValues: $inputValues)
        // Backward compatibility: unknown types render as invisible
        case .unknown:
            EmptyView()
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
        return Text(loc?("block.\(block.id).text", text) ?? text)
            .font(.system(size: fontSize, weight: .bold))
            .applyTextStyle(block.style)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Text

    private func textBlock(_ block: ContentBlock) -> some View {
        let text = block.text ?? ""
        return Text(loc?("block.\(block.id).text", text) ?? text)
            .font(.body)
            .applyTextStyle(block.style)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Image

    private func imageBlock(_ block: ContentBlock) -> some View {
        Group {
            if let urlString = block.image_url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxHeight: CGFloat(block.height ?? 200))
                            .clipShape(RoundedRectangle(cornerRadius: CGFloat(block.corner_radius ?? 0)))
                            .accessibilityLabel(block.alt ?? "Image")
                    case .failure:
                        imagePlaceholder
                    default:
                        ProgressView().frame(height: CGFloat(block.height ?? 200))
                    }
                }
            } else {
                imagePlaceholder
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

        return Button {
            onAction(block.action ?? "next", block.action_value)
        } label: {
            Text(labelText)
                .font(.body.weight(.semibold))
                .foregroundColor(btnVariant == "outline" ? bgColor : (btnVariant == "text" ? bgColor : txtColor))
                .applyTextStyle(block.style)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(btnVariant == "outline" || btnVariant == "text" ? Color.clear : bgColor)
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .overlay(
                    btnVariant == "outline"
                        ? RoundedRectangle(cornerRadius: radius).stroke(bgColor, lineWidth: 1.5)
                        : nil
                )
        }
        .applyPressedStyle(block.pressed_style)
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

    @ViewBuilder
    private func listMarker(style: String, index: Int) -> some View {
        switch style {
        case "numbered":
            Text("\(index + 1).")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
        case "check":
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundColor(.green)
        default:
            Circle()
                .fill(Color.primary.opacity(0.5))
                .frame(width: 6, height: 6)
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
                .tint(.accentColor)
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
                AsyncImage(url: url) { phase in
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
        // AC-012: Auto-bind active_index to current step index when not explicitly set or 0
        let activeIdx = (block.active_index ?? 0) == 0 ? currentStepIndex : (block.active_index ?? 0)
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
                Button {
                    onAction("social_login", provider.type)
                } label: {
                    HStack(spacing: 10) {
                        socialLoginIcon(provider.type)
                        Text(provider.label ?? socialLoginDefaultLabel(provider.type))
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: btnHeight)
                    .foregroundColor(socialLoginTextColor(provider.type, style: btnStyle))
                    .background(socialLoginBgColor(provider.type, style: btnStyle))
                    .clipShape(RoundedRectangle(cornerRadius: btnRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: btnRadius)
                            .stroke(socialLoginBorderColor(provider.type, style: btnStyle), lineWidth: btnStyle == "outlined" ? 1.5 : 0)
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

    @ViewBuilder
    private func socialLoginIcon(_ type: String) -> some View {
        switch type {
        case "apple":
            Image(systemName: "applelogo")
                .font(.body.weight(.medium))
        case "google":
            Text("G")
                .font(.system(size: 18, weight: .bold, design: .rounded))
        case "email":
            Image(systemName: "envelope.fill")
                .font(.body)
        case "facebook":
            Text("f")
                .font(.system(size: 20, weight: .bold, design: .rounded))
        case "github":
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.body)
        default:
            Image(systemName: "person.fill")
                .font(.body)
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
        case "google": return .white
        case "facebook": return Color(hex: "#1877F2")
        case "github": return Color(hex: "#24292E")
        default: return .accentColor
        }
    }

    private func socialLoginTextColor(_ type: String, style: String) -> Color {
        if style == "outlined" || style == "minimal" {
            return type == "apple" ? .primary : .primary
        }
        switch type {
        case "apple": return .white
        case "google": return Color(hex: "#3C4043")
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
                                .fill(timelineStatusColor(item.status, completed: completedCol, current: currentCol, upcoming: upcomingCol))
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
                        Text(item.title)
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

        return Group {
            if #available(iOS 15.0, *) {
                let attributed = parseMarkdownToAttributedString(content, linkColor: linkCol)
                Text(attributed)
                    .font(isLegal ? .caption : .body)
                    .foregroundColor(isLegal ? .secondary : .primary)
                    .multilineTextAlignment(isLegal ? .center : .leading)
                    .applyTextStyle(block.base_style)
                    .frame(maxWidth: .infinity, alignment: isLegal ? .center : .leading)
            } else {
                // Fallback: render as plain text, stripping markdown tokens
                Text(stripMarkdown(content))
                    .font(isLegal ? .caption : .body)
                    .foregroundColor(isLegal ? .secondary : .primary)
                    .multilineTextAlignment(isLegal ? .center : .leading)
                    .applyTextStyle(block.base_style)
                    .frame(maxWidth: .infinity, alignment: isLegal ? .center : .leading)
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
        let childBlocks = block.children ?? []
        let rowGap = CGFloat(block.gap ?? 8)
        let vAlign: VerticalAlignment = {
            switch block.align_items {
            case "top": return .top
            case "bottom": return .bottom
            default: return .center
            }
        }()

        HStack(alignment: vAlign, spacing: rowGap) {
            ForEach(childBlocks) { child in
                renderBlock(child)
            }
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
            AsyncImage(url: url) { phase in
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

// MARK: - Rating Block View (SPEC-089d AC-019)

/// Stateful star rating input rendered as an independent SwiftUI view.
struct RatingBlockView: View {
    let block: ContentBlock
    let onAction: (_ action: String, _ actionValue: String?) -> Void

    @State private var selectedRating: Double = 0

    var body: some View {
        let maxStars = block.max_stars ?? 5
        let starSz = CGFloat(block.star_size ?? 32)
        let filledCol = Color(hex: block.filled_color ?? "#FBBF24")
        let emptyCol = Color(hex: block.empty_color ?? "#D1D5DB")
        let halfEnabled = block.allow_half ?? false

        VStack(spacing: 8) {
            if let label = block.rating_label {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }

            HStack(spacing: 4) {
                ForEach(1...maxStars, id: \.self) { index in
                    starImage(for: Double(index), filled: filledCol, empty: emptyCol, halfEnabled: halfEnabled)
                        .font(.system(size: starSz))
                        .onTapGesture {
                            selectedRating = Double(index)
                        }
                        .gesture(
                            halfEnabled ?
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let halfThreshold = starSz / 2
                                    if value.location.x < halfThreshold {
                                        selectedRating = Double(index) - 0.5
                                    } else {
                                        selectedRating = Double(index)
                                    }
                                }
                            : nil
                        )
                        .accessibilityLabel("\(index) star\(index > 1 ? "s" : "")")
                }
            }
        }
        .onAppear {
            selectedRating = block.default_rating ?? 0
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int(selectedRating)) of \(maxStars) stars")
    }

    @ViewBuilder
    private func starImage(for value: Double, filled: Color, empty: Color, halfEnabled: Bool) -> some View {
        if selectedRating >= value {
            Image(systemName: "star.fill")
                .foregroundColor(filled)
        } else if halfEnabled && selectedRating >= value - 0.5 {
            Image(systemName: "star.leadinghalf.filled")
                .foregroundColor(filled)
        } else {
            Image(systemName: "star")
                .foregroundColor(empty)
        }
    }
}

// MARK: - Countdown Timer Block View (SPEC-089d AC-018)

/// Stateful countdown timer driven by `Timer.publish`.
struct CountdownTimerBlockView: View {
    let block: ContentBlock
    let onAction: (_ action: String, _ actionValue: String?) -> Void

    @State private var remainingSeconds: Int = 0
    @State private var expired: Bool = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if expired {
                expiredView
            } else {
                digitalTimerView
            }
        }
        .onAppear {
            remainingSeconds = block.duration_seconds ?? 60
        }
        .onReceive(timer) { _ in
            guard !expired else { return }
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            }
            if remainingSeconds <= 0 {
                expired = true
                handleExpiry()
            }
        }
    }

    // Digital variant (default): HStack of time unit columns
    private var digitalTimerView: some View {
        let timeColor = Color(hex: block.text_color ?? "#000000")
        let accentCol = Color(hex: block.accent_color ?? "#6366F1")
        let fontSize = CGFloat(block.font_size ?? 28)
        let lbls = block.labels

        let days = remainingSeconds / 86400
        let hours = (remainingSeconds % 86400) / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60

        return HStack(spacing: 16) {
            if block.show_days != false && days > 0 {
                timerUnit(value: days, label: lbls?.days ?? "Days", fontSize: fontSize, color: timeColor, accent: accentCol)
            }
            if block.show_hours != false {
                timerUnit(value: hours, label: lbls?.hours ?? "Hours", fontSize: fontSize, color: timeColor, accent: accentCol)
            }
            if block.show_minutes != false {
                timerUnit(value: minutes, label: lbls?.minutes ?? "Min", fontSize: fontSize, color: timeColor, accent: accentCol)
            }
            if block.show_seconds != false {
                timerUnit(value: seconds, label: lbls?.seconds ?? "Sec", fontSize: fontSize, color: timeColor, accent: accentCol)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func timerUnit(value: Int, label: String, fontSize: CGFloat, color: Color, accent: Color) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d", value))
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(accent)
        }
    }

    @ViewBuilder
    private var expiredView: some View {
        switch block.on_expire_action {
        case "hide":
            EmptyView()
        case "show_expired_text":
            Text(block.expired_text ?? "Time's up!")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
        default:
            // auto_advance or no action specified — show brief expired text
            Text(block.expired_text ?? "Time's up!")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func handleExpiry() {
        if block.on_expire_action == "auto_advance" {
            onAction("next", nil)
        }
    }
}

// MARK: - Animated Loading Block View (SPEC-089d AC-017)

/// Stateful animated loading / checklist block driven by sequential timers.
struct AnimatedLoadingBlockView: View {
    let block: ContentBlock
    let onAction: (_ action: String, _ actionValue: String?) -> Void

    @State private var completedCount: Int = 0
    @State private var overallProgress: CGFloat = 0
    @State private var timerCancellable: Timer? = nil

    var body: some View {
        let variant = block.loading_variant ?? "checklist"
        let itemList = block.loading_items ?? []
        let progressCol = Color(hex: block.progress_color ?? "#6366F1")
        let checkCol = Color(hex: block.check_color ?? "#22C55E")
        let totalMs = block.total_duration_ms ?? itemList.reduce(0) { $0 + ($1.duration_ms ?? 1000) }

        VStack(spacing: 16) {
            if block.show_percentage == true {
                Text("\(Int(overallProgress * 100))%")
                    .font(.title2.weight(.bold))
                    .foregroundColor(progressCol)
            }

            switch variant {
            case "circular":
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                        .frame(width: 80, height: 80)
                    Circle()
                        .trim(from: 0, to: overallProgress)
                        .stroke(progressCol, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: overallProgress)
                }

            case "linear":
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(progressCol)
                            .frame(width: geometry.size.width * overallProgress, height: 8)
                            .animation(.linear(duration: 0.3), value: overallProgress)
                    }
                }
                .frame(height: 8)

            default: // checklist
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(itemList.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 12) {
                            ZStack {
                                if index < completedCount {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(checkCol)
                                        .transition(.scale.combined(with: .opacity))
                                } else if index == completedCount {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .transition(.opacity)
                                } else {
                                    Circle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                                        .frame(width: 22, height: 22)
                                }
                            }
                            .frame(width: 28, height: 28)
                            .animation(.easeInOut(duration: 0.3), value: completedCount)

                            Text(item.label)
                                .font(.subheadline)
                                .foregroundColor(index <= completedCount ? .primary : .secondary)
                        }
                    }
                }
            }
        }
        .onAppear {
            startSequentialTimer(items: itemList, totalMs: totalMs)
        }
        .onDisappear {
            timerCancellable?.invalidate()
        }
    }

    private func startSequentialTimer(items: [LoadingItemConfig], totalMs: Int) {
        guard !items.isEmpty else {
            // No items: just run a single progress over totalMs
            let duration = Double(totalMs) / 1000.0
            let tickInterval = 0.05
            var elapsed = 0.0
            timerCancellable = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { timer in
                elapsed += tickInterval
                let progress = min(elapsed / duration, 1.0)
                DispatchQueue.main.async {
                    overallProgress = CGFloat(progress)
                }
                if elapsed >= duration {
                    timer.invalidate()
                    if block.auto_advance == true {
                        DispatchQueue.main.async {
                            onAction("next", nil)
                        }
                    }
                }
            }
            return
        }

        // Sequential item completion
        var cumulativeDelay = 0.0
        let totalDuration = Double(items.reduce(0) { $0 + ($1.duration_ms ?? 1000) })

        for (index, item) in items.enumerated() {
            let itemDuration = Double(item.duration_ms ?? 1000) / 1000.0
            cumulativeDelay += itemDuration

            let capturedDelay = cumulativeDelay
            let capturedIndex = index

            DispatchQueue.main.asyncAfter(deadline: .now() + capturedDelay) {
                withAnimation {
                    completedCount = capturedIndex + 1
                    overallProgress = CGFloat(capturedDelay / (totalDuration / 1000.0))
                }

                // If last item, handle auto_advance
                if capturedIndex == items.count - 1 {
                    overallProgress = 1.0
                    if block.auto_advance == true {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            onAction("next", nil)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Circular Gauge Block View (SPEC-089d AC-022)

/// Renders a circular arc gauge with center label. Supports animated fill.
struct CircularGaugeBlockView: View {
    let block: ContentBlock

    @State private var animatedProgress: CGFloat = 0

    var body: some View {
        let value = CGFloat(block.gauge_value ?? block.progress_value ?? 0)
        let maxVal = CGFloat(block.max_value ?? 100)
        let targetProgress = maxVal > 0 ? min(value / maxVal, 1.0) : 0
        let size = CGFloat(block.height ?? 120)
        let strokeW = CGFloat(block.stroke_width ?? 10)
        let fillCol = Color(hex: block.bar_color ?? block.active_color ?? "#6366F1")
        let trackCol = Color(hex: block.track_color ?? "#E5E7EB")
        let labelCol = Color(hex: block.label_color ?? block.text_color ?? "#000000")
        let labelFontSz = CGFloat(block.label_font_size ?? block.font_size ?? 20)
        let shouldAnimate = block.animate ?? true
        let animDuration = Double(block.animation_duration_ms ?? 800) / 1000.0
        let showPct = block.show_percentage ?? false

        ZStack {
            // Track
            Circle()
                .stroke(trackCol, lineWidth: strokeW)
            // Filled arc
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(fillCol, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Center label
            VStack(spacing: 2) {
                Text(showPct ? "\(Int(animatedProgress * 100))%" : (block.text ?? "\(Int(value))"))
                    .font(.system(size: labelFontSz, weight: .bold))
                    .foregroundColor(labelCol)
                if let sub = block.sublabel {
                    Text(sub)
                        .font(.caption)
                        .foregroundColor(labelCol.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity)
        .onAppear {
            if shouldAnimate {
                withAnimation(.easeInOut(duration: animDuration)) {
                    animatedProgress = targetProgress
                }
            } else {
                animatedProgress = targetProgress
            }
        }
    }
}

// MARK: - Date Wheel Picker Block View (SPEC-089d AC-023)

/// Multi-column date picker using native iOS wheel picker style.
struct DateWheelPickerBlockView: View {
    let block: ContentBlock

    @State private var selectedDate = Date()

    var body: some View {
        let highlightCol = Color(hex: block.highlight_color ?? "#6366F1")

        VStack(spacing: 8) {
            DatePicker(
                "",
                selection: $selectedDate,
                displayedComponents: [.date]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .accentColor(highlightCol)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Wheel Picker Block View (SPEC-089d AC-013)

/// Numeric wheel picker for single-value selection.
struct WheelPickerBlockView: View {
    let block: ContentBlock

    @State private var selectedIndex: Int = 0

    var body: some View {
        let minVal = block.min_value ?? 0
        let maxVal = block.max_value_picker ?? 100
        let step = block.step_value ?? 1
        let defaultVal = block.default_picker_value ?? minVal
        let unitStr = block.unit ?? ""
        let unitPos = block.unit_position ?? "after"
        let highlightCol = Color(hex: block.highlight_color ?? block.active_color ?? "#6366F1")

        // Generate values
        let values: [Double] = {
            var vals: [Double] = []
            var current = minVal
            while current <= maxVal {
                vals.append(current)
                current += step
            }
            return vals.isEmpty ? [0] : vals
        }()

        let initialIndex = values.firstIndex(where: { $0 >= defaultVal }) ?? 0

        VStack(spacing: 8) {
            if let label = block.rating_label ?? block.text {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Picker("", selection: $selectedIndex) {
                ForEach(0..<values.count, id: \.self) { idx in
                    let val = values[idx]
                    let formatted = val == val.rounded() ? String(Int(val)) : String(format: "%.1f", val)
                    let display = unitPos == "before" ? "\(unitStr)\(formatted)" : "\(formatted)\(unitStr)"
                    Text(display)
                        .tag(idx)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .accentColor(highlightCol)
        }
        .onAppear {
            selectedIndex = initialIndex
        }
    }
}

// MARK: - Pulsing Avatar Block View (SPEC-089d AC-014)

/// Avatar image with animated pulsing ring effects.
struct PulsingAvatarBlockView: View {
    let block: ContentBlock

    @State private var isPulsing = false

    var body: some View {
        let avatarSize = CGFloat(block.icon_size ?? block.height ?? 80)
        let pulseCol = Color(hex: block.pulse_color ?? "#6366F1")
        let ringCount = block.pulse_ring_count ?? 3
        let pulseDuration = block.pulse_speed ?? 1.5
        let borderW = CGFloat(block.border_width ?? 0)
        let borderCol = Color(hex: block.border_color ?? "#FFFFFF")

        let align: Alignment = {
            switch block.alignment {
            case "left": return .leading
            case "right": return .trailing
            default: return .center
            }
        }()

        ZStack {
            // Pulse rings
            ForEach(0..<ringCount, id: \.self) { ringIndex in
                Circle()
                    .stroke(pulseCol.opacity(0.3), lineWidth: 2)
                    .frame(width: avatarSize + CGFloat(ringIndex + 1) * 20,
                           height: avatarSize + CGFloat(ringIndex + 1) * 20)
                    .scaleEffect(isPulsing ? 1.2 : 1.0)
                    .opacity(isPulsing ? 0 : 0.6)
                    .animation(
                        Animation.easeInOut(duration: pulseDuration)
                            .repeatForever(autoreverses: false)
                            .delay(pulseDuration / Double(ringCount) * Double(ringIndex)),
                        value: isPulsing
                    )
            }

            // Avatar image
            Group {
                if let urlString = block.image_url, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Circle().fill(Color.gray.opacity(0.2))
                        }
                    }
                } else {
                    Circle().fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: avatarSize * 0.4))
                                .foregroundColor(.gray)
                        )
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
            .overlay(
                borderW > 0
                    ? Circle().stroke(borderCol, lineWidth: borderW)
                    : nil
            )

            // Badge
            if let badgeText = block.badge_text, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Color(hex: block.badge_text_color ?? "#FFFFFF"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: block.badge_bg_color ?? "#EF4444"))
                    .clipShape(Capsule())
                    .offset(x: avatarSize * 0.35, y: -avatarSize * 0.35)
            }
        }
        .frame(maxWidth: .infinity, alignment: align)
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Star Background Block View (SPEC-089d AC-027)

/// Animated star/particle background using Canvas + TimelineView.
struct StarBackgroundBlockView: View {
    let block: ContentBlock

    @State private var particles: [StarParticle] = []
    @State private var isActive = true

    var body: some View {
        let color = Color(hex: block.active_color ?? block.text_color ?? "#FFFFFF")
        let opacity = block.block_style?.opacity ?? 0.8
        let particleCount: Int = {
            switch block.density {
            case "sparse": return 20
            case "dense": return 100
            default: return 50
            }
        }()
        let speedFactor: CGFloat = {
            switch block.speed {
            case "slow": return 0.3
            case "fast": return 1.5
            default: return 0.8
            }
        }()
        let minSize = CGFloat(block.size_range?.first ?? 1)
        let maxSize = CGFloat(block.size_range?.last ?? 3)
        let isFullscreen = block.fullscreen ?? false
        let height = CGFloat(block.height ?? 200)

        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            Canvas { context, size in
                for particle in particles {
                    let rect = CGRect(
                        x: particle.x,
                        y: particle.y,
                        width: particle.size,
                        height: particle.size
                    )
                    context.opacity = particle.opacity * opacity
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(color)
                    )
                }
            }
            .onChange(of: timeline.date) { _ in
                updateParticles(speedFactor: speedFactor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: isFullscreen ? .infinity : height)
        .clipped()
        .onAppear {
            initializeParticles(count: particleCount, minSize: minSize, maxSize: maxSize)
        }
        .onDisappear {
            isActive = false
        }
    }

    private func initializeParticles(count: Int, minSize: CGFloat, maxSize: CGFloat) {
        particles = (0..<count).map { _ in
            StarParticle(
                x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                y: CGFloat.random(in: 0...(UIScreen.main.bounds.height)),
                size: CGFloat.random(in: minSize...maxSize),
                opacity: Double.random(in: 0.2...1.0),
                speed: CGFloat.random(in: 0.2...1.0)
            )
        }
    }

    private func updateParticles(speedFactor: CGFloat) {
        for i in particles.indices {
            particles[i].y += particles[i].speed * speedFactor
            particles[i].opacity += Double.random(in: -0.02...0.02)
            particles[i].opacity = max(0.1, min(1.0, particles[i].opacity))

            // Wrap around when particle falls off screen
            if particles[i].y > UIScreen.main.bounds.height {
                particles[i].y = -particles[i].size
                particles[i].x = CGFloat.random(in: 0...UIScreen.main.bounds.width)
            }
        }
    }
}

// MARK: - Pricing Card Block View (SPEC-089d Nurrai)

/// Renders pricing plan cards in stack or side-by-side layout.
struct PricingCardBlockView: View {
    let block: ContentBlock
    let onAction: (_ action: String, _ actionValue: String?) -> Void

    @State private var selectedPlanId: String? = nil

    var body: some View {
        let plans = block.pricing_plans ?? []
        let isSideBySide = block.pricing_layout == "side_by_side"
        let accentCol = Color(hex: block.active_color ?? block.bg_color ?? "#6366F1")

        Group {
            if isSideBySide {
                HStack(spacing: 12) {
                    ForEach(plans) { plan in
                        planCard(plan, accent: accentCol)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(plans) { plan in
                        planCard(plan, accent: accentCol)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func planCard(_ plan: PricingPlanConfig, accent: Color) -> some View {
        let isHighlighted = plan.is_highlighted ?? false
        let isSelected = selectedPlanId == plan.id

        return Button {
            selectedPlanId = plan.id
            onAction("select_plan", plan.id)
        } label: {
            VStack(spacing: 6) {
                // Badge
                if let badge = plan.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(accent)
                        .clipShape(Capsule())
                }

                Text(plan.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)

                Text(plan.price)
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)

                Text(plan.period)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(isSelected ? accent.opacity(0.05) : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? accent : (isHighlighted ? accent : Color.gray.opacity(0.3)),
                        lineWidth: isSelected || isHighlighted ? 2 : 1
                    )
            )
            .shadow(color: isHighlighted ? accent.opacity(0.15) : .clear, radius: 4, y: 2)
        }
    }
}

// MARK: - Form Input Block Views (SPEC-089d Phase 3: AC-040 through AC-053)

/// Helper view to render a form field label above the input control.
struct FormFieldLabelView: View {
    let block: ContentBlock

    var body: some View {
        if let label = block.field_label ?? block.rating_label ?? block.text, !label.isEmpty {
            let required = block.field_required ?? false
            HStack(spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Color(hex: block.field_style?.label_color ?? "#374151"))
                if required {
                    Text("*")
                        .foregroundColor(.red)
                }
            }
        }
    }
}

/// Helper function for calling FormFieldLabelView from within views.
@ViewBuilder
private func formFieldLabel(_ block: ContentBlock) -> some View {
    FormFieldLabelView(block: block)
}

/// Generic text-based input (text, number, email, phone, url).
struct FormInputTextBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]
    let keyboardType: UIKeyboardType

    @State private var text: String = ""

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let placeholder = block.field_placeholder ?? block.text ?? ""
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(hex: block.field_style?.background_color ?? "#FFFFFF"))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: CGFloat(block.field_style?.border_width ?? 1))
                )
                .onChange(of: text) { newValue in
                    inputValues[fieldId] = newValue
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Multi-line text area input.
struct FormInputTextAreaBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var text: String = ""

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)
        let minLines = (block.field_config?["min_lines"]?.value as? Int) ?? 3

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            TextEditor(text: $text)
                .frame(minHeight: CGFloat(minLines * 22))
                .padding(4)
                .background(Color(hex: block.field_style?.background_color ?? "#FFFFFF"))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: CGFloat(block.field_style?.border_width ?? 1))
                )
                .onChange(of: text) { newValue in
                    inputValues[fieldId] = newValue
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Password input with show/hide toggle.
struct FormInputPasswordBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var text: String = ""
    @State private var showPassword: Bool = false

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let placeholder = block.field_placeholder ?? "Password"
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            HStack {
                if showPassword {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                } else {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                }

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(hex: block.field_style?.background_color ?? "#FFFFFF"))
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: CGFloat(block.field_style?.border_width ?? 1))
            )
            .onChange(of: text) { newValue in
                inputValues[fieldId] = newValue
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Date, Time, or DateTime picker input.
struct FormInputDateBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]
    let components: DatePickerComponents

    @State private var selectedDate = Date()

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let accentColor = Color(hex: block.field_style?.fill_color ?? block.active_color ?? "#6366F1")

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            DatePicker(
                "",
                selection: $selectedDate,
                displayedComponents: components
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .accentColor(accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: selectedDate) { newValue in
                let formatter = ISO8601DateFormatter()
                inputValues[fieldId] = formatter.string(from: newValue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Dropdown select input.
struct FormInputSelectBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var selectedValue: String = ""

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let options = block.field_options ?? []

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            Picker("", selection: $selectedValue) {
                Text(block.field_placeholder ?? "Select...").tag("")
                ForEach(options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(hex: block.field_style?.background_color ?? "#FFFFFF"))
            .cornerRadius(CGFloat(block.field_style?.corner_radius ?? 8))
            .overlay(
                RoundedRectangle(cornerRadius: CGFloat(block.field_style?.corner_radius ?? 8))
                    .stroke(Color(hex: block.field_style?.border_color ?? "#D1D5DB"), lineWidth: 1)
            )
            .onChange(of: selectedValue) { newValue in
                inputValues[fieldId] = newValue
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Slider input for single numeric value.
struct FormInputSliderBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var value: Double = 50

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let minVal = block.min_value ?? 0
        let maxVal = block.max_value_picker ?? 100
        let stepVal = block.step_value ?? 1
        let showValue = (block.field_config?["show_value"]?.value as? Bool) ?? true
        let unitStr = block.unit ?? ""
        let trackCol = Color(hex: block.field_style?.track_color ?? block.track_color ?? "#E5E7EB")
        let fillCol = Color(hex: block.field_style?.fill_color ?? block.active_color ?? "#6366F1")

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                formFieldLabel(block)
                Spacer()
                if showValue {
                    let formatted = value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
                    Text("\(formatted)\(unitStr)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(fillCol)
                }
            }

            Slider(value: $value, in: minVal...maxVal, step: stepVal)
                .tint(fillCol)
                .onChange(of: value) { newValue in
                    inputValues[fieldId] = newValue
                }
        }
        .onAppear {
            value = block.default_picker_value ?? minVal
            inputValues[fieldId] = value
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Toggle (switch) input.
struct FormInputToggleBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var isOn: Bool = false

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let onColor = Color(hex: block.field_style?.toggle_on_color ?? "#6366F1")
        let label = block.field_label ?? block.toggle_label ?? ""

        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(onColor)
                .onChange(of: isOn) { newValue in
                    inputValues[fieldId] = newValue
                }
        }
        .onAppear {
            isOn = block.toggle_default ?? false
            inputValues[fieldId] = isOn
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Stepper input for incrementing/decrementing numeric value.
struct FormInputStepperBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var value: Int = 0

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let minVal = Int(block.min_value ?? 0)
        let maxVal = Int(block.max_value_picker ?? 100)
        let stepVal = Int(block.step_value ?? 1)
        let unitStr = block.unit ?? ""

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            Stepper(value: $value, in: minVal...maxVal, step: stepVal) {
                Text("\(value)\(unitStr)")
                    .font(.body.weight(.medium))
            }
            .onChange(of: value) { newValue in
                inputValues[fieldId] = newValue
            }
        }
        .onAppear {
            value = Int(block.default_picker_value ?? Double(minVal))
            inputValues[fieldId] = value
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Segmented picker input.
struct FormInputSegmentedBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var selectedValue: String = ""

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let options = block.field_options ?? []

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            Picker("", selection: $selectedValue) {
                ForEach(options) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedValue) { newValue in
                inputValues[fieldId] = newValue
            }
        }
        .onAppear {
            if selectedValue.isEmpty, let first = options.first {
                selectedValue = first.value
                inputValues[fieldId] = first.value
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Star rating input (form variant — reuses rating block logic).
struct FormInputRatingBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var selectedRating: Double = 0

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let maxStars = block.max_stars ?? 5
        let starSz = CGFloat(block.star_size ?? 32)
        let filledCol = Color(hex: block.filled_color ?? block.field_style?.fill_color ?? "#FBBF24")
        let emptyCol = Color(hex: block.empty_color ?? "#D1D5DB")

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            HStack(spacing: 4) {
                ForEach(1...maxStars, id: \.self) { index in
                    Image(systemName: selectedRating >= Double(index) ? "star.fill" : "star")
                        .font(.system(size: starSz))
                        .foregroundColor(selectedRating >= Double(index) ? filledCol : emptyCol)
                        .onTapGesture {
                            selectedRating = Double(index)
                            inputValues[fieldId] = selectedRating
                        }
                }
            }
        }
        .onAppear {
            selectedRating = block.default_rating ?? 0
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Range slider (dual-thumb) input.
struct FormInputRangeSliderBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var lowValue: Double = 0
    @State private var highValue: Double = 100

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let minVal = block.min_value ?? 0
        let maxVal = block.max_value_picker ?? 100
        let unitStr = block.unit ?? ""
        let fillCol = Color(hex: block.field_style?.fill_color ?? block.active_color ?? "#6366F1")

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                formFieldLabel(block)
                Spacer()
                Text("\(Int(lowValue))\(unitStr) - \(Int(highValue))\(unitStr)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(fillCol)
            }

            VStack(spacing: 4) {
                HStack {
                    Text("Min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Slider(value: $lowValue, in: minVal...maxVal)
                        .tint(fillCol)
                }
                HStack {
                    Text("Max")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Slider(value: $highValue, in: minVal...maxVal)
                        .tint(fillCol)
                }
            }
            .onChange(of: lowValue) { _ in
                if lowValue > highValue { highValue = lowValue }
                inputValues[fieldId] = ["min": lowValue, "max": highValue]
            }
            .onChange(of: highValue) { _ in
                if highValue < lowValue { lowValue = highValue }
                inputValues[fieldId] = ["min": lowValue, "max": highValue]
            }
        }
        .onAppear {
            lowValue = block.min_value ?? 0
            highValue = block.max_value_picker ?? 100
            inputValues[fieldId] = ["min": lowValue, "max": highValue]
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Chips/tag input — multi-select toggleable chips.
struct FormInputChipsBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var selectedValues: Set<String> = []

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let options = block.field_options ?? []
        let fillCol = Color(hex: block.field_style?.fill_color ?? block.active_color ?? "#6366F1")
        let maxSelections = (block.field_config?["max_selections"]?.value as? Int)

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            // FlowLayout approximation using wrapping HStack
            FlowLayoutView(spacing: 8) {
                ForEach(options) { option in
                    let isSelected = selectedValues.contains(option.value)
                    Button {
                        if isSelected {
                            selectedValues.remove(option.value)
                        } else {
                            if let max = maxSelections, selectedValues.count >= max {
                                return // At max selections
                            }
                            selectedValues.insert(option.value)
                        }
                        inputValues[fieldId] = Array(selectedValues)
                    } label: {
                        Text(option.label)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? fillCol : Color.gray.opacity(0.1))
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(isSelected ? fillCol : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Color picker — grid of preset color swatches.
struct FormInputColorBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var selectedColor: String = ""

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let presetColors: [String] = {
            if let colors = block.field_config?["preset_colors"]?.value as? [String] {
                return colors
            }
            return ["#EF4444", "#F97316", "#EAB308", "#22C55E", "#3B82F6", "#6366F1", "#A855F7", "#EC4899", "#000000", "#6B7280"]
        }()

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(presetColors, id: \.self) { color in
                    Circle()
                        .fill(Color(hex: color))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                                .padding(2)
                        )
                        .onTapGesture {
                            selectedColor = color
                            inputValues[fieldId] = color
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Placeholder for complex inputs (location, image_picker, signature) — renders icon + label.
struct FormInputPlaceholderBlock: View {
    let block: ContentBlock
    let iconName: String
    let label: String

    var body: some View {
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(16)
            .background(Color(hex: block.field_style?.background_color ?? "#F9FAFB"))
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - AC-046: Location Input Placeholder (interactive text field)

/// Interactive text field placeholder for location input.
/// Opens keyboard for typing; actual location autocomplete in future SDK update.
struct FormInputLocationPlaceholderBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var text: String = ""

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundColor(.secondary)
                TextField(block.field_placeholder ?? "Search location...", text: $text)
                    .font(.subheadline)
                    .onChange(of: text) { newValue in
                        inputValues[fieldId] = newValue
                    }
            }
            .padding(12)
            .background(Color(hex: block.field_style?.background_color ?? "#F9FAFB"))
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - AC-048: Image Picker Placeholder (interactive button with alert)

/// Interactive placeholder for image picker. Shows an alert on tap.
struct FormInputImagePickerPlaceholderBlock: View {
    let block: ContentBlock

    @State private var showAlert = false

    var body: some View {
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            Button {
                showAlert = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "photo.fill")
                        .foregroundColor(.secondary)
                    Text("Tap to pick image")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(16)
                .background(Color(hex: block.field_style?.background_color ?? "#F9FAFB"))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
                )
            }
            .buttonStyle(.plain)
            .alert("Photo Picker", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Photo picker coming in next SDK update.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - AC-051: Signature Input (interactive Canvas with touch drawing)

/// Interactive signature pad with basic touch/drag drawing.
struct FormInputSignatureBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var lines: [[CGPoint]] = []
    @State private var currentLine: [CGPoint] = []

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    for line in lines + [currentLine] {
                        guard line.count > 1 else { continue }
                        var path = Path()
                        path.move(to: line[0])
                        for point in line.dropFirst() {
                            path.addLine(to: point)
                        }
                        context.stroke(path, with: .color(.primary), lineWidth: 2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(Color(hex: block.field_style?.background_color ?? "#F9FAFB"))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            currentLine.append(value.location)
                        }
                        .onEnded { _ in
                            lines.append(currentLine)
                            currentLine = []
                            inputValues[fieldId] = "signed"
                        }
                )

                // Clear button
                if !lines.isEmpty {
                    Button {
                        lines = []
                        currentLine = []
                        inputValues.removeValue(forKey: fieldId)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .padding(8)
                    }
                }
            }

            if lines.isEmpty {
                Text("Draw your signature above")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Flow Layout (SPEC-089d Phase 3 — for chips block)

/// Simple flow layout approximation using LazyVGrid with adaptive columns.
/// Wraps children to next line when they exceed available width.
struct FlowLayoutView<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        // Use adaptive grid items as a flow-layout approximation
        let columns = [GridItem(.adaptive(minimum: 60, maximum: .infinity), spacing: spacing)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            content()
        }
    }
}
