import XCTest
@testable import AppDNASDK

/// Tests that ContentBlock correctly decodes JSON from the editor/Firestore.
/// These tests prevent the #1 production risk: field name mismatches between
/// what the editor writes and what the SDK reads.
final class ContentBlockDecodingTests: XCTestCase {

    // MARK: - Unknown block type doesn't crash (AC-001)

    func testUnknownBlockTypeDecodesToUnknown() throws {
        let json = """
        { "id": "b1", "type": "future_block_type_2030" }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.id, "b1")
        XCTAssertEqual(block.type, .unknown)
    }

    // MARK: - Basic block types

    func testDecodeHeadingBlock() throws {
        let json = """
        {
            "id": "h1",
            "type": "heading",
            "text": "Welcome",
            "level": 1,
            "style": { "font_size": 28, "font_weight": 700, "color": "#ffffff" }
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .heading)
        XCTAssertEqual(block.text, "Welcome")
        XCTAssertEqual(block.level, 1)
        XCTAssertEqual(block.style?.font_size, 28)
        XCTAssertEqual(block.style?.font_weight, 700)
        XCTAssertEqual(block.style?.color, "#ffffff")
    }

    func testDecodeButtonBlock() throws {
        let json = """
        {
            "id": "btn1",
            "type": "button",
            "text": "Continue",
            "variant": "primary",
            "action": "next",
            "bg_color": "#6366f1",
            "text_color": "#ffffff",
            "button_corner_radius": 12
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .button)
        XCTAssertEqual(block.text, "Continue")
        XCTAssertEqual(block.variant, "primary")
        XCTAssertEqual(block.bg_color, "#6366f1")
        XCTAssertEqual(block.button_corner_radius, 12)
    }

    func testDecodeImageBlock() throws {
        let json = """
        {
            "id": "img1",
            "type": "image",
            "image_url": "https://example.com/photo.jpg",
            "height": 200,
            "corner_radius": 16,
            "alt": "Hero image"
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .image)
        XCTAssertEqual(block.image_url, "https://example.com/photo.jpg")
        XCTAssertEqual(block.height, 200)
        XCTAssertEqual(block.corner_radius, 16)
    }

    // MARK: - SPEC-089d new block types

    func testDecodePageIndicator() throws {
        let json = """
        {
            "id": "pi1",
            "type": "page_indicator",
            "dot_count": 5,
            "active_index": 2,
            "active_color": "#6366f1",
            "inactive_color": "#d1d5db",
            "dot_size": 8,
            "dot_spacing": 6,
            "active_dot_width": 24
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .page_indicator)
        XCTAssertEqual(block.dot_count, 5)
        XCTAssertEqual(block.active_index, 2)
        XCTAssertEqual(block.active_color, "#6366f1")
        XCTAssertEqual(block.dot_size, 8)
        XCTAssertEqual(block.active_dot_width, 24)
    }

    func testDecodeSocialLogin() throws {
        let json = """
        {
            "id": "sl1",
            "type": "social_login",
            "providers": [
                { "type": "apple", "enabled": true },
                { "type": "google", "enabled": true },
                { "type": "email", "label": "Continue with Email", "enabled": true }
            ],
            "button_style": "filled",
            "button_height": 52,
            "spacing": 12,
            "show_divider": true,
            "divider_text": "or continue with"
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .social_login)
        XCTAssertEqual(block.providers?.count, 3)
        XCTAssertEqual(block.providers?[0].type, "apple")
        XCTAssertEqual(block.providers?[2].label, "Continue with Email")
        XCTAssertEqual(block.button_style, "filled")
        XCTAssertEqual(block.show_divider, true)
    }

    func testDecodeCountdownTimer() throws {
        let json = """
        {
            "id": "ct1",
            "type": "countdown_timer",
            "timer_variant": "digital",
            "duration_seconds": 900,
            "show_hours": true,
            "show_minutes": true,
            "show_seconds": true,
            "on_expire_action": "auto_advance",
            "accent_color": "#ef4444"
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .countdown_timer)
        XCTAssertEqual(block.timer_variant, "digital")
        XCTAssertEqual(block.duration_seconds, 900)
        XCTAssertEqual(block.on_expire_action, "auto_advance")
    }

    func testDecodeRating() throws {
        let json = """
        {
            "id": "r1",
            "type": "rating",
            "max_stars": 5,
            "default_rating": 0,
            "star_size": 32,
            "filled_color": "#f59e0b",
            "empty_color": "#d1d5db",
            "allow_half": true,
            "field_id": "satisfaction"
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .rating)
        XCTAssertEqual(block.max_stars, 5)
        XCTAssertEqual(block.filled_color, "#f59e0b")
        XCTAssertEqual(block.allow_half, true)
        XCTAssertEqual(block.field_id, "satisfaction")
    }

