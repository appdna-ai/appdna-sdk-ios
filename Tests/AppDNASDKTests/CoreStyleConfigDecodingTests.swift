import XCTest
@testable import AppDNASDK

/// Comprehensive JSON decoding tests for all shared Codable design-token types
/// in Core/StyleEngine.swift, Core/HapticEngine.swift, Core/ConfettiOverlay.swift,
/// Core/BlurModifier.swift, and Core/IconResolver.swift.
///
/// These types are used across ALL 5 SDK modules (onboarding, paywalls,
/// messages, surveys, push) so getting decode right is critical.
final class CoreStyleConfigDecodingTests: XCTestCase {

    // MARK: - TextStyleConfig

    func testDecodeTextStyleConfigAllFields() throws {
        let json = """
        {
            "font_family": "Helvetica Neue",
            "font_size": 18.0,
            "font_weight": 700,
            "color": "#1A1A2E",
            "alignment": "center",
            "line_height": 1.5,
            "letter_spacing": 0.5,
            "opacity": 0.9
        }
        """.data(using: .utf8)!

        let style = try JSONDecoder().decode(TextStyleConfig.self, from: json)
        XCTAssertEqual(style.font_family, "Helvetica Neue")
        XCTAssertEqual(style.font_size, 18.0)
        XCTAssertEqual(style.font_weight, 700)
        XCTAssertEqual(style.color, "#1A1A2E")
        XCTAssertEqual(style.alignment, "center")
        XCTAssertEqual(style.line_height, 1.5)
        XCTAssertEqual(style.letter_spacing, 0.5)
        XCTAssertEqual(style.opacity, 0.9)
    }

    func testDecodeTextStyleConfigEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let style = try JSONDecoder().decode(TextStyleConfig.self, from: json)
        XCTAssertNil(style.font_family)
        XCTAssertNil(style.font_size)
        XCTAssertNil(style.font_weight)
        XCTAssertNil(style.color)
        XCTAssertNil(style.alignment)
        XCTAssertNil(style.line_height)
        XCTAssertNil(style.letter_spacing)
        XCTAssertNil(style.opacity)
    }

    func testDecodeTextStyleConfigPartial() throws {
        let json = """
        { "font_size": 14.0, "color": "#333333" }
        """.data(using: .utf8)!

        let style = try JSONDecoder().decode(TextStyleConfig.self, from: json)
        XCTAssertNil(style.font_family)
        XCTAssertEqual(style.font_size, 14.0)
        XCTAssertNil(style.font_weight)
        XCTAssertEqual(style.color, "#333333")
        XCTAssertNil(style.alignment)
    }

    func testDecodeTextStyleAlignmentValues() throws {
        for alignment in ["left", "center", "right"] {
            let json = """
            { "alignment": "\(alignment)" }
            """.data(using: .utf8)!

            let style = try JSONDecoder().decode(TextStyleConfig.self, from: json)
            XCTAssertEqual(style.alignment, alignment)
        }
    }

    // MARK: - BackgroundStyleConfig

    func testDecodeBackgroundStyleConfigColor() throws {
        let json = """
        {
            "type": "color",
            "color": "#FF5733"
        }
        """.data(using: .utf8)!

        let bg = try JSONDecoder().decode(BackgroundStyleConfig.self, from: json)
        XCTAssertEqual(bg.type, "color")
        XCTAssertEqual(bg.color, "#FF5733")
        XCTAssertNil(bg.gradient)
        XCTAssertNil(bg.image_url)
        XCTAssertNil(bg.overlay)
    }

    func testDecodeBackgroundStyleConfigGradient() throws {
        let json = """
        {
            "type": "gradient",
            "gradient": {
                "type": "linear",
                "angle": 135.0,
                "stops": [
                    { "color": "#FF0000", "position": 0.0 },
                    { "color": "#0000FF", "position": 1.0 }
                ]
            }
        }
        """.data(using: .utf8)!

        let bg = try JSONDecoder().decode(BackgroundStyleConfig.self, from: json)
        XCTAssertEqual(bg.type, "gradient")
        XCTAssertNotNil(bg.gradient)
        XCTAssertEqual(bg.gradient?.type, "linear")
        XCTAssertEqual(bg.gradient?.angle, 135.0)
        XCTAssertEqual(bg.gradient?.stops?.count, 2)
        XCTAssertEqual(bg.gradient?.stops?[0].color, "#FF0000")
        XCTAssertEqual(bg.gradient?.stops?[0].position, 0.0)
        XCTAssertEqual(bg.gradient?.stops?[1].color, "#0000FF")
        XCTAssertEqual(bg.gradient?.stops?[1].position, 1.0)
    }

    func testDecodeBackgroundStyleConfigRadialGradient() throws {
        let json = """
        {
            "type": "gradient",
            "gradient": {
                "type": "radial",
                "stops": [
                    { "color": "#FFFFFF", "position": 0.0 },
                    { "color": "#000000", "position": 1.0 }
                ]
            }
        }
        """.data(using: .utf8)!

        let bg = try JSONDecoder().decode(BackgroundStyleConfig.self, from: json)
        XCTAssertEqual(bg.gradient?.type, "radial")
        XCTAssertNil(bg.gradient?.angle)
        XCTAssertEqual(bg.gradient?.stops?.count, 2)
    }

    func testDecodeBackgroundStyleConfigImage() throws {
        let json = """
        {
            "type": "image",
            "image_url": "https://cdn.example.com/bg.jpg",
            "image_fit": "cover",
            "overlay": "#00000088"
        }
        """.data(using: .utf8)!

        let bg = try JSONDecoder().decode(BackgroundStyleConfig.self, from: json)
        XCTAssertEqual(bg.type, "image")
        XCTAssertEqual(bg.image_url, "https://cdn.example.com/bg.jpg")
        XCTAssertEqual(bg.image_fit, "cover")
        XCTAssertEqual(bg.overlay, "#00000088")
    }

    func testDecodeBackgroundStyleConfigImageFitValues() throws {
        for fit in ["cover", "contain", "fill", "none"] {
            let json = """
            { "type": "image", "image_url": "https://example.com/img.jpg", "image_fit": "\(fit)" }
            """.data(using: .utf8)!

            let bg = try JSONDecoder().decode(BackgroundStyleConfig.self, from: json)
            XCTAssertEqual(bg.image_fit, fit)
        }
    }

    func testDecodeBackgroundStyleConfigEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let bg = try JSONDecoder().decode(BackgroundStyleConfig.self, from: json)
        XCTAssertNil(bg.type)
        XCTAssertNil(bg.color)
        XCTAssertNil(bg.gradient)
        XCTAssertNil(bg.image_url)
        XCTAssertNil(bg.image_fit)
        XCTAssertNil(bg.overlay)
    }

    // MARK: - GradientConfig

    func testDecodeGradientConfigLinear() throws {
        let json = """
        {
            "type": "linear",
            "angle": 180.0,
            "stops": [
                { "color": "#6366F1", "position": 0.0 },
                { "color": "#8B5CF6", "position": 0.5 },
                { "color": "#EC4899", "position": 1.0 }
            ]
        }
        """.data(using: .utf8)!

        let grad = try JSONDecoder().decode(GradientConfig.self, from: json)
        XCTAssertEqual(grad.type, "linear")
        XCTAssertEqual(grad.angle, 180.0)
        XCTAssertEqual(grad.stops?.count, 3)
        XCTAssertEqual(grad.stops?[1].color, "#8B5CF6")
        XCTAssertEqual(grad.stops?[1].position, 0.5)
    }

    func testDecodeGradientConfigEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let grad = try JSONDecoder().decode(GradientConfig.self, from: json)
        XCTAssertNil(grad.type)
        XCTAssertNil(grad.angle)
        XCTAssertNil(grad.stops)
    }

    func testDecodeGradientStopConfig() throws {
        let json = """
        { "color": "#FF6B6B", "position": 0.75 }
        """.data(using: .utf8)!

        let stop = try JSONDecoder().decode(GradientStopConfig.self, from: json)
        XCTAssertEqual(stop.color, "#FF6B6B")
        XCTAssertEqual(stop.position, 0.75)
    }

    // MARK: - BorderStyleConfig

    func testDecodeBorderStyleConfigAllFields() throws {
        let json = """
        {
            "width": 2.0,
            "color": "#6366F1",
            "style": "solid",
            "radius": 12.0,
            "radius_top_left": 16.0,
            "radius_top_right": 16.0,
            "radius_bottom_left": 4.0,
            "radius_bottom_right": 4.0
        }
        """.data(using: .utf8)!

        let border = try JSONDecoder().decode(BorderStyleConfig.self, from: json)
        XCTAssertEqual(border.width, 2.0)
        XCTAssertEqual(border.color, "#6366F1")
        XCTAssertEqual(border.style, "solid")
        XCTAssertEqual(border.radius, 12.0)
        XCTAssertEqual(border.radius_top_left, 16.0)
        XCTAssertEqual(border.radius_top_right, 16.0)
        XCTAssertEqual(border.radius_bottom_left, 4.0)
        XCTAssertEqual(border.radius_bottom_right, 4.0)
    }

    func testDecodeBorderStyleConfigEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let border = try JSONDecoder().decode(BorderStyleConfig.self, from: json)
        XCTAssertNil(border.width)
        XCTAssertNil(border.color)
        XCTAssertNil(border.style)
        XCTAssertNil(border.radius)
        XCTAssertNil(border.radius_top_left)
        XCTAssertNil(border.radius_top_right)
        XCTAssertNil(border.radius_bottom_left)
        XCTAssertNil(border.radius_bottom_right)
    }

    func testDecodeBorderStyleValues() throws {
        for style in ["solid", "dashed", "dotted", "none"] {
            let json = """
            { "style": "\(style)" }
            """.data(using: .utf8)!

            let border = try JSONDecoder().decode(BorderStyleConfig.self, from: json)
            XCTAssertEqual(border.style, style)
        }
    }

    func testDecodeBorderStylePerCornerRadiusOnly() throws {
        let json = """
        {
            "radius_top_left": 20.0,
            "radius_top_right": 20.0,
            "radius_bottom_left": 0.0,
            "radius_bottom_right": 0.0
        }
        """.data(using: .utf8)!

        let border = try JSONDecoder().decode(BorderStyleConfig.self, from: json)
        XCTAssertNil(border.radius)
        XCTAssertEqual(border.radius_top_left, 20.0)
        XCTAssertEqual(border.radius_top_right, 20.0)
        XCTAssertEqual(border.radius_bottom_left, 0.0)
        XCTAssertEqual(border.radius_bottom_right, 0.0)
    }

    // MARK: - ShadowStyleConfig

    func testDecodeShadowStyleConfigAllFields() throws {
        let json = """
        {
            "x": 2.0,
            "y": 4.0,
            "blur": 8.0,
            "spread": 1.0,
            "color": "#00000033"
        }
        """.data(using: .utf8)!

        let shadow = try JSONDecoder().decode(ShadowStyleConfig.self, from: json)
        XCTAssertEqual(shadow.x, 2.0)
        XCTAssertEqual(shadow.y, 4.0)
        XCTAssertEqual(shadow.blur, 8.0)
        XCTAssertEqual(shadow.spread, 1.0)
        XCTAssertEqual(shadow.color, "#00000033")
    }

    func testDecodeShadowStyleConfigEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let shadow = try JSONDecoder().decode(ShadowStyleConfig.self, from: json)
        XCTAssertNil(shadow.x)
        XCTAssertNil(shadow.y)
        XCTAssertNil(shadow.blur)
        XCTAssertNil(shadow.spread)
        XCTAssertNil(shadow.color)
    }

    func testDecodeShadowStyleConfigPartial() throws {
        let json = """
        { "y": 2.0, "blur": 6.0, "color": "#0000001A" }
        """.data(using: .utf8)!

        let shadow = try JSONDecoder().decode(ShadowStyleConfig.self, from: json)
        XCTAssertNil(shadow.x)
        XCTAssertEqual(shadow.y, 2.0)
        XCTAssertEqual(shadow.blur, 6.0)
        XCTAssertNil(shadow.spread)
        XCTAssertEqual(shadow.color, "#0000001A")
    }

    // MARK: - SpacingConfig

    func testDecodeSpacingConfigAllFields() throws {
        let json = """
        { "top": 16.0, "right": 20.0, "bottom": 16.0, "left": 20.0 }
        """.data(using: .utf8)!

        let spacing = try JSONDecoder().decode(SpacingConfig.self, from: json)
        XCTAssertEqual(spacing.top, 16.0)
        XCTAssertEqual(spacing.right, 20.0)
        XCTAssertEqual(spacing.bottom, 16.0)
        XCTAssertEqual(spacing.left, 20.0)
    }

    func testDecodeSpacingConfigEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let spacing = try JSONDecoder().decode(SpacingConfig.self, from: json)
        XCTAssertNil(spacing.top)
        XCTAssertNil(spacing.right)
        XCTAssertNil(spacing.bottom)
        XCTAssertNil(spacing.left)
    }

    func testDecodeSpacingConfigPartialVerticalOnly() throws {
        let json = """
        { "top": 8.0, "bottom": 8.0 }
        """.data(using: .utf8)!

        let spacing = try JSONDecoder().decode(SpacingConfig.self, from: json)
        XCTAssertEqual(spacing.top, 8.0)
        XCTAssertNil(spacing.right)
        XCTAssertEqual(spacing.bottom, 8.0)
        XCTAssertNil(spacing.left)
    }

    // MARK: - ElementStyleConfig (with CodingKeys)

    func testDecodeElementStyleConfigAllFields() throws {
        let json = """
        {
            "background": { "type": "color", "color": "#F0F0F0" },
            "border": { "width": 1.0, "color": "#CCCCCC", "style": "solid", "radius": 8.0 },
            "shadow": { "x": 0, "y": 2, "blur": 4, "color": "#0000001A" },
            "padding": { "top": 12, "right": 16, "bottom": 12, "left": 16 },
            "corner_radius": 12.0,
            "opacity": 0.95,
            "text_style": { "font_size": 16.0, "color": "#333333", "font_weight": 400 }
        }
        """.data(using: .utf8)!

        let style = try JSONDecoder().decode(ElementStyleConfig.self, from: json)
        XCTAssertNotNil(style.background)
        XCTAssertEqual(style.background?.type, "color")
        XCTAssertEqual(style.background?.color, "#F0F0F0")
        XCTAssertNotNil(style.border)
        XCTAssertEqual(style.border?.width, 1.0)
        XCTAssertEqual(style.border?.color, "#CCCCCC")
        XCTAssertEqual(style.border?.style, "solid")
        XCTAssertEqual(style.border?.radius, 8.0)
        XCTAssertNotNil(style.shadow)
        XCTAssertEqual(style.shadow?.y, 2.0)
        XCTAssertEqual(style.shadow?.blur, 4.0)
        XCTAssertNotNil(style.padding)
        XCTAssertEqual(style.padding?.top, 12.0)
        XCTAssertEqual(style.padding?.right, 16.0)
        XCTAssertEqual(style.corner_radius, 12.0)
        XCTAssertEqual(style.opacity, 0.95)
        // CodingKeys: text_style -> textStyle
        XCTAssertNotNil(style.textStyle)
        XCTAssertEqual(style.textStyle?.font_size, 16.0)
        XCTAssertEqual(style.textStyle?.color, "#333333")
        XCTAssertEqual(style.textStyle?.font_weight, 400)
    }

    func testDecodeElementStyleConfigEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let style = try JSONDecoder().decode(ElementStyleConfig.self, from: json)
        XCTAssertNil(style.background)
        XCTAssertNil(style.border)
        XCTAssertNil(style.shadow)
        XCTAssertNil(style.padding)
        XCTAssertNil(style.corner_radius)
        XCTAssertNil(style.opacity)
        XCTAssertNil(style.textStyle)
    }

    func testDecodeElementStyleConfigCodingKeyTextStyle() throws {
        // Verify that "text_style" in JSON maps to the Swift `textStyle` property
        let json = """
        {
            "text_style": { "font_size": 24.0, "font_weight": 700 }
        }
        """.data(using: .utf8)!

        let style = try JSONDecoder().decode(ElementStyleConfig.self, from: json)
        XCTAssertNotNil(style.textStyle)
        XCTAssertEqual(style.textStyle?.font_size, 24.0)
        XCTAssertEqual(style.textStyle?.font_weight, 700)
    }

    func testDecodeElementStyleConfigWithGradientBackground() throws {
        let json = """
        {
            "background": {
                "type": "gradient",
                "gradient": {
                    "type": "linear",
                    "angle": 90.0,
                    "stops": [
                        { "color": "#6366F1", "position": 0.0 },
                        { "color": "#8B5CF6", "position": 1.0 }
                    ]
                }
            },
            "corner_radius": 16.0
        }
        """.data(using: .utf8)!

        let style = try JSONDecoder().decode(ElementStyleConfig.self, from: json)
        XCTAssertEqual(style.background?.type, "gradient")
        XCTAssertEqual(style.background?.gradient?.type, "linear")
        XCTAssertEqual(style.background?.gradient?.angle, 90.0)
        XCTAssertEqual(style.background?.gradient?.stops?.count, 2)
        XCTAssertEqual(style.corner_radius, 16.0)
    }

    func testEncodeAndDecodeElementStyleConfigRoundTrip() throws {
        let json = """
        {
            "background": { "type": "color", "color": "#FFFFFF" },
            "border": { "width": 1.0, "color": "#E0E0E0" },
            "padding": { "top": 8, "bottom": 8 },
            "corner_radius": 8.0,
            "opacity": 1.0,
            "text_style": { "font_size": 14.0 }
        }
        """.data(using: .utf8)!

        let original = try JSONDecoder().decode(ElementStyleConfig.self, from: json)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ElementStyleConfig.self, from: encoded)

        XCTAssertEqual(decoded.background?.type, "color")
        XCTAssertEqual(decoded.background?.color, "#FFFFFF")
        XCTAssertEqual(decoded.border?.width, 1.0)
        XCTAssertEqual(decoded.corner_radius, 8.0)
        XCTAssertEqual(decoded.opacity, 1.0)
        XCTAssertEqual(decoded.textStyle?.font_size, 14.0)
    }

    // MARK: - SectionStyleConfig

    func testDecodeSectionStyleConfigFull() throws {
        let json = """
        {
            "container": {
                "background": { "type": "color", "color": "#FAFAFA" },
                "padding": { "top": 24, "right": 16, "bottom": 24, "left": 16 },
                "corner_radius": 16.0
            },
            "elements": {
                "title": {
                    "text_style": { "font_size": 24.0, "font_weight": 700, "color": "#111111" }
                },
                "subtitle": {
                    "text_style": { "font_size": 16.0, "color": "#666666" },
                    "opacity": 0.8
                },
                "cta_button": {
                    "background": { "type": "color", "color": "#6366F1" },
                    "corner_radius": 12.0,
                    "text_style": { "color": "#FFFFFF", "font_weight": 600 }
                }
            }
        }
        """.data(using: .utf8)!

        let section = try JSONDecoder().decode(SectionStyleConfig.self, from: json)
        XCTAssertNotNil(section.container)
        XCTAssertEqual(section.container?.background?.color, "#FAFAFA")
        XCTAssertEqual(section.container?.padding?.top, 24.0)
        XCTAssertEqual(section.container?.corner_radius, 16.0)

        XCTAssertNotNil(section.elements)
        XCTAssertEqual(section.elements?.count, 3)

        let titleStyle = section.elements?["title"]
        XCTAssertNotNil(titleStyle)
        XCTAssertEqual(titleStyle?.textStyle?.font_size, 24.0)
        XCTAssertEqual(titleStyle?.textStyle?.font_weight, 700)

        let subtitleStyle = section.elements?["subtitle"]
        XCTAssertEqual(subtitleStyle?.textStyle?.font_size, 16.0)
        XCTAssertEqual(subtitleStyle?.opacity, 0.8)

        let ctaStyle = section.elements?["cta_button"]
        XCTAssertEqual(ctaStyle?.background?.color, "#6366F1")
        XCTAssertEqual(ctaStyle?.corner_radius, 12.0)
        XCTAssertEqual(ctaStyle?.textStyle?.color, "#FFFFFF")
    }

    func testDecodeSectionStyleConfigEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let section = try JSONDecoder().decode(SectionStyleConfig.self, from: json)
        XCTAssertNil(section.container)
        XCTAssertNil(section.elements)
    }

    func testDecodeSectionStyleConfigContainerOnly() throws {
        let json = """
        {
            "container": { "corner_radius": 8.0 }
        }
        """.data(using: .utf8)!

        let section = try JSONDecoder().decode(SectionStyleConfig.self, from: json)
        XCTAssertNotNil(section.container)
        XCTAssertEqual(section.container?.corner_radius, 8.0)
        XCTAssertNil(section.elements)
    }

    func testDecodeSectionStyleConfigElementsOnly() throws {
        let json = """
        {
            "elements": {
                "header": { "text_style": { "font_size": 20.0 } }
            }
        }
        """.data(using: .utf8)!

        let section = try JSONDecoder().decode(SectionStyleConfig.self, from: json)
        XCTAssertNil(section.container)
        XCTAssertNotNil(section.elements)
        XCTAssertEqual(section.elements?["header"]?.textStyle?.font_size, 20.0)
    }

    // MARK: - AnimationConfig

    func testDecodeAnimationConfigAllFields() throws {
        let json = """
        {
            "entry_animation": "slide_up",
            "entry_duration_ms": 500,
            "section_stagger": "fade_in",
            "section_stagger_delay_ms": 100,
            "cta_animation": "pulse",
            "plan_selection_animation": "scale",
            "dismiss_animation": "slide_down"
        }
        """.data(using: .utf8)!

        let anim = try JSONDecoder().decode(AnimationConfig.self, from: json)
        XCTAssertEqual(anim.entry_animation, "slide_up")
        XCTAssertEqual(anim.entry_duration_ms, 500)
        XCTAssertEqual(anim.section_stagger, "fade_in")
        XCTAssertEqual(anim.section_stagger_delay_ms, 100)
        XCTAssertEqual(anim.cta_animation, "pulse")
        XCTAssertEqual(anim.plan_selection_animation, "scale")
        XCTAssertEqual(anim.dismiss_animation, "slide_down")
    }

    func testDecodeAnimationConfigEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let anim = try JSONDecoder().decode(AnimationConfig.self, from: json)
        XCTAssertNil(anim.entry_animation)
        XCTAssertNil(anim.entry_duration_ms)
        XCTAssertNil(anim.section_stagger)
        XCTAssertNil(anim.section_stagger_delay_ms)
        XCTAssertNil(anim.cta_animation)
        XCTAssertNil(anim.plan_selection_animation)
        XCTAssertNil(anim.dismiss_animation)
    }

    func testDecodeAnimationConfigEntryTypes() throws {
        for entry in ["slide_up", "fade_in", "scale_in", "none"] {
            let json = """
            { "entry_animation": "\(entry)" }
            """.data(using: .utf8)!

            let anim = try JSONDecoder().decode(AnimationConfig.self, from: json)
            XCTAssertEqual(anim.entry_animation, entry)
        }
    }

    func testDecodeAnimationConfigStaggerTypes() throws {
        for stagger in ["fade_in", "slide_in_left", "slide_in_right", "bounce", "none"] {
            let json = """
            { "section_stagger": "\(stagger)" }
            """.data(using: .utf8)!

            let anim = try JSONDecoder().decode(AnimationConfig.self, from: json)
            XCTAssertEqual(anim.section_stagger, stagger)
        }
    }

    func testDecodeAnimationConfigCTATypes() throws {
        for cta in ["pulse", "glow", "bounce", "none"] {
            let json = """
            { "cta_animation": "\(cta)" }
            """.data(using: .utf8)!

            let anim = try JSONDecoder().decode(AnimationConfig.self, from: json)
            XCTAssertEqual(anim.cta_animation, cta)
        }
    }

    func testDecodeAnimationConfigPlanSelectionTypes() throws {
        for plan in ["scale", "border_highlight", "glow", "none"] {
            let json = """
            { "plan_selection_animation": "\(plan)" }
            """.data(using: .utf8)!

            let anim = try JSONDecoder().decode(AnimationConfig.self, from: json)
            XCTAssertEqual(anim.plan_selection_animation, plan)
        }
    }

    func testDecodeAnimationConfigDismissTypes() throws {
        for dismiss in ["slide_down", "fade_out", "none"] {
            let json = """
            { "dismiss_animation": "\(dismiss)" }
            """.data(using: .utf8)!

            let anim = try JSONDecoder().decode(AnimationConfig.self, from: json)
            XCTAssertEqual(anim.dismiss_animation, dismiss)
        }
    }

    // MARK: - HapticConfig

    func testDecodeHapticConfigAllTriggerTypes() throws {
        let json = """
        {
            "enabled": true,
            "triggers": {
                "on_step_advance": "medium",
                "on_button_tap": "light",
                "on_plan_select": "selection",
                "on_option_select": "selection",
                "on_toggle": "light",
                "on_form_submit": "success",
                "on_error": "error",
                "on_success": "success"
            }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(HapticConfig.self, from: json)
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.triggers.on_step_advance, .medium)
        XCTAssertEqual(config.triggers.on_button_tap, .light)
        XCTAssertEqual(config.triggers.on_plan_select, .selection)
        XCTAssertEqual(config.triggers.on_option_select, .selection)
        XCTAssertEqual(config.triggers.on_toggle, .light)
        XCTAssertEqual(config.triggers.on_form_submit, .success)
        XCTAssertEqual(config.triggers.on_error, .error)
        XCTAssertEqual(config.triggers.on_success, .success)
    }

    func testDecodeHapticConfigMinimalTriggers() throws {
        let json = """
        {
            "enabled": true,
            "triggers": {}
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(HapticConfig.self, from: json)
        XCTAssertTrue(config.enabled)
        XCTAssertNil(config.triggers.on_step_advance)
        XCTAssertNil(config.triggers.on_button_tap)
        XCTAssertNil(config.triggers.on_plan_select)
        XCTAssertNil(config.triggers.on_option_select)
        XCTAssertNil(config.triggers.on_toggle)
        XCTAssertNil(config.triggers.on_form_submit)
        XCTAssertNil(config.triggers.on_error)
        XCTAssertNil(config.triggers.on_success)
    }

    func testDecodeHapticTypeEnum() throws {
        let types: [(String, HapticType)] = [
            ("light", .light), ("medium", .medium), ("heavy", .heavy),
            ("selection", .selection), ("success", .success),
            ("warning", .warning), ("error", .error),
        ]
        for (raw, expected) in types {
            let json = "\"\(raw)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(HapticType.self, from: json)
            XCTAssertEqual(decoded, expected, "Failed for haptic type \(raw)")
        }
    }

    func testDecodeUnknownHapticTypeThrows() {
        let json = "\"ultra_heavy\"".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(HapticType.self, from: json))
    }

    // MARK: - ParticleEffect

    func testDecodeParticleEffectAllFields() throws {
        let json = """
        {
            "type": "confetti",
            "trigger": "on_appear",
            "duration_ms": 3000,
            "intensity": "heavy",
            "colors": ["#FF0000", "#00FF00", "#0000FF", "#FFFF00"]
        }
        """.data(using: .utf8)!

        let effect = try JSONDecoder().decode(ParticleEffect.self, from: json)
        XCTAssertEqual(effect.type, "confetti")
        XCTAssertEqual(effect.trigger, "on_appear")
        XCTAssertEqual(effect.duration_ms, 3000)
        XCTAssertEqual(effect.intensity, "heavy")
        XCTAssertEqual(effect.colors?.count, 4)
        XCTAssertEqual(effect.colors?[0], "#FF0000")
    }

    func testDecodeParticleEffectWithoutColors() throws {
        let json = """
        {
            "type": "sparkle",
            "trigger": "on_step_complete",
            "duration_ms": 2000,
            "intensity": "medium"
        }
        """.data(using: .utf8)!

        let effect = try JSONDecoder().decode(ParticleEffect.self, from: json)
        XCTAssertEqual(effect.type, "sparkle")
        XCTAssertEqual(effect.trigger, "on_step_complete")
        XCTAssertEqual(effect.duration_ms, 2000)
        XCTAssertEqual(effect.intensity, "medium")
        XCTAssertNil(effect.colors)
    }

    func testDecodeParticleEffectTypes() throws {
        for type in ["confetti", "sparkle", "fireworks", "snow", "hearts"] {
            let json = """
            { "type": "\(type)", "trigger": "on_appear", "duration_ms": 1000, "intensity": "light" }
            """.data(using: .utf8)!

            let effect = try JSONDecoder().decode(ParticleEffect.self, from: json)
            XCTAssertEqual(effect.type, type)
        }
    }

    func testDecodeParticleEffectTriggers() throws {
        for trigger in ["on_appear", "on_step_complete", "on_purchase", "on_flow_complete"] {
            let json = """
            { "type": "confetti", "trigger": "\(trigger)", "duration_ms": 1000, "intensity": "medium" }
            """.data(using: .utf8)!

            let effect = try JSONDecoder().decode(ParticleEffect.self, from: json)
            XCTAssertEqual(effect.trigger, trigger)
        }
    }

    func testDecodeParticleEffectIntensities() throws {
        for intensity in ["light", "medium", "heavy"] {
            let json = """
            { "type": "confetti", "trigger": "on_appear", "duration_ms": 1500, "intensity": "\(intensity)" }
            """.data(using: .utf8)!

            let effect = try JSONDecoder().decode(ParticleEffect.self, from: json)
            XCTAssertEqual(effect.intensity, intensity)
        }
    }

    func testDecodeParticleEffectEmptyColors() throws {
        let json = """
        {
            "type": "confetti",
            "trigger": "on_appear",
            "duration_ms": 1000,
            "intensity": "light",
            "colors": []
        }
        """.data(using: .utf8)!

        let effect = try JSONDecoder().decode(ParticleEffect.self, from: json)
        XCTAssertNotNil(effect.colors)
        XCTAssertEqual(effect.colors?.count, 0)
    }

    // MARK: - BlurConfig

    func testDecodeBlurConfigAllFields() throws {
        let json = """
        { "radius": 20.0, "tint": "#00000066", "saturation": 1.8 }
        """.data(using: .utf8)!

        let blur = try JSONDecoder().decode(BlurConfig.self, from: json)
        XCTAssertEqual(blur.radius, 20.0)
        XCTAssertEqual(blur.tint, "#00000066")
        XCTAssertEqual(blur.saturation, 1.8)
    }

    func testDecodeBlurConfigRadiusOnly() throws {
        let json = """
        { "radius": 10.0 }
        """.data(using: .utf8)!

        let blur = try JSONDecoder().decode(BlurConfig.self, from: json)
        XCTAssertEqual(blur.radius, 10.0)
        XCTAssertNil(blur.tint)
        XCTAssertNil(blur.saturation)
    }

    func testDecodeBlurConfigZeroRadius() throws {
        let json = """
        { "radius": 0.0 }
        """.data(using: .utf8)!

        let blur = try JSONDecoder().decode(BlurConfig.self, from: json)
        XCTAssertEqual(blur.radius, 0.0)
    }

    func testDecodeBlurConfigHighValues() throws {
        let json = """
        { "radius": 100.0, "tint": "#FFFFFF99", "saturation": 3.0 }
        """.data(using: .utf8)!

        let blur = try JSONDecoder().decode(BlurConfig.self, from: json)
        XCTAssertEqual(blur.radius, 100.0)
        XCTAssertEqual(blur.tint, "#FFFFFF99")
        XCTAssertEqual(blur.saturation, 3.0)
    }

    // MARK: - IconReference

    func testDecodeIconReferenceAllFields() throws {
        let json = """
        { "library": "lucide", "name": "heart", "color": "#FF0000", "size": 32.0 }
        """.data(using: .utf8)!

        let icon = try JSONDecoder().decode(IconReference.self, from: json)
        XCTAssertEqual(icon.library, "lucide")
        XCTAssertEqual(icon.name, "heart")
        XCTAssertEqual(icon.color, "#FF0000")
        XCTAssertEqual(icon.size, 32.0)
    }

    func testDecodeIconReferenceMinimal() throws {
        let json = """
        { "library": "emoji", "name": "star" }
        """.data(using: .utf8)!

        let icon = try JSONDecoder().decode(IconReference.self, from: json)
        XCTAssertEqual(icon.library, "emoji")
        XCTAssertEqual(icon.name, "star")
        XCTAssertNil(icon.color)
        XCTAssertNil(icon.size)
    }

    func testDecodeIconReferenceAllLibraries() throws {
        for lib in ["lucide", "sf-symbols", "material", "emoji"] {
            let json = """
            { "library": "\(lib)", "name": "check" }
            """.data(using: .utf8)!

            let icon = try JSONDecoder().decode(IconReference.self, from: json)
            XCTAssertEqual(icon.library, lib, "Failed for library \(lib)")
        }
    }

    func testEncodeAndDecodeIconReferenceRoundTrip() throws {
        let json = """
        { "library": "sf-symbols", "name": "star.fill", "color": "#FFD700", "size": 24.0 }
        """.data(using: .utf8)!

        let original = try JSONDecoder().decode(IconReference.self, from: json)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IconReference.self, from: encoded)

        XCTAssertEqual(decoded.library, "sf-symbols")
        XCTAssertEqual(decoded.name, "star.fill")
        XCTAssertEqual(decoded.color, "#FFD700")
        XCTAssertEqual(decoded.size, 24.0)
    }

    // MARK: - LocalizationConfig

    func testDecodeLocalizationConfigFull() throws {
        let json = """
        {
            "localizations": {
                "en": { "title": "Welcome", "body": "Hello!" },
                "fr": { "title": "Bienvenue", "body": "Bonjour!" },
                "de": { "title": "Willkommen", "body": "Hallo!" }
            },
            "default_locale": "en"
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(LocalizationConfig.self, from: json)
        XCTAssertEqual(config.default_locale, "en")
        XCTAssertEqual(config.localizations?.count, 3)
        XCTAssertEqual(config.localizations?["en"]?["title"], "Welcome")
        XCTAssertEqual(config.localizations?["fr"]?["body"], "Bonjour!")
    }

    func testDecodeLocalizationConfigEmpty() throws {
        let json = "{}".data(using: .utf8)!
        let config = try JSONDecoder().decode(LocalizationConfig.self, from: json)
        XCTAssertNil(config.localizations)
        XCTAssertNil(config.default_locale)
    }

    // MARK: - Composite / deeply nested structures

    func testDecodeElementStyleWithNestedGradientAndShadow() throws {
        let json = """
        {
            "background": {
                "type": "gradient",
                "gradient": {
                    "type": "linear",
                    "angle": 45.0,
                    "stops": [
                        { "color": "#667eea", "position": 0.0 },
                        { "color": "#764ba2", "position": 1.0 }
                    ]
                }
            },
            "border": {
                "width": 1.0,
                "color": "#FFFFFF33",
                "style": "solid",
                "radius_top_left": 24.0,
                "radius_top_right": 24.0,
                "radius_bottom_left": 0.0,
                "radius_bottom_right": 0.0
            },
            "shadow": {
                "x": 0.0,
                "y": 8.0,
                "blur": 24.0,
                "spread": 0.0,
                "color": "#00000040"
            },
            "padding": { "top": 32.0, "right": 24.0, "bottom": 32.0, "left": 24.0 },
            "corner_radius": 24.0,
            "opacity": 1.0,
            "text_style": {
                "font_family": "SF Pro Display",
                "font_size": 32.0,
                "font_weight": 800,
                "color": "#FFFFFF",
                "alignment": "center",
                "line_height": 1.2,
                "letter_spacing": -0.5,
                "opacity": 1.0
            }
        }
        """.data(using: .utf8)!

        let style = try JSONDecoder().decode(ElementStyleConfig.self, from: json)

        // Background
        XCTAssertEqual(style.background?.type, "gradient")
        XCTAssertEqual(style.background?.gradient?.angle, 45.0)
        XCTAssertEqual(style.background?.gradient?.stops?[0].color, "#667eea")

        // Border with per-corner radius
        XCTAssertEqual(style.border?.width, 1.0)
        XCTAssertEqual(style.border?.radius_top_left, 24.0)
        XCTAssertEqual(style.border?.radius_bottom_left, 0.0)

        // Shadow
        XCTAssertEqual(style.shadow?.y, 8.0)
        XCTAssertEqual(style.shadow?.blur, 24.0)
        XCTAssertEqual(style.shadow?.color, "#00000040")

        // Padding
        XCTAssertEqual(style.padding?.top, 32.0)
        XCTAssertEqual(style.padding?.left, 24.0)

        // Text style
        XCTAssertEqual(style.textStyle?.font_family, "SF Pro Display")
        XCTAssertEqual(style.textStyle?.font_size, 32.0)
        XCTAssertEqual(style.textStyle?.font_weight, 800)
        XCTAssertEqual(style.textStyle?.letter_spacing, -0.5)
    }

    func testDecodeSectionStyleWithMultipleElements() throws {
        let json = """
        {
            "container": {
                "background": { "type": "color", "color": "#111827" },
                "corner_radius": 20.0,
                "padding": { "top": 40, "right": 20, "bottom": 40, "left": 20 }
            },
            "elements": {
                "hero_image": {
                    "corner_radius": 16.0,
                    "shadow": { "y": 4, "blur": 12, "color": "#00000033" }
                },
                "title": {
                    "text_style": { "font_size": 28, "font_weight": 700, "color": "#FFFFFF" }
                },
                "subtitle": {
                    "text_style": { "font_size": 16, "color": "#9CA3AF", "line_height": 1.5 }
                },
                "primary_cta": {
                    "background": { "type": "color", "color": "#6366F1" },
                    "corner_radius": 12,
                    "padding": { "top": 14, "right": 24, "bottom": 14, "left": 24 },
                    "text_style": { "font_size": 16, "font_weight": 600, "color": "#FFFFFF" }
                },
                "secondary_cta": {
                    "border": { "width": 1, "color": "#6366F1", "style": "solid" },
                    "corner_radius": 12,
                    "text_style": { "color": "#6366F1" }
                }
            }
        }
        """.data(using: .utf8)!

        let section = try JSONDecoder().decode(SectionStyleConfig.self, from: json)
        XCTAssertEqual(section.container?.background?.color, "#111827")
        XCTAssertEqual(section.elements?.count, 5)

        XCTAssertEqual(section.elements?["hero_image"]?.corner_radius, 16.0)
        XCTAssertEqual(section.elements?["hero_image"]?.shadow?.blur, 12.0)

        XCTAssertEqual(section.elements?["title"]?.textStyle?.font_weight, 700)
        XCTAssertEqual(section.elements?["subtitle"]?.textStyle?.line_height, 1.5)
        XCTAssertEqual(section.elements?["primary_cta"]?.background?.color, "#6366F1")
        XCTAssertEqual(section.elements?["secondary_cta"]?.border?.color, "#6366F1")
    }

    // MARK: - Edge cases: forward compatibility

    func testDecodeTextStyleIgnoresUnknownFields() throws {
        let json = """
        {
            "font_size": 14.0,
            "color": "#000000",
            "text_transform": "uppercase",
            "text_decoration": "underline"
        }
        """.data(using: .utf8)!

        // Unknown fields should be silently ignored
        let style = try JSONDecoder().decode(TextStyleConfig.self, from: json)
        XCTAssertEqual(style.font_size, 14.0)
        XCTAssertEqual(style.color, "#000000")
    }

    func testDecodeAnimationConfigIgnoresUnknownFields() throws {
        let json = """
        {
            "entry_animation": "slide_up",
            "exit_animation": "slide_down",
            "loop_count": 3
        }
        """.data(using: .utf8)!

        let anim = try JSONDecoder().decode(AnimationConfig.self, from: json)
        XCTAssertEqual(anim.entry_animation, "slide_up")
    }

    func testDecodeBlurConfigIgnoresUnknownFields() throws {
        let json = """
        {
            "radius": 15.0,
            "tint": "#FFFFFF22",
            "vibrancy": true,
            "material": "thin"
        }
        """.data(using: .utf8)!

        let blur = try JSONDecoder().decode(BlurConfig.self, from: json)
        XCTAssertEqual(blur.radius, 15.0)
        XCTAssertEqual(blur.tint, "#FFFFFF22")
    }

    func testDecodeParticleEffectIgnoresUnknownFields() throws {
        let json = """
        {
            "type": "confetti",
            "trigger": "on_appear",
            "duration_ms": 2000,
            "intensity": "medium",
            "gravity": 0.8,
            "wind_speed": 1.2
        }
        """.data(using: .utf8)!

        let effect = try JSONDecoder().decode(ParticleEffect.self, from: json)
        XCTAssertEqual(effect.type, "confetti")
        XCTAssertEqual(effect.duration_ms, 2000)
    }

    // MARK: - Numeric edge cases

    func testDecodeSpacingConfigWithZeroes() throws {
        let json = """
        { "top": 0.0, "right": 0.0, "bottom": 0.0, "left": 0.0 }
        """.data(using: .utf8)!

        let spacing = try JSONDecoder().decode(SpacingConfig.self, from: json)
        XCTAssertEqual(spacing.top, 0.0)
        XCTAssertEqual(spacing.right, 0.0)
        XCTAssertEqual(spacing.bottom, 0.0)
        XCTAssertEqual(spacing.left, 0.0)
    }

    func testDecodeShadowWithNegativeValues() throws {
        let json = """
        { "x": -3.0, "y": -5.0, "blur": 10.0, "spread": -1.0, "color": "#000000" }
        """.data(using: .utf8)!

        let shadow = try JSONDecoder().decode(ShadowStyleConfig.self, from: json)
        XCTAssertEqual(shadow.x, -3.0)
        XCTAssertEqual(shadow.y, -5.0)
        XCTAssertEqual(shadow.spread, -1.0)
    }

    func testDecodeTextStyleWithNegativeLetterSpacing() throws {
        let json = """
        { "letter_spacing": -1.5, "font_size": 32.0 }
        """.data(using: .utf8)!

        let style = try JSONDecoder().decode(TextStyleConfig.self, from: json)
        XCTAssertEqual(style.letter_spacing, -1.5)
    }

    func testDecodeElementStyleOpacityBoundaries() throws {
        // Opacity at 0
        let json0 = """
        { "opacity": 0.0 }
        """.data(using: .utf8)!
        let style0 = try JSONDecoder().decode(ElementStyleConfig.self, from: json0)
        XCTAssertEqual(style0.opacity, 0.0)

        // Opacity at 1
        let json1 = """
        { "opacity": 1.0 }
        """.data(using: .utf8)!
        let style1 = try JSONDecoder().decode(ElementStyleConfig.self, from: json1)
        XCTAssertEqual(style1.opacity, 1.0)
    }
}
