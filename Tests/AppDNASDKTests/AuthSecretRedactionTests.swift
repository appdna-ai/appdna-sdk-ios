import XCTest
@testable import AppDNASDK

/// 🔴 EVERY LOGIN ATTEMPT UPLOADED THE END-USER'S PLAINTEXT PASSWORD INTO OUR DATA WAREHOUSE.
///
/// On a `login` / `register` / `change_password` step, `handleStepCompleted` took the raw field map the
/// user had just typed — password included — and gave it to two sinks:
///
///   1. `responses` → `SessionDataStore` (UserDefaults, plaintext, on disk, on every attempt), which
///      `TemplateEngine.buildContext()` folds into the `{{…}}` namespace. That is the same path that
///      once rendered one user's name into another user's paywall copy, so the password was one
///      `{{onboarding.password}}` away from being *displayed*.
///
///   2. `onStepCompleted` → the `onboarding_step_completed` event, whose properties carry
///      `"selection_data": data` verbatim. That event is enqueued, uploaded, and lands in
///      `raw.sdk_events` — and stays there.
///
/// The host is the only party that needs the credentials, and it still gets them in full: the delegate's
/// `onBeforeStepAdvance` is handed the raw `stepData`. Nobody else does.
///
/// These tests decode the step from the JSON the CONSOLE actually publishes, rather than hand-building a
/// model — so they prove the real wire shape is what gets redacted, not a shape I invented to pass.
final class AuthSecretRedactionTests: XCTestCase {

