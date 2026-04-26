import XCTest
@testable import AppDNASDK

/// Unit tests for the OTP channel resolver used by `request_otp` / `verify_otp`
/// auth-action buttons. The resolver was extracted from the SwiftUI view as
/// `OtpChannelResolver` so the explicit-channel + auto-detect logic is testable
/// without instantiating the renderer.
///
/// The 14 strict-typed action cases themselves (login, register, etc.) live
/// inside a private SwiftUI view method in `OnboardingRenderer` — their
/// payload-shape behavior is verified via the Mac build bridge with a sample
/// host app + manual paywall flow.
final class OnboardingActionPassthroughTests: XCTestCase {

    // MARK: - Explicit channel

    func testExplicitChannelSms() {
        let blocks = [decode(blockJson(id: "phone", type: "input_phone"))]
        let result = OtpChannelResolver.resolve(
            actionValue: "sms",
            blocks: blocks,
            inputValues: ["phone": "+15551234567"],
        )
        XCTAssertEqual(result.channel, "sms")
        XCTAssertEqual(result.recipient, "+15551234567")
    }

    func testExplicitChannelEmail() {
        let blocks = [decode(blockJson(id: "email", type: "input_email"))]
        let result = OtpChannelResolver.resolve(
            actionValue: "email",
            blocks: blocks,
            inputValues: ["email": "user@example.com"],
        )
        XCTAssertEqual(result.channel, "email")
        XCTAssertEqual(result.recipient, "user@example.com")
    }

    func testExplicitChannelWhatsappPullsFromPhoneInput() {
        let blocks = [decode(blockJson(id: "phone", type: "input_phone"))]
        let result = OtpChannelResolver.resolve(
            actionValue: "whatsapp",
            blocks: blocks,
            inputValues: ["phone": "+15551234567"],
        )
        XCTAssertEqual(result.channel, "whatsapp")
        XCTAssertEqual(result.recipient, "+15551234567")
    }

    func testExplicitChannelVoicePullsFromPhoneInput() {
        let blocks = [decode(blockJson(id: "phone", type: "input_phone"))]
        let result = OtpChannelResolver.resolve(
            actionValue: "voice",
            blocks: blocks,
            inputValues: ["phone": "+15551234567"],
        )
        XCTAssertEqual(result.channel, "voice")
        XCTAssertEqual(result.recipient, "+15551234567")
    }

    func testExplicitChannelIsCaseInsensitive() {
        let blocks = [decode(blockJson(id: "email", type: "input_email"))]
        let result = OtpChannelResolver.resolve(
            actionValue: "EMAIL",
            blocks: blocks,
            inputValues: ["email": "user@example.com"],
        )
        XCTAssertEqual(result.channel, "email")
    }

    func testExplicitChannelUnknownStringFallsThroughToAutoDetect() {
        let blocks = [decode(blockJson(id: "email", type: "input_email"))]
        let result = OtpChannelResolver.resolve(
            actionValue: "carrier_pigeon",
            blocks: blocks,
            inputValues: ["email": "user@example.com"],
        )
        // Unknown channel is ignored; auto-detect picks the email field.
        XCTAssertEqual(result.channel, "email")
        XCTAssertEqual(result.recipient, "user@example.com")
    }

    // MARK: - Auto-detect

    func testAutoDetectPhoneWhenOnlyPhoneInputPresent() {
        let blocks = [decode(blockJson(id: "phone", type: "input_phone"))]
        let result = OtpChannelResolver.resolve(
            actionValue: nil,
            blocks: blocks,
            inputValues: ["phone": "+15551234567"],
        )
        XCTAssertEqual(result.channel, "sms")
        XCTAssertEqual(result.recipient, "+15551234567")
    }

    func testAutoDetectEmailWhenOnlyEmailInputPresent() {
        let blocks = [decode(blockJson(id: "email", type: "input_email"))]
        let result = OtpChannelResolver.resolve(
            actionValue: nil,
            blocks: blocks,
            inputValues: ["email": "user@example.com"],
        )
        XCTAssertEqual(result.channel, "email")
        XCTAssertEqual(result.recipient, "user@example.com")
    }