    func testDecodeTimeline() throws {
        let json = """
        {
            "id": "tl1",
            "type": "timeline",
            "timeline_items": [
                { "id": "s1", "title": "Sign up", "subtitle": "Create account", "status": "completed" },
                { "id": "s2", "title": "Profile", "status": "current" },
                { "id": "s3", "title": "Ready!", "status": "upcoming" }
            ],
            "line_color": "#e5e7eb",
            "completed_color": "#10b981",
            "current_color": "#6366f1",
            "upcoming_color": "#9ca3af",
            "show_line": true
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .timeline)
        XCTAssertEqual(block.timeline_items?.count, 3)
        XCTAssertEqual(block.timeline_items?[0].status, "completed")
        XCTAssertEqual(block.timeline_items?[1].title, "Profile")
        XCTAssertEqual(block.show_line, true)
    }

    func testDecodeProgressBar() throws {
        let json = """
        {
            "id": "pb1",
            "type": "progress_bar",
            "progress_variant": "segmented",
            "total_segments": 5,
            "filled_segments": 3,
            "bar_height": 6,
            "bar_color": "#6366f1",
            "track_color": "#e5e7eb",
            "show_label": true,
            "segment_gap": 4
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .progress_bar)
        XCTAssertEqual(block.progress_variant, "segmented")
        XCTAssertEqual(block.total_segments, 5)
        XCTAssertEqual(block.filled_segments, 3)
        XCTAssertEqual(block.segment_gap, 4)
    }

    func testDecodePricingCard() throws {
        let json = """
        {
            "id": "pc1",
            "type": "pricing_card",
            "pricing_plans": [
                { "id": "p1", "label": "Monthly", "price": "$9.99", "period": "/month", "is_highlighted": false },
                { "id": "p2", "label": "Annual", "price": "$59.99", "period": "/year", "badge": "BEST VALUE", "is_highlighted": true }
            ],
            "pricing_layout": "stack"
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .pricing_card)
        XCTAssertEqual(block.pricing_plans?.count, 2)
        XCTAssertEqual(block.pricing_plans?[1].badge, "BEST VALUE")
        XCTAssertEqual(block.pricing_plans?[1].is_highlighted, true)
        XCTAssertEqual(block.pricing_layout, "stack")
    }

    // MARK: - Block Style Design Tokens (AC-005 through AC-009)

    func testDecodeBlockStyle() throws {
        let json = """
        {
            "id": "styled1",
            "type": "text",
            "text": "Styled block",
            "block_style": {
                "background_color": "#1a1a2e",
                "background_gradient": { "angle": 135, "start": "#6366f1", "end": "#a855f7" },
                "border_color": "#374151",
                "border_width": 1,
                "border_style": "solid",
                "border_radius": 12,
                "shadow": { "x": 0, "y": 4, "blur": 12, "spread": 0, "color": "rgba(0,0,0,0.15)" },
                "padding_top": 16,
                "padding_right": 16,
                "padding_bottom": 16,
                "padding_left": 16,
                "margin_top": 8,
                "margin_bottom": 8,
                "opacity": 0.95
            }
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        let bs = block.block_style
        XCTAssertNotNil(bs)
        XCTAssertEqual(bs?.background_color, "#1a1a2e")
        XCTAssertEqual(bs?.background_gradient?.angle, 135)
        XCTAssertEqual(bs?.border_color, "#374151")
        XCTAssertEqual(bs?.border_width, 1)
        XCTAssertEqual(bs?.border_radius, 12)
        XCTAssertNotNil(bs?.shadow)
        XCTAssertEqual(bs?.shadow?.blur, 12)
        XCTAssertEqual(bs?.padding_top, 16)
        XCTAssertEqual(bs?.margin_top, 8)
        XCTAssertEqual(bs?.opacity, 0.95)
    }

    // MARK: - Visibility Conditions (AC-054 through AC-056)

    func testDecodeVisibilityCondition() throws {
        let json = """
        {
            "id": "vc1",
            "type": "text",
            "text": "Conditional",
            "visibility_condition": {
                "type": "when_equals",
                "variable": "responses.step1.goal",
                "value": "fitness"
            }
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertNotNil(block.visibility_condition)
        XCTAssertEqual(block.visibility_condition?.type, "when_equals")
        XCTAssertEqual(block.visibility_condition?.variable, "responses.step1.goal")
    }

    // MARK: - Entrance Animations (AC-057 through AC-061)

    func testDecodeEntranceAnimation() throws {
        let json = """
        {
            "id": "ea1",
            "type": "heading",
            "text": "Animated",
            "entrance_animation": {
                "type": "slide_up",
                "duration_ms": 400,
                "delay_ms": 200,
                "easing": "spring"
            }
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertNotNil(block.entrance_animation)
        XCTAssertEqual(block.entrance_animation?.type, "slide_up")
        XCTAssertEqual(block.entrance_animation?.duration_ms, 400)
        XCTAssertEqual(block.entrance_animation?.delay_ms, 200)
    }

    // MARK: - Dynamic Bindings (AC-064 through AC-066)

    func testDecodeBindings() throws {
        let json = """
        {
            "id": "db1",
            "type": "circular_gauge",
            "gauge_value": 0,
            "bindings": {
                "gauge_value": "hook_data.user_progress",
                "bar_color": "hook_data.status_color"
            }
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.bindings?["gauge_value"], "hook_data.user_progress")
        XCTAssertEqual(block.bindings?["bar_color"], "hook_data.status_color")
    }

    // MARK: - Form Input Blocks (AC-040 through AC-053)

    func testDecodeFormInputText() throws {
        let json = """
        {
            "id": "fi1",
            "type": "input_text",
            "field_id": "full_name",
            "field_label": "Your Name",
            "field_placeholder": "Enter your name",
            "field_required": true
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .input_text)
        XCTAssertEqual(block.field_id, "full_name")
        XCTAssertEqual(block.field_label, "Your Name")
        XCTAssertEqual(block.field_placeholder, "Enter your name")
        XCTAssertEqual(block.field_required, true)
    }

    func testDecodeFormInputSelect() throws {
        let json = """
        {
            "id": "fi2",
            "type": "input_select",
            "field_id": "gender",
            "field_label": "Gender",
            "field_options": [
                { "id": "m", "label": "Male" },
                { "id": "f", "label": "Female" },
                { "id": "nb", "label": "Non-binary" }
            ]
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .input_select)
        XCTAssertEqual(block.field_options?.count, 3)
        XCTAssertEqual(block.field_options?[0].id, "m")
        XCTAssertEqual(block.field_options?[1].label, "Female")
    }

    // MARK: - Container Blocks (stack, row)

    func testDecodeStackWithChildren() throws {
        let json = """
        {
            "id": "stack1",
            "type": "stack",
            "children": [
                { "id": "c1", "type": "image", "image_url": "bg.jpg", "z_index": 0 },
                { "id": "c2", "type": "text", "text": "Overlay", "z_index": 1 }
            ]
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .stack)
        XCTAssertEqual(block.children?.count, 2)
        XCTAssertEqual(block.children?[0].type, .image)
        XCTAssertEqual(block.children?[1].z_index, 1)
    }

    // MARK: - 2D Positioning + Relative Sizing

    func testDecodePositioningAndSizing() throws {
        let json = """
        {
            "id": "pos1",
            "type": "button",
            "text": "Centered",
            "vertical_align": "center",
            "horizontal_align": "center",
            "vertical_offset": 10,
            "horizontal_offset": -5,
            "element_width": "80%",
            "element_height": "auto"
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.vertical_align, "center")
        XCTAssertEqual(block.horizontal_align, "center")
        XCTAssertEqual(block.vertical_offset, 10)
        XCTAssertEqual(block.horizontal_offset, -5)
        XCTAssertEqual(block.element_width, "80%")
        XCTAssertEqual(block.element_height, "auto")
    }

    // MARK: - Empty/minimal blocks don't crash

    func testDecodeMinimalBlock() throws {
        let json = """
        { "id": "min1", "type": "spacer" }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .spacer)
        XCTAssertNil(block.text)
        XCTAssertNil(block.block_style)
        XCTAssertNil(block.visibility_condition)
    }

    func testDecodeBlockWithExtraUnknownFields() throws {
        let json = """
        {
            "id": "extra1",
            "type": "text",
            "text": "Hello",
            "future_field_2030": "some value",
            "another_unknown": 42
        }
        """.data(using: .utf8)!

        // Should not crash — unknown fields are ignored by Codable
        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .text)
        XCTAssertEqual(block.text, "Hello")
    }

