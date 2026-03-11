import SwiftUI

// MARK: - Config types for design tokens

/// Text styling properties from Firestore config.
public struct TextStyleConfig: Codable {
    public let font_family: String?
    public let font_size: Double?
    public let font_weight: Int?
    public let color: String?
    public let alignment: String?
    public let line_height: Double?
    public let letter_spacing: Double?
    public let opacity: Double?
}

/// Background style (color, gradient, or image).
public struct BackgroundStyleConfig: Codable {
    public let type: String?         // "color", "gradient", "image"
    public let color: String?
    public let gradient: GradientConfig?
    public let image_url: String?
    public let image_fit: String?    // "cover", "contain", "fill", "none"
    public let overlay: String?      // hex color overlay
}

public struct GradientConfig: Codable {
    public let type: String?         // "linear", "radial"
    public let angle: Double?
    public let stops: [GradientStopConfig]?
}

public struct GradientStopConfig: Codable {
    public let color: String
    public let position: Double
}

/// Border style.
public struct BorderStyleConfig: Codable {
    public let width: Double?
    public let color: String?
    public let style: String?        // "solid", "dashed", "dotted", "none"
    public let radius: Double?
    public let radius_top_left: Double?
    public let radius_top_right: Double?
    public let radius_bottom_left: Double?
    public let radius_bottom_right: Double?
}

/// Shadow style.
public struct ShadowStyleConfig: Codable {
    public let x: Double?
    public let y: Double?
    public let blur: Double?
    public let spread: Double?
    public let color: String?
}

/// Spacing/padding.
public struct SpacingConfig: Codable {
    public let top: Double?
    public let right: Double?
    public let bottom: Double?
    public let left: Double?
}

/// Full container/element style combining background, border, shadow, padding.
public struct ElementStyleConfig: Codable {
    public let background: BackgroundStyleConfig?
    public let border: BorderStyleConfig?
    public let shadow: ShadowStyleConfig?
    public let padding: SpacingConfig?
    public let corner_radius: Double?
    public let opacity: Double?
}

/// Section-level style (container + per-element overrides).
public struct SectionStyleConfig: Codable {
    public let container: ElementStyleConfig?
    public let elements: [String: ElementStyleConfig]?
}

/// Animation configuration.
public struct AnimationConfig: Codable {
    public let entry_animation: String?       // slide_up, fade_in, scale_in, none
    public let entry_duration_ms: Int?
    public let section_stagger: String?       // fade_in, slide_in_left, slide_in_right, bounce, none
    public let section_stagger_delay_ms: Int?
    public let cta_animation: String?         // pulse, glow, bounce, none
    public let plan_selection_animation: String? // scale, border_highlight, glow, none
    public let dismiss_animation: String?     // slide_down, fade_out, none
}

/// Localization strings per locale.
public struct LocalizationConfig: Codable {
    public let localizations: [String: [String: String]]?
    public let default_locale: String?
}

// MARK: - SwiftUI View extensions for applying design tokens

extension View {
    /// Apply TextStyleConfig to a Text-like view.
    func applyTextStyle(_ style: TextStyleConfig?) -> some View {
        guard let s = style else { return AnyView(self) }
        let font = FontResolver.font(family: s.font_family, size: s.font_size, weight: s.font_weight)
        return AnyView(
            self
                .font(font)
                .foregroundColor(s.color.map { Color(hex: $0) } ?? .primary)
                .multilineTextAlignment(textAlignment(s.alignment))
                .lineSpacing(lineSpacing(s.line_height, s.font_size))
                .tracking(CGFloat(s.letter_spacing ?? 0))
                .opacity(s.opacity ?? 1.0)
        )
    }

