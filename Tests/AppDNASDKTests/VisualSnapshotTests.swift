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

    private func render(_ json: String) throws -> some View {
        let block = try JSONDecoder().decode(ContentBlock.self, from: Data(json.utf8))
        return ContentBlockRendererView(blocks: [block], onAction: { _, _ in })
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
        assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
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
        assertSnapshot(of: view, as: .image(layout: .sizeThatFits))
    }
}