    // MARK: - Ambiguous → nil

    func testAmbiguousWhenBothEmailAndPhonePresent() {
        let blocks = [
            decode(blockJson(id: "email", type: "input_email")),
            decode(blockJson(id: "phone", type: "input_phone")),
        ]
        let result = OtpChannelResolver.resolve(
            actionValue: nil,
            blocks: blocks,
            inputValues: ["email": "user@example.com", "phone": "+15551234567"],
        )
        XCTAssertNil(result.channel, "Step has both email + phone — host must specify channel")
        XCTAssertNil(result.recipient)
    }

    func testNilWhenNeitherEmailNorPhonePresent() {
        let blocks = [decode(blockJson(id: "name", type: "input_text"))]
        let result = OtpChannelResolver.resolve(
            actionValue: nil,
            blocks: blocks,
            inputValues: ["name": "Alex"],
        )
        XCTAssertNil(result.channel)
        XCTAssertNil(result.recipient)
    }

    func testAmbiguousWhenMultiplePhoneInputsPresent() {
        let blocks = [
            decode(blockJson(id: "phone1", type: "input_phone")),
            decode(blockJson(id: "phone2", type: "input_phone")),
        ]
        let result = OtpChannelResolver.resolve(
            actionValue: nil,
            blocks: blocks,
            inputValues: ["phone1": "+1", "phone2": "+2"],
        )
        XCTAssertNil(result.channel, "Two phone inputs — auto-detect should not guess which")
    }

    // MARK: - Recipient absent / empty

    func testRecipientNilWhenInputValueMissing() {
        let blocks = [decode(blockJson(id: "phone", type: "input_phone"))]
        let result = OtpChannelResolver.resolve(
            actionValue: "sms",
            blocks: blocks,
            inputValues: [:],
        )
        XCTAssertEqual(result.channel, "sms", "Channel still resolved from explicit actionValue")
        XCTAssertNil(result.recipient, "Recipient is nil when the input field has no value yet")
    }

    func testRecipientFallsBackToBlockIdWhenFieldIdAbsent() {
        // Block JSON without an explicit field_id — should fall back to id for keying.
        let json = """
        {"id": "phone", "type": "input_phone"}
        """
        let block = try! JSONDecoder().decode(ContentBlock.self, from: Data(json.utf8))
        let result = OtpChannelResolver.resolve(
            actionValue: "sms",
            blocks: [block],
            inputValues: ["phone": "+15551234567"],
        )
        XCTAssertEqual(result.recipient, "+15551234567")
    }

    // MARK: - Auth action policy (delegate-required guard)

    func testAllAuthActionsRequireDelegate() {
        // Every strict-typed auth action — entry + lifecycle + the legacy
        // social_login — must be in the delegate-required set so the SDK
        // refuses to silently advance past credential collection without a
        // host-side handler.
        let entry: [String] = [
            "login", "register", "reset_password", "magic_link",
            "request_otp", "verify_otp", "verify_email", "resend_verification",
            "enable_biometric",
        ]
        let lifecycle: [String] = [
            "logout", "change_password", "set_new_password",
            "delete_account", "update_profile",
        ]
        for action in entry + lifecycle + ["social_login"] {
            XCTAssertTrue(
                AuthActionPolicy.delegateRequiredActions.contains(action),
                "Action '\(action)' must be guarded by AuthActionPolicy",
            )
        }
    }

    func testFlowControlActionsDoNotRequireDelegate() {
        // Flow-control actions advance the step on their own — they MUST NOT
        // be in the delegate-required set or hosts that don't implement a
        // delegate would get stuck on every step.
        for action in ["next", "skip", "link", "permission"] {
            XCTAssertFalse(
                AuthActionPolicy.delegateRequiredActions.contains(action),
                "Action '\(action)' must NOT require a delegate",
            )
        }
    }

    // MARK: - Helpers

    private func blockJson(id: String, type: String) -> String {
        """
        {"id": "\(id)", "type": "\(type)", "field_id": "\(id)"}
        """
    }

    private func decode(_ json: String) -> ContentBlock {
        try! JSONDecoder().decode(ContentBlock.self, from: Data(json.utf8))
    }
}
