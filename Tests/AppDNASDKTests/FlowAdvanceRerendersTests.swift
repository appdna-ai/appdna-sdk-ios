import XCTest
import SwiftUI
@testable import AppDNASDK

/// 🔴 iOS PRESENTED THE FIRST SCREEN OF A FLOW AND NEVER MOVED.
///
/// `ScreenPresenter.presentFlow` read `flowManager.currentScreen` ONCE, built a `SectionContext` from
/// that snapshot, and handed the resulting renderer to `present(config:context:)`. So `handleAction`
/// advanced `currentScreenIndex` — and nothing re-rendered. A multi-screen flow showed screen 1 forever
/// and "Next" was a dead button. Android had the mirror-image bug (its `showFlow` rendered nothing at
/// all); both are fixed.
///
/// `FlowManager` was an `ObservableObject` with `@Published var currentScreenIndex` the whole time. The
/// observability existed; the view simply never observed it.
///
/// A UIKit/SwiftUI presentation cannot be driven from a unit test, so this asserts the two facts the
/// re-render actually depends on — the ones that were false:
///
///   1. advancing the flow CHANGES the manager's published state (so an observer would be notified);
///   2. `currentScreen` follows the index, rather than being pinned to the first screen.
///
/// If either regressed, no amount of `@ObservedObject` would help. The presentation itself is covered by
/// the device pass.
final class FlowAdvanceRerendersTests: XCTestCase {

    /// The configs are `Codable`, so build them the way the SDK does — from the JSON the console emits.
    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func makeManager() throws -> FlowManager {
        let flow: FlowConfig = try decode("""
        {
          "id": "flow_welcome",
          "name": "Welcome",
          "start_screen_id": "s1",
          "screens": [
            { "screen_id": "s1" },
            { "screen_id": "s2" },
            { "screen_id": "s3" }
          ]
        }
        """)
        let screens: [String: ScreenConfig] = [
            "s1": try decode(#"{"id":"s1","name":"One","sections":[]}"#),
            "s2": try decode(#"{"id":"s2","name":"Two","sections":[]}"#),
            "s3": try decode(#"{"id":"s3","name":"Three","sections":[]}"#),
        ]
        return FlowManager(flowConfig: flow, screens: screens)
    }

    func testAdvancingTheFlowMovesCurrentScreen() throws {
        let manager = try makeManager()

        XCTAssertEqual(manager.currentScreenIndex, 0)
        XCTAssertEqual(manager.currentScreen?.id, "s1")

        manager.handleAction(.next)

        // The bug: `currentScreenIndex` moved and `currentScreen` did not follow it — or the presented
        // view held the old snapshot regardless. Both must track.
        XCTAssertEqual(manager.currentScreenIndex, 1, "the flow did not advance")
        XCTAssertEqual(manager.currentScreen?.id, "s2", "currentScreen is pinned to the first screen")

        manager.handleAction(.next)
        XCTAssertEqual(manager.currentScreen?.id, "s3")

        manager.handleAction(.back)
        XCTAssertEqual(manager.currentScreen?.id, "s2", "back did not move the flow")
    }

    /// The published property is what a SwiftUI observer subscribes to. If advancing stopped publishing,
    /// the view would silently freeze again — the exact failure, one layer down.
    func testAdvancingPublishesAChange() throws {
        let manager = try makeManager()

        let published = expectation(description: "currentScreenIndex publishes on advance")
        let cancellable = manager.$currentScreenIndex
            .dropFirst()  // the initial value
            .sink { index in
                XCTAssertEqual(index, 1)
                published.fulfill()
            }

        manager.handleAction(.next)

        wait(for: [published], timeout: 1.0)
        cancellable.cancel()
    }
}
