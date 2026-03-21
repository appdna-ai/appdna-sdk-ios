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
    }
}

// MARK: - Content Block Renderer

struct ContentBlockRendererView: View {
    let blocks: [ContentBlock]
    let onAction: (_ action: String, _ actionValue: String?) -> Void
    @Binding var toggleValues: [String: Bool]
    var loc: ((String, String) -> String)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                renderBlock(block)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: ContentBlock) -> some View {
        renderBlockContent(block)
            .applyBlockStyle(block.block_style)
            .applyBlockPosition(
                verticalAlign: block.vertical_align,
                horizontalAlign: block.horizontal_align,
                verticalOffset: block.vertical_offset,
                horizontalOffset: block.horizontal_offset
            )
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
        // SPEC-089d Phase A: New onboarding block stubs
        case .page_indicator:
            stubBlockPlaceholder("page_indicator")
        case .wheel_picker:
            stubBlockPlaceholder("wheel_picker")
        case .pulsing_avatar:
            stubBlockPlaceholder("pulsing_avatar")
        case .social_login:
            stubBlockPlaceholder("social_login")
        case .timeline:
            stubBlockPlaceholder("timeline")
        case .animated_loading:
            stubBlockPlaceholder("animated_loading")
        case .star_background:
            stubBlockPlaceholder("star_background")
        case .countdown_timer:
            stubBlockPlaceholder("countdown_timer")
        case .rating:
            stubBlockPlaceholder("rating")
        case .rich_text:
            stubBlockPlaceholder("rich_text")
        case .progress_bar:
            stubBlockPlaceholder("progress_bar")
        // SPEC-089d Phase F: Container & advanced block stubs
        case .stack:
            stubBlockPlaceholder("stack")
        case .custom_view:
            stubBlockPlaceholder("custom_view")
        case .date_wheel_picker:
            stubBlockPlaceholder("date_wheel_picker")
        case .circular_gauge:
            stubBlockPlaceholder("circular_gauge")
        case .row:
            stubBlockPlaceholder("row")
        // SPEC-089d Nurrai
        case .pricing_card:
            stubBlockPlaceholder("pricing_card")
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

    // MARK: - Button

    private func buttonBlock(_ block: ContentBlock) -> some View {
        Button {
            onAction(block.action ?? "next", block.action_value)
        } label: {
            Text(loc?("block.\(block.id).text", block.text ?? "Continue") ?? block.text ?? "Continue")
                .font(.body.weight(.semibold))
                .foregroundColor(Color(hex: block.text_color ?? "#FFFFFF"))
                .applyTextStyle(block.style)  // SPEC-084 Gap #8: override with schema-driven style when present
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: block.bg_color ?? "#6366F1"))
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(block.button_corner_radius ?? 12)))
        }
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
}