    /// Apply ElementStyleConfig to a container view.
    func applyContainerStyle(_ style: ElementStyleConfig?) -> some View {
        guard let s = style else { return AnyView(self) }
        let defaultRadius = CGFloat(s.corner_radius ?? 0)
        let border = s.border

        // Per-corner radius support (SPEC-084)
        let hasPerCorner = border?.radius_top_left != nil || border?.radius_top_right != nil
            || border?.radius_bottom_left != nil || border?.radius_bottom_right != nil

        let base = self
            .padding(edgeInsets(s.padding))
            .background(StyleEngine.backgroundView(s.background))

        if hasPerCorner {
            let tl = CGFloat(border?.radius_top_left ?? Double(defaultRadius))
            let tr = CGFloat(border?.radius_top_right ?? Double(defaultRadius))
            let bl = CGFloat(border?.radius_bottom_left ?? Double(defaultRadius))
            let br = CGFloat(border?.radius_bottom_right ?? Double(defaultRadius))
            let path = PerCornerRadiusShape(topLeft: tl, topRight: tr, bottomLeft: bl, bottomRight: br)
            return AnyView(
                base
                    .clipShape(path)
                    .overlay(path.stroke(
                        Color(hex: border?.color ?? "transparent"),
                        lineWidth: CGFloat(border?.width ?? 0)
                    ))
                    .shadow(
                        color: Color(hex: s.shadow?.color ?? "transparent"),
                        radius: CGFloat(s.shadow?.blur ?? 0) / 2,
                        x: CGFloat(s.shadow?.x ?? 0),
                        y: CGFloat(s.shadow?.y ?? 0)
                    )
                    .opacity(s.opacity ?? 1.0)
            )
        } else {
            let shape = RoundedRectangle(cornerRadius: defaultRadius)
            return AnyView(
                base
                    .clipShape(shape)
                    .overlay(shape.stroke(
                        Color(hex: border?.color ?? "transparent"),
                        lineWidth: CGFloat(border?.width ?? 0)
                    ))
                    .shadow(
                        color: Color(hex: s.shadow?.color ?? "transparent"),
                        radius: CGFloat(s.shadow?.blur ?? 0) / 2,
                        x: CGFloat(s.shadow?.x ?? 0),
                        y: CGFloat(s.shadow?.y ?? 0)
                    )
                    .opacity(s.opacity ?? 1.0)
            )
        }
    }

    private func textAlignment(_ alignment: String?) -> TextAlignment {
        switch alignment {
        case "center": return .center
        case "right": return .trailing
        default: return .leading
        }
    }

    private func lineSpacing(_ lineHeight: Double?, _ fontSize: Double?) -> CGFloat {
        guard let lh = lineHeight else { return 0 }
        let size = CGFloat(fontSize ?? 16)
        return (CGFloat(lh) - 1.0) * size
    }

    private func edgeInsets(_ padding: SpacingConfig?) -> EdgeInsets {
        guard let p = padding else { return EdgeInsets() }
        return EdgeInsets(
            top: CGFloat(p.top ?? 0),
            leading: CGFloat(p.left ?? 0),
            bottom: CGFloat(p.bottom ?? 0),
            trailing: CGFloat(p.right ?? 0)
        )
    }
}

// MARK: - Background rendering

enum StyleEngine {
    @ViewBuilder
    static func backgroundView(_ bg: BackgroundStyleConfig?) -> some View {
        switch bg?.type {
        case "color":
            Color(hex: bg?.color ?? "#FFFFFF")
        case "gradient":
            if let grad = bg?.gradient, let stops = grad.stops, stops.count >= 2 {
                switch grad.type {
                case "radial":
                    RadialGradient(
                        colors: stops.map { Color(hex: $0.color) },
                        center: .center,
                        startRadius: 0,
                        endRadius: 300
                    )
                default: // linear
                    LinearGradient(
                        colors: stops.map { Color(hex: $0.color) },
                        startPoint: gradientPoint(angle: grad.angle ?? 180, start: true),
                        endPoint: gradientPoint(angle: grad.angle ?? 180, start: false)
                    )
                }
            } else {
                Color.clear
            }
        case "image":
            ZStack {
                if let urlString = bg?.image_url, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: imageFit(bg?.image_fit))
                        default:
                            Color.clear
                        }
                    }
                }
                if let overlay = bg?.overlay {
                    Color(hex: overlay)
                }
            }
        default:
            Color.clear
        }
    }

    private static func gradientPoint(angle: Double, start: Bool) -> UnitPoint {
        let rads = angle * .pi / 180
        let dx = sin(rads)
        let dy = -cos(rads)
        if start {
            return UnitPoint(x: 0.5 - dx / 2, y: 0.5 - dy / 2)
        }
        return UnitPoint(x: 0.5 + dx / 2, y: 0.5 + dy / 2)
    }

    private static func imageFit(_ fit: String?) -> ContentMode {
        switch fit {
        case "contain": return .fit
        default: return .fill
        }
    }
}

// MARK: - Per-corner radius shape (iOS 15 compatible)

struct PerCornerRadiusShape: Shape {
    let topLeft: CGFloat
    let topRight: CGFloat
    let bottomLeft: CGFloat
    let bottomRight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
            radius: topRight, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addArc(
            center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
            radius: bottomRight, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
            radius: bottomLeft, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addArc(
            center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
            radius: topLeft, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Localization helper

enum LocalizationEngine {
    static func resolve(key: String, localizations: [String: [String: String]]?, defaultLocale: String?, fallback: String) -> String {
        let deviceLocale = Locale.current.language.languageCode?.identifier ?? "en"
        if let value = localizations?[deviceLocale]?[key] {
            return value
        }
        if let defLocale = defaultLocale, let value = localizations?[defLocale]?[key] {
            return value
        }
        return fallback
    }
}
