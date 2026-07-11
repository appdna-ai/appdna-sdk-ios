import XCTest
@testable import AppDNASDK

/// SPEC-070-B B2 — `deep_link_handled` on iOS, and the push-tap → deep-link route that never existed.
///
/// THE BUG (two halves):
///   1. iOS never emitted `deep_link_handled`. Android has always emitted it
///      (`AppDNAModules.kt:676`), so every deep-link-attributed session was missing from iOS
///      analytics — a hole in the attribution data, not a cosmetic gap.
///   2. iOS's push tap handler routed ONLY `show_screen`. A push whose action was a deep link did
///      nothing at all: no navigation, no delegate call, no event. Android routes it
///      (`AppDNA.kt:1391/1397`).
///
/// Event name and props are Android's verbatim: `deep_link_handled` / `{"url": <absolute string>}`.
final class DeepLinkHandledTests: XCTestCase {

    private final class SpyDeepLinkDelegate: AppDNADeepLinkDelegate {
        private(set) var url: URL?
        private(set) var params: [String: String] = [:]
        func onDeepLinkReceived(url: URL, params: [String: String]) {
            self.url = url
            self.params = params
        }
    }

    // MARK: - The emission

    func testHandleURLEmitsDeepLinkHandledWithTheUrlProp() throws {
        let module = AppDNA.DeepLinksModule()
        let delegate = SpyDeepLinkDelegate()
        module.setDelegate(delegate)

        var events: [(String, [String: Any])] = []
        module.trackEvent = { name, props in events.append((name, props)) }

        let url = try XCTUnwrap(URL(string: "myapp://workout/123?src=push"))
        module.handleURL(url)

        // The host is told.
        XCTAssertEqual(delegate.url, url)
        XCTAssertEqual(delegate.params["src"], "push")

        // Analytics sees it — this is the half that never happened on iOS.
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].0, "deep_link_handled")
        XCTAssertEqual(events[0].1["url"] as? String, "myapp://workout/123?src=push")
        // Exactly one prop — Android sends `mapOf("url" to url)` and nothing else.
        XCTAssertEqual(events[0].1.count, 1)
    }

    /// The contract lives in one place so the two platforms cannot drift.
    func testAnalyticsContractMatchesAndroid() throws {
        XCTAssertEqual(DeepLinkAnalytics.event, "deep_link_handled")
        let url = try XCTUnwrap(URL(string: "myapp://home"))
        XCTAssertEqual(DeepLinkAnalytics.props(url: url)["url"] as? String, "myapp://home")
    }

    /// A vetoed URL emits nothing — a suppressed deep link is not a handled deep link.
    func testVetoedURLEmitsNothing() throws {
        let module = AppDNA.DeepLinksModule()
        let delegate = SpyDeepLinkDelegate()
        module.setDelegate(delegate)

        var events: [(String, [String: Any])] = []
        module.trackEvent = { name, props in events.append((name, props)) }
        module.asyncShouldOpen = { _, _ in false }

        module.handleURL(try XCTUnwrap(URL(string: "myapp://blocked")))

        let settled = expectation(description: "veto task settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2.0)

        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(delegate.url)
    }

    // MARK: - Push tap routing

    /// A push whose body action is a deep link now routes to the deep-link module. Before, the
    /// handler only matched `show_screen`, so this tap fell on the floor.
    func testPushBodyDeepLinkActionRoutesToDeepLink() {
        let payload = PushPayload(
            pushId: "p1",
            title: "t",
            body: "b",
            action: PushAction(type: "deep_link", value: "myapp://workout/123")
        )
        XCTAssertEqual(
            PushTapRouter.route(payload: payload, tappedActionId: nil),
            .deepLink("myapp://workout/123")
        )
    }

    /// A tapped BUTTON routes on that button's own action, not the body's — otherwise every button
    /// would go to the same place.
    func testTappedButtonRoutesOnItsOwnAction() {
        let payload = PushPayload(
            pushId: "p1",
            title: "t",
            body: "b",
            action: PushAction(type: "show_screen", value: "home"),
            actions: [
                PushAction(type: "deep_link", value: "myapp://offer", id: "btn_offer", label: "Offer"),
                PushAction(type: "show_screen", value: "settings", id: "btn_settings", label: "Settings"),
            ]
        )
        XCTAssertEqual(
            PushTapRouter.route(payload: payload, tappedActionId: "btn_offer"),
            .deepLink("myapp://offer")
        )
        XCTAssertEqual(
            PushTapRouter.route(payload: payload, tappedActionId: "btn_settings"),
            .showScreen("settings")
        )
        // Body tap (no button) falls back to the body action — unchanged behaviour.
        XCTAssertEqual(
            PushTapRouter.route(payload: payload, tappedActionId: nil),
            .showScreen("home")
        )
    }

    func testOpenUrlIsTreatedAsADeepLink() {
        let payload = PushPayload(
            pushId: "p1", title: "t", body: "b",
            action: PushAction(type: "open_url", value: "https://example.com/promo")
        )
        XCTAssertEqual(
            PushTapRouter.route(payload: payload, tappedActionId: nil),
            .deepLink("https://example.com/promo")
        )
    }

    func testNonRoutableActionsAreIgnored() {
        let dismiss = PushPayload(
            pushId: "p1", title: "t", body: "b",
            action: PushAction(type: "dismiss", value: "x")
        )
        XCTAssertEqual(PushTapRouter.route(payload: dismiss, tappedActionId: nil), .ignored)

        // A deep-link action with no target is not a destination.
        let empty = PushPayload(
            pushId: "p1", title: "t", body: "b",
            action: PushAction(type: "deep_link", value: "")
        )
        XCTAssertEqual(PushTapRouter.route(payload: empty, tappedActionId: nil), .ignored)

        // No action at all.
        let none = PushPayload(pushId: "p1", title: "t", body: "b")
        XCTAssertEqual(PushTapRouter.route(payload: none, tappedActionId: nil), .ignored)
    }
}
