import SwiftUI

// MARK: - Content Block Type

public enum ContentBlockType: String, Codable {
    case heading, text, image, button, spacer, list, divider, badge, icon, toggle, video
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
        }
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

        return Text(block.icon_emoji ?? "")
            .font(.system(size: CGFloat(block.icon_size ?? 32)))
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

    // MARK: - Video (thumbnail only — full video in SPEC-085)

    private func videoBlock(_ block: ContentBlock) -> some View {
        let effectiveHeight = CGFloat(block.video_height ?? block.height ?? 200)
        let effectiveCornerRadius = CGFloat(block.video_corner_radius ?? block.corner_radius ?? 8)

        return Group {
            if let thumbUrl = block.video_thumbnail_url ?? block.image_url,
               let url = URL(string: thumbUrl) {
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
                            // Play icon overlay
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
}
