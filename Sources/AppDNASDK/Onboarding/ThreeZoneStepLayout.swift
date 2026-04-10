import SwiftUI

// MARK: - Three-Zone Step Layout
//
// Apple HIG pattern: ScrollView.safeAreaInset(edge: .bottom) for pinned CTA.
// Background uses .background() modifier, content stays in normal safe area.

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

    /// Scroll offset tracked for collapse_on_scroll blocks (Sprint 7).
    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        let visible = blocks.filter {
            evaluateVisibilityCondition($0.visibility_condition, responses: responses, hookData: hookData)
        }
        let (topBlocks, centerBlocks, bottomBlocks) = Self.partitionBlocks(visible)
        let onlyCenterContent = topBlocks.isEmpty && !centerBlocks.isEmpty

        Group {
            if onlyCenterContent {
                // Only center content (e.g. loading spinner) — vertically center it
                VStack {
                    Spacer()
                    zoneRenderer(blocks: centerBlocks)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Normal: top content scrollable, center below it
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        if !topBlocks.isEmpty {
                            zoneRenderer(blocks: topBlocks, scrollOffset: scrollOffset)
                                .padding(.top, 16)
                        }
                        if !centerBlocks.isEmpty {
                            zoneRenderer(blocks: centerBlocks, scrollOffset: scrollOffset)
                                .padding(.top, 20)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                }
                .coordinateSpace(name: "stepScroll")
                // Scroll offset tracker as overlay — doesn't participate in
                // VStack layout, so it can't push content or interfere with
                // keyboard avoidance scroll positioning.
                .overlay(alignment: .top) {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPrefKey.self,
                            value: -geo.frame(in: .named("stepScroll")).minY
                        )
                    }
                    .frame(height: 0)
                }
                .onPreferenceChange(ScrollOffsetPrefKey.self) { value in
                    scrollOffset = value
                }
                .scrollDismissesKeyboardCompat()
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !bottomBlocks.isEmpty {
                VStack(spacing: 8) {
                    zoneRenderer(blocks: bottomBlocks)
                }
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func zoneRenderer(blocks: [ContentBlock], scrollOffset: CGFloat = 0) -> some View {
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
            isZoneManaged: true,
            scrollOffset: scrollOffset
        )
        // Use ~8% of screen width for responsive margins across all devices
        .padding(.horizontal, max(24, UIScreen.main.bounds.width * 0.08))
    }

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

// MARK: - Scroll offset tracking

private struct ScrollOffsetPrefKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