    // MARK: - Full Nurrai-style flow step with multiple blocks

    func testDecodeNurraiWelcomeStep() throws {
        let json = """
        {
            "id": "welcome",
            "type": "heading",
            "text": "Welcome to Nurrai",
            "level": 1,
            "style": { "font_size": 32, "font_weight": 800, "color": "#ffffff", "alignment": "center" },
            "block_style": {
                "margin_top": 40,
                "margin_bottom": 16
            },
            "entrance_animation": {
                "type": "fade_in",
                "duration_ms": 600,
                "delay_ms": 300,
                "easing": "ease_out"
            },
            "vertical_align": "center",
            "horizontal_align": "center"
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertEqual(block.type, .heading)
        XCTAssertEqual(block.text, "Welcome to Nurrai")
        XCTAssertEqual(block.style?.font_size, 32)
        XCTAssertEqual(block.style?.alignment, "center")
        XCTAssertEqual(block.block_style?.margin_top, 40)
        XCTAssertEqual(block.entrance_animation?.type, "fade_in")
        XCTAssertEqual(block.vertical_align, "center")
    }

    // MARK: - Pressed Style

    func testDecodePressedStyle() throws {
        let json = """
        {
            "id": "ps1",
            "type": "button",
            "text": "Tap me",
            "pressed_style": {
                "scale": 0.95,
                "opacity": 0.8,
                "bg_color": "#4f46e5"
            }
        }
        """.data(using: .utf8)!

        let block = try JSONDecoder().decode(ContentBlock.self, from: json)
        XCTAssertNotNil(block.pressed_style)
        XCTAssertEqual(block.pressed_style?.scale, 0.95)
        XCTAssertEqual(block.pressed_style?.opacity, 0.8)
    }
}
