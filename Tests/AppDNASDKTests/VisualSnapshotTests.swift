import SnapshotTesting
import SwiftUI
import XCTest
@testable import AppDNASDK

/// SPEC-419 EPIC-1 (Select overhaul) — iOS visual snapshots (surface #4: onboarding select).
///
/// Mirrors the Android Roborazzi `SelectEpic1SnapshotTest` with the SAME select configs so the
/// iOS + Android goldens are directly comparable (cross-platform parity, both systems 100%).
///
/// Record the goldens (first run / after an intended render change):
///   xcodebuild test -scheme AppDNASDK \
///     -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
///     -only-testing:AppDNASDKTests/VisualSnapshotTests RECORD_SNAPSHOTS=YES
/// Then commit Tests/__Snapshots__/. CI re-runs without RECORD_SNAPSHOTS and fails on pixel deltas.
final class VisualSnapshotTests: XCTestCase {

    private func render(_ json: String, inputs: [String: Any] = [:]) throws -> some View {
        let block = try JSONDecoder().decode(ContentBlock.self, from: Data(json.utf8))
        return ContentBlockRendererView(
            blocks: [block],
            onAction: { _, _ in },
            toggleValues: .constant([:]),
            inputValues: .constant(inputs)
        )
            .padding(16)
            .frame(width: 390)
            .background(Color(hex: "#0F1117"))
    }

    private func renderMany(_ jsons: [String]) throws -> some View {
        let blocks = try jsons.map { try JSONDecoder().decode(ContentBlock.self, from: Data($0.utf8)) }
        return ContentBlockRendererView(
            blocks: blocks,
            onAction: { _, _ in },
            toggleValues: .constant([:]),
            inputValues: .constant([:])
        )
            .padding(16)
            .frame(width: 390)
            .background(Color(hex: "#0F1117"))
    }

