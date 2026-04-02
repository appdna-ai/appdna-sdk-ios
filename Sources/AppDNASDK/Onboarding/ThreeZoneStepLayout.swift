import SwiftUI

// MARK: - Three-Zone Step Layout
//
// Apple HIG pattern: ScrollView.safeAreaInset(edge: .bottom) for pinned CTA.
// Background sibling has .ignoresSafeArea(), content layer does NOT.
// This is Apple's first-party solution for sticky footers (WWDC 2021).

struct ThreeZoneStepLayout: View {
    let blocks: [ContentBlock]
    let onAction: (_ action: String, _ actionValue: String?) -> Void
    @Binding var toggleValues: [String: Bool]
    var loc: ((String, String) -> String)? = nil
    var responses: [String: Any] = [:]
    var hookData: [String: Any]? = nil
    @Binding var inputValues: [String: Any]
    var currentStepIndex: Int = 0
    var totalSteps: Int = 1

    var body: some View {
        let visible = blocks.filter {
            evaluateVisibilityCondition($0.visibility_condition, responses: responses, hookData: hookData)
        }
        let (topBlocks, centerBlocks, bottomBlocks) = Self.partitionBlocks(visible)

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                // ── TOP ZONE ──
                if !topBlocks.isEmpty {
                    zoneRenderer(blocks: topBlocks)
                        .padding(.top, 16)
                }

                // ── CENTER ZONE ──
                if !centerBlocks.isEmpty {
                    zoneRenderer(blocks: centerBlocks)
                        .padding(.top, 20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            // ── BOTTOM ZONE: pinned to screen bottom ──
            // safeAreaInset automatically:
            // 1. Pins this view at the bottom
            // 2. Adds content inset to ScrollView so content isn't hidden
            if !bottomBlocks.isEmpty {
                VStack(spacing: 8) {
                    zoneRenderer(blocks: bottomBlocks)
                }
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func zoneRenderer(blocks: [ContentBlock]) -> some View {
        ContentBlockRendererView(
            blocks: blocks,
            onAction: onAction,
            toggleValues: $toggleValues,
            loc: loc,
            responses: responses,
            hookData: hookData,
            inputValues: $inputValues,
            currentStepIndex: currentStepIndex,
            totalSteps: totalSteps,
            isZoneManaged: true
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Block Partitioning

    static func partitionBlocks(_ blocks: [ContentBlock]) -> (top: [ContentBlock], center: [ContentBlock], bottom: [ContentBlock]) {
        var top: [ContentBlock] = []
        var center: [ContentBlock] = []
        var bottom: [ContentBlock] = []
        for block in blocks {
            let effectiveZone = block.zone ?? block.vertical_align ?? "top"
            switch effectiveZone {
            case "center": center.append(block)
            case "bottom": bottom.append(block)
            default: top.append(block)
            }
        }
        return (top, center, bottom)
    }
}
