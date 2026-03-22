import SwiftUI
import MapKit
import PhotosUI

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
func resolveDotPath(
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
func valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
    if a == nil && b == nil { return true }
    guard let a = a, let b = b else { return false }
    return "\(a)" == "\(b)"
}

/// Compares two values numerically.
func compareNumeric(_ a: Any?, _ b: Any?) -> ComparisonResult {
    let numA = toDouble(a)
    let numB = toDouble(b)
    guard let na = numA, let nb = numB else { return .orderedSame }
    if na < nb { return .orderedAscending }
    if na > nb { return .orderedDescending }
    return .orderedSame
}

func toDouble(_ value: Any?) -> Double? {
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
