import XCTest
@testable import AppDNASDK

/// The server has always sent an `actions` array and the SDK has always REGISTERED those buttons with
/// `UNUserNotificationCenter` — but the payload handed to the host exposed a single `action`, so a
/// host could see which button id was tapped and had no way to learn what that button meant.
final class PushPayloadParserTests: XCTestCase {

    private let userInfoWithActions: [AnyHashable: Any] = [
        "push_id": "push_promo_55jx",
        "actions": [
            [
                "id": "view",
                "label": "View offer",
                "action_type": "deep_link",
                "action_value": "myapp://paywall/promo",
            ],
            [
                "id": "dismiss",
                "label": "Not now",
                "action_type": "dismiss",
            ],
        ],
    ]

    func testActionsArrayIsParsedInOrder() {
        let payload = PushPayloadParser.parse(
            userInfo: userInfoWithActions,
            title: "Limited offer",
            body: "20% off ends in 1 hour"
        )

        XCTAssertEqual(payload.pushId, "push_promo_55jx")
        XCTAssertEqual(payload.actions.count, 2)

        XCTAssertEqual(payload.actions[0].id, "view")
        XCTAssertEqual(payload.actions[0].label, "View offer")
        XCTAssertEqual(payload.actions[0].type, "deep_link")
        XCTAssertEqual(payload.actions[0].value, "myapp://paywall/promo")

        XCTAssertEqual(payload.actions[1].id, "dismiss")
        XCTAssertEqual(payload.actions[1].type, "dismiss")
        // "dismiss" carries no target — an absent action_value is not a malformed button.
        XCTAssertEqual(payload.actions[1].value, "")
    }

    /// Source compat for hosts reading the pre-existing single `action`.
    func testSingleActionFallsBackToFirstButton() {
        let payload = PushPayloadParser.parse(userInfo: userInfoWithActions, title: "t", body: "b")
        XCTAssertEqual(payload.action?.type, "deep_link")
        XCTAssertEqual(payload.action?.value, "myapp://paywall/promo")
    }

    /// An explicit body action always wins over the first button.
    func testExplicitBodyActionWinsOverFirstButton() {
        var userInfo = userInfoWithActions
        userInfo["action"] = ["type": "show_screen", "value": "screen_home"]

        let payload = PushPayloadParser.parse(userInfo: userInfo, title: "t", body: "b")

        XCTAssertEqual(payload.action?.type, "show_screen")
        XCTAssertEqual(payload.action?.value, "screen_home")
        XCTAssertEqual(payload.actions.count, 2)
    }

    func testPayloadWithoutActionsIsEmptyNotNil() {
        let payload = PushPayloadParser.parse(
            userInfo: ["push_id": "p1", "action": ["type": "deep_link", "value": "myapp://home"]],
            title: "t",
            body: "b"
        )
        XCTAssertTrue(payload.actions.isEmpty)
        XCTAssertEqual(payload.action?.value, "myapp://home")
    }

    /// A button with no `action_type` has nothing to route to — it must not become an action with a
    /// blank type that a host would switch on.
    func testButtonWithoutActionTypeIsSkipped() {
        let payload = PushPayloadParser.parse(
            userInfo: ["push_id": "p1", "actions": [["id": "x", "label": "X"]]],
            title: "t",
            body: "b"
        )
        XCTAssertTrue(payload.actions.isEmpty)
        XCTAssertNil(payload.action)
    }
}
