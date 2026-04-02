import SwiftUI

// MARK: - Three-Zone Step Layout
//
// Partitions content blocks into three vertical zones based on `zone` property:
//   TOP    → scrollable content area (headings, text, inputs)
//   CENTER → centered in remaining vertical space (gauges, images, pickers)
//   BOTTOM → pinned to screen bottom, always visible (CTA buttons, legal text)
//
// Falls back to `vertical_align` for legacy data without explicit `zone`.

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

    @State private var bottomHeight: CGFloat = 0
    @State private var centerHeight: CGFloat = 0

    var body: some View {
        let visible = blocks.filter {
            evaluateVisibilityCondition($0.visibility_condition, responses: responses, hookData: hookData)
        }
        let (topBlocks, centerBlocks, bottomBlocks) = Self.partitionBlocks(visible)
        let hasBottom = !bottomBlocks.isEmpty
        let hasCenter = !centerBlocks.isEmpty

        GeometryReader { geometry in
            let availableHeight = geometry.size.height
            let topMaxHeight = availableHeight - bottomHeight - centerHeight - (hasCenter ? 16 : 0)

            VStack(spacing: 0) {
                // ── TOP ZONE ──
                if !topBlocks.isEmpty {
                    ScrollView(showsIndicators: false) {
                        zoneRenderer(blocks: topBlocks)
                            .padding(.top, 16)
                    }
                    .frame(maxHeight: (hasBottom || hasCenter) ? max(topMaxHeight, 100) : nil)
                }

                if hasCenter {
                    Spacer(minLength: 4)
                    zoneRenderer(blocks: centerBlocks)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: CenterHeightKey.self, value: g.size.height)
                        })
                    Spacer(minLength: 4)
                } else if hasBottom {
                    Spacer(minLength: 0)
                }

                // ── BOTTOM ZONE ──
                if hasBottom {
                    zoneRenderer(blocks: bottomBlocks)
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 4 : 16)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: BottomHeightKey.self, value: g.size.height)
                        })
                }
            }
            .frame(width: geometry.size.width, height: availableHeight)
            .onPreferenceChange(BottomHeightKey.self) { bottomHeight = $0 }
            .onPreferenceChange(CenterHeightKey.self) { centerHeight = $0 }
        }
        .ignoresSafeArea(.keyboard)
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
            case "center":
                center.append(block)
            case "bottom":
                bottom.append(block)
            default:
                top.append(block)
            }
        }

        return (top, center, bottom)
    }
}

// MARK: - Preference Keys for measuring zone heights

private struct BottomHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CenterHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