    /// A login step exactly as the console publishes it: an email input, a password input, a button.
    /// `input_password` is the schema's own block type (`flow.schema.ts:379`).
    private func loginStep() throws -> OnboardingStep {
        let json = """
        {
          "id": "step_login",
          "type": "custom",
          "config": {
            "content_blocks": [
              { "id": "b1", "type": "input_email",    "field_id": "email" },
              { "id": "b2", "type": "input_password", "field_id": "password" },
              { "id": "b3", "type": "button", "action": "login" }
            ]
          }
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(OnboardingStep.self, from: json)
    }

    /// A form step whose password field is declared by FIELD type rather than block type — the other
    /// way the console can express the same thing (`FORM_FIELD_TYPES` includes `password`).
    private func formStepWithPasswordField() throws -> OnboardingStep {
        let json = """
        {
          "id": "step_register",
          "type": "form",
          "config": {
            "fields": [
              { "id": "email",    "type": "email",    "label": "Email" },
              { "id": "passcode", "type": "password", "label": "Choose a password" }
            ]
          }
        }
        """.data(using: .utf8)!
        return try JSONDecoder().decode(OnboardingStep.self, from: json)
    }

    func testPasswordBlockValueIsStrippedAndEverythingElseSurvives() throws {
        let step = try loginStep()
        let typed: [String: Any] = [
            "email": "alice@example.com",
            "password": "hunter2",
            "action": "login",
        ]

        let safe = AuthSecretRedactor.redact(typed, in: step)

        XCTAssertNil(
            safe?["password"],
            "the user's password survived redaction — it would be persisted to UserDefaults, folded " +
            "into the {{…}} template namespace, AND uploaded to raw.sdk_events in selection_data"
        )
        XCTAssertEqual(safe?["email"] as? String, "alice@example.com", "redaction ate a non-secret field")
        XCTAssertEqual(safe?["action"] as? String, "login", "redaction ate the action")
    }

    /// The field id is `passcode`, not `password`. A name-based guess (`id.contains("password")`) would
    /// sail straight past this and leak it. The discriminator is the declared TYPE.
    func testAPasswordFieldNotNamedPasswordIsStillRedacted() throws {
        let step = try formStepWithPasswordField()
        let typed: [String: Any] = ["email": "bob@example.com", "passcode": "s3cret!"]

        let safe = AuthSecretRedactor.redact(typed, in: step)

        XCTAssertNil(
            safe?["passcode"],
            "a password field called `passcode` leaked — the redactor is matching on the field NAME " +
            "rather than its declared type"
        )
        XCTAssertEqual(safe?["email"] as? String, "bob@example.com")
    }

    /// …and the converse: a non-secret field whose id merely CONTAINS the word must NOT be eaten. A
    /// substring oracle would redact this one, silently dropping a real answer from the funnel.
    func testANonSecretFieldWhoseNameContainsPasswordIsKept() throws {
        let json = """
        {
          "id": "step_hint",
          "type": "form",
          "config": {
            "fields": [{ "id": "password_hint", "type": "text", "label": "Password hint" }]
          }
        }
        """.data(using: .utf8)!
        let step = try JSONDecoder().decode(OnboardingStep.self, from: json)

        let safe = AuthSecretRedactor.redact(["password_hint": "my dog"], in: step)

        XCTAssertEqual(
            safe?["password_hint"] as? String, "my dog",
            "a plain text field was redacted because its NAME contains \\\"password\\\" — that is a " +
            "substring oracle, and it silently drops real user answers"
        )
    }

    /// A step with no secret fields must pass through untouched — redaction must not become a tax on
    /// every ordinary step in the flow.
    func testAStepWithNoSecretsIsUnchanged() throws {
        let json = """
        { "id": "s", "type": "question", "config": { "fields": [
            { "id": "goal", "type": "text", "label": "Goal" }] } }
        """.data(using: .utf8)!
        let step = try JSONDecoder().decode(OnboardingStep.self, from: json)

        let data: [String: Any] = ["goal": "lose_weight", "action": "next"]
        let safe = AuthSecretRedactor.redact(data, in: step)

        XCTAssertEqual(safe?.count, 2)
        XCTAssertEqual(safe?["goal"] as? String, "lose_weight")
    }

    /// The redactor must find the secret through BOTH declaration styles at once — a step may carry
    /// content blocks and form fields together.
    func testSecretIdsAreCollectedFromBlocksAndFieldsAlike() throws {
        XCTAssertEqual(try AuthSecretRedactor.secretFieldIds(in: loginStep()), ["password"])
        XCTAssertEqual(try AuthSecretRedactor.secretFieldIds(in: formStepWithPasswordField()), ["passcode"])
    }

    /// 🔴 A PASSWORD NESTED IN A `row` STILL SHIPPED TO THE WAREHOUSE — the scan was top-level only.
    /// The renderer writes nested inputs into the SAME value map, so the redactor must walk the tree.
    func testAPasswordNestedInsideARowIsRedacted() throws {
        let json = """
        {
          "id": "step_login_row",
          "type": "custom",
          "config": {
            "content_blocks": [
              { "id": "row1", "type": "row", "children": [
                { "id": "b1", "type": "input_email",    "field_id": "email" },
                { "id": "b2", "type": "input_password", "field_id": "password" }
              ] },
              { "id": "b3", "type": "button", "action": "login" }
            ]
          }
        }
        """.data(using: .utf8)!
        let step = try JSONDecoder().decode(OnboardingStep.self, from: json)

        XCTAssertEqual(try AuthSecretRedactor.secretFieldIds(in: step), ["password"])
        let safe = AuthSecretRedactor.redact(["email": "a@b.com", "password": "hunter2"], in: step)
        XCTAssertNil(safe?["password"], "a password nested inside a row block leaked to the warehouse")
        XCTAssertEqual(safe?["email"] as? String, "a@b.com")
    }

    /// ...and one nested two levels deep, in `stack_children` — the other nesting key.
    func testAPasswordNestedTwoLevelsDeepIsRedacted() throws {
        let json = """
        {
          "id": "s", "type": "custom",
          "config": { "content_blocks": [
            { "id": "outer", "type": "stack", "stack_children": [
              { "id": "inner", "type": "row", "children": [
                { "id": "p", "type": "input_password", "field_id": "pw" }
              ] }
            ] }
          ] }
        }
        """.data(using: .utf8)!
        let step = try JSONDecoder().decode(OnboardingStep.self, from: json)
        XCTAssertEqual(try AuthSecretRedactor.secretFieldIds(in: step), ["pw"])
    }

    /// 🔴 THE OTP CODE WAS NOT REDACTED. A `verify_otp` step captures the one-time code in an
    /// `otp_input` block; it shipped to `raw.sdk_events` in the clear.
    func testTheOtpCodeIsRedacted() throws {
        let json = """
        {
          "id": "step_verify", "type": "custom",
          "config": { "content_blocks": [
            { "id": "b1", "type": "otp_input", "field_id": "code" },
            { "id": "b2", "type": "button", "action": "verify_otp" }
          ] }
        }
        """.data(using: .utf8)!
        let step = try JSONDecoder().decode(OnboardingStep.self, from: json)

        let safe = AuthSecretRedactor.redact(
            ["code": "418302", "action": "verify_otp", "channel": "sms"], in: step
        )
        XCTAssertNil(safe?["code"], "the one-time code shipped to the warehouse unredacted")
        XCTAssertEqual(safe?["action"] as? String, "verify_otp", "non-secret metadata must survive")
    }
}