    /// leading_text + trailing_text on one row + positionable "RECOMMENDED" badge + subtitle.
    func testSelectStacked_leadingTrailingBadge() throws {
        let view = try render("""
        {
          "id": "sel1", "type": "input_select",
          "field_config": { "display_style": "stacked" },
          "field_options": [
            { "id": "o1", "label": "Casual", "leading_text": "5 min/day", "trailing_text": "Easy",
              "badge": { "text": "RECOMMENDED", "bg_color": "#22C55E", "text_color": "#FFFFFF", "position": "top_trailing" } },
            { "id": "o2", "label": "Regular", "leading_text": "10 min/day", "trailing_text": "Steady" },
            { "id": "o3", "label": "Serious", "subtitle": "Big goals", "leading_text": "15 min/day", "trailing_text": "Hard" }
          ]
        }
        """)
        // Compare by default (CI fails on pixel drift); record only when the bridge/env asks.
        // The bridge passes TEST_RUNNER_RECORD_SNAPSHOTS, which xcodebuild forwards to the sim
        // test process as RECORD_SNAPSHOTS (plain env vars don't reach the test runner).
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil ? .all : .never
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
        }
    }

    /// Per-option center alignment (title + subtitle centered).
    func testSelectStacked_centerAligned() throws {
        let view = try render("""
        {
          "id": "sel2", "type": "input_select",
          "field_config": { "display_style": "stacked" },
          "field_options": [
            { "id": "c1", "label": "Beginner", "subtitle": "Just starting out", "text_alignment": "center" },
            { "id": "c2", "label": "Intermediate", "subtitle": "Some experience", "text_alignment": "center" },
            { "id": "c3", "label": "Advanced", "subtitle": "Very experienced", "text_alignment": "center" }
          ]
        }
        """)
        // Compare by default (CI fails on pixel drift); record only when the bridge/env asks.
        // The bridge passes TEST_RUNNER_RECORD_SNAPSHOTS, which xcodebuild forwards to the sim
        // test process as RECORD_SNAPSHOTS (plain env vars don't reach the test runner).
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil ? .all : .never
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
        }
    }

    /// Per-option image_overlay_color tint (parity with Android ContentBlockRenderer).
    func testSelectStacked_imageOverlay() throws {
        let view = try render("""
        {
          "id": "sel3", "type": "input_select",
          "field_config": { "display_style": "stacked" },
          "field_options": [
            { "id": "i1", "label": "Circle", "image_url": "https://example.com/a.png", "image_overlay_color": "#FF5722", "image_overlay_opacity": 0.85 },
            { "id": "i2", "label": "Rounded", "image_url": "https://example.com/b.png", "image_shape": "rounded", "image_overlay_color": "#2196F3", "image_overlay_opacity": 0.85 },
            { "id": "i3", "label": "Square", "image_url": "https://example.com/c.png", "image_shape": "square", "image_overlay_color": "#22C55E", "image_overlay_opacity": 0.85 }
          ]
        }
        """)
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil ? .all : .never
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
        }
    }

    /// Selected-state styling — option "b" selected (green accent): selected gets the accent
    /// border + tinted bg; unselected get the neutral gray border (no more purple-border bug).
    func testSelectStacked_selectedState() throws {
        let view = try render("""
        {
          "id": "sel4", "type": "input_select",
          "field_config": { "display_style": "stacked" },
          "field_style": { "fill_color": "#22C55E" },
          "field_options": [
            { "id": "a", "value": "a", "label": "Casual", "subtitle": "Easy pace" },
            { "id": "b", "value": "b", "label": "Regular", "subtitle": "Recommended" },
            { "id": "c", "value": "c", "label": "Serious", "subtitle": "Intense" }
          ]
        }
        """, inputs: ["sel4": "b"])
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil ? .all : .never
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
        }
    }

    /// Selected-state image tint — "Picked" is selected → its image uses selected_image_overlay_color
    /// (green); "Other" is unselected → it uses the base image_overlay_color (gray). Parity with Android.
    func testSelectStacked_selectedImageTint() throws {
        let view = try render("""
        {
          "id": "sel5", "type": "input_select",
          "field_config": { "display_style": "stacked" },
          "field_options": [
            { "id": "p", "value": "p", "label": "Picked", "image_url": "https://example.com/a.png", "image_overlay_color": "#9CA3AF", "selected_image_overlay_color": "#22C55E", "image_overlay_opacity": 0.85, "selected_image_overlay_opacity": 0.85 },
            { "id": "q", "value": "q", "label": "Other", "image_url": "https://example.com/b.png", "image_overlay_color": "#9CA3AF", "image_overlay_opacity": 0.85 }
          ]
        }
        """, inputs: ["sel5": "p"])
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil ? .all : .never
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
        }
    }

    /// Image-fill tiles layout — 2×2 grid (image fills the tile, label overlaid over a scrim);
    /// "Lifting" selected with a yellow accent border. Parity with Android.
    func testSelect_imageTiles() throws {
        let view = try render("""
        {
          "id": "tiles1", "type": "input_select",
          "field_config": { "display_style": "image_tiles", "grid_columns": 2 },
          "field_style": { "fill_color": "#FACC15" },
          "field_options": [
            { "id": "run", "value": "run", "label": "Running", "image_url": "https://example.com/a.png", "image_overlay_color": "#E11D48", "image_overlay_opacity": 0.9 },
            { "id": "lift", "value": "lift", "label": "Lifting", "image_url": "https://example.com/b.png", "image_overlay_color": "#2563EB", "image_overlay_opacity": 0.9 },
            { "id": "yoga", "value": "yoga", "label": "Yoga", "image_url": "https://example.com/c.png", "image_overlay_color": "#7C3AED", "image_overlay_opacity": 0.9 },
            { "id": "swim", "value": "swim", "label": "Swimming", "image_url": "https://example.com/d.png", "image_overlay_color": "#059669", "image_overlay_opacity": 0.9 }
          ]
        }
        """, inputs: ["tiles1": "lift"])
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil ? .all : .never
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
        }
    }

    /// Bubble/chip layout — wrapping pill chips; "Running" selected (green fill), others bordered. Parity with Android.
    func testSelect_bubbleChips() throws {
        let view = try render("""
        {
          "id": "bubble1", "type": "input_select",
          "field_config": { "display_style": "bubble" },
          "field_style": { "fill_color": "#22C55E", "text_color": "#FFFFFF" },
          "field_options": [
            { "id": "running", "value": "running", "label": "Running" },
            { "id": "yoga", "value": "yoga", "label": "Yoga" },
            { "id": "cycling", "value": "cycling", "label": "Cycling" },
            { "id": "swimming", "value": "swimming", "label": "Swimming" },
            { "id": "boxing", "value": "boxing", "label": "Boxing" },
            { "id": "pilates", "value": "pilates", "label": "Pilates" }
          ]
        }
        """, inputs: ["bubble1": "running"])
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil ? .all : .never
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
        }
    }

    /// List / separators layout — borderless rows + hairline dividers; "Plus" selected (tint + ✓). Parity with Android.
    func testSelect_listSeparators() throws {
        let view = try render("""
        {
          "id": "list1", "type": "input_select",
          "field_config": { "display_style": "list" },
          "field_style": { "fill_color": "#3B82F6", "text_color": "#FFFFFF" },
          "field_options": [
            { "id": "free", "value": "free", "label": "Free", "subtitle": "Basic features" },
            { "id": "plus", "value": "plus", "label": "Plus", "subtitle": "More storage + priority support" },
            { "id": "pro", "value": "pro", "label": "Pro", "subtitle": "Everything, unlimited" },
            { "id": "team", "value": "team", "label": "Team", "subtitle": "For your whole organization" }
          ]
        }
        """, inputs: ["list1": "plus"])
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil ? .all : .never
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
        }
    }

    /// Custom field border + fill — input_text (green border) + input_email (blue border), dark fill. Parity with Android.
    func testField_customBorderFill() throws {
        let view = try renderMany([
            """
            { "id": "name", "type": "input_text", "label": "Full name", "field_placeholder": "Jane Doe",
              "field_style": { "border_color": "#22C55E", "background_color": "#1F2937", "text_color": "#FFFFFF", "placeholder_color": "#9CA3AF" } }
            """,
            """
            { "id": "email", "type": "input_email", "label": "Email", "field_placeholder": "jane@example.com",
              "field_style": { "border_color": "#3B82F6", "background_color": "#1F2937", "text_color": "#FFFFFF", "placeholder_color": "#9CA3AF" } }
            """,
        ])
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil ? .all : .never
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
        }
    }

    /// Selection animation glow — "Focused" selected with selection_animation:glow → accent glow halo. Parity with Android.
    func testSelect_selectionGlow() throws {
        let view = try render("""
        {
          "id": "glow1", "type": "input_select",
          "field_config": { "display_style": "stacked", "selection_animation": "glow" },
          "field_style": { "fill_color": "#22C55E" },
          "field_options": [
            { "id": "a", "value": "a", "label": "Calm", "subtitle": "Relaxing pace" },
            { "id": "b", "value": "b", "label": "Focused", "subtitle": "Steady progress" },
            { "id": "c", "value": "c", "label": "Intense", "subtitle": "Push hard" }
          ]
        }
        """, inputs: ["glow1": "b"])
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil ? .all : .never
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
        }
    }

    /// EPIC-2 — progress bar multi-color gradient fill (~80% filled, green→yellow→red). Parity with Android.
    func testProgress_gradient() throws {
        let view = try render("""
        {
          "id": "pb1", "type": "progress_bar",
          "progress_variant": "continuous", "total_segments": 5, "filled_segments": 4,
          "bar_height": 14, "corner_radius": 7, "track_color": "#374151",
          "bar_gradient_colors": ["#22C55E", "#EAB308", "#EF4444"]
        }
        """)
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] != nil ? .all : .never
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
        }
    }
}
