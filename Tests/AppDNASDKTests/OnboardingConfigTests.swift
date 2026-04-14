import XCTest
@testable import AppDNASDK

final class OnboardingConfigTests: XCTestCase {

    // MARK: - Step types

    func testStepTypeWelcome() {
        let step = OnboardingStep(
            id: "step_1",
            type: .welcome,
            config: StepConfig(
                title: "Welcome to FitLife",
                subtitle: "Your personal fitness companion",
                image_url: "https://example.com/hero.png",
                cta_text: "Get Started",
                skip_enabled: false,
                options: nil,
                selection_mode: nil,
                items: nil,
                layout: nil
            ),
            hook: nil
        )
        XCTAssertEqual(step.type, .welcome)
        XCTAssertEqual(step.config.title, "Welcome to FitLife")
        XCTAssertEqual(step.config.skip_enabled, false)
    }

    func testStepTypeQuestion() {
        let step = OnboardingStep(
            id: "step_2",
            type: .question,
            config: StepConfig(
                title: "What's your goal?",
                subtitle: nil,
                image_url: nil,
                cta_text: "Continue",
                skip_enabled: nil,
                options: [
                    QuestionOption(id: "lose_weight", label: "Lose Weight", icon: "🏃", subtitle: nil),
                    QuestionOption(id: "build_muscle", label: "Build Muscle", icon: "💪", subtitle: nil),
                ],
                selection_mode: .single,
                items: nil,
                layout: nil
            ),
            hook: nil
        )
        XCTAssertEqual(step.type, .question)
        XCTAssertEqual(step.config.options?.count, 2)
        XCTAssertEqual(step.config.selection_mode, .single)
    }

    func testStepTypeValueProp() {
        let step = OnboardingStep(
            id: "step_3",
            type: .value_prop,
            config: StepConfig(
                title: "Here's what you'll get",
                subtitle: nil,
                image_url: nil,
                cta_text: "Continue",
                skip_enabled: nil,
                options: nil,
                selection_mode: nil,
                items: [
                    ValuePropItem(icon: "📊", title: "Personalized Plans", subtitle: "Tailored to your goals"),
                ],
                layout: nil
            ),
            hook: nil
        )
        XCTAssertEqual(step.type, .value_prop)
        XCTAssertEqual(step.config.items?.count, 1)
        XCTAssertEqual(step.config.items?.first?.title, "Personalized Plans")
    }

    func testStepTypeCustom() {
        let step = OnboardingStep(
            id: "step_4",
            type: .custom,
            config: StepConfig(
                title: nil,
                subtitle: nil,
                image_url: nil,
                cta_text: nil,
                skip_enabled: nil,
                options: nil,
                selection_mode: nil,
                items: nil,
                layout: ["type": AnyCodable("stack")]
            ),
            hook: nil
        )
        XCTAssertEqual(step.type, .custom)
        XCTAssertNotNil(step.config.layout)
    }

    // MARK: - Flow config

    func testOnboardingFlowSettings() {
        let flow = OnboardingFlowConfig(
            id: "flow_123",
            name: "Default Onboarding",
            version: 3,
            steps: [],
            settings: OnboardingSettings(
                show_progress: true,
                allow_back: true,
                skip_to_step: nil
            )
        )
        XCTAssertEqual(flow.id, "flow_123")
        XCTAssertEqual(flow.name, "Default Onboarding")
        XCTAssertEqual(flow.version, 3)
        XCTAssertTrue(flow.settings.show_progress)
        XCTAssertTrue(flow.settings.allow_back)
        XCTAssertNil(flow.settings.skip_to_step)
    }

    // MARK: - Selection modes

    func testSelectionModes() {
        XCTAssertEqual(SelectionMode.single.rawValue, "single")
        XCTAssertEqual(SelectionMode.multi.rawValue, "multi")
    }

    // MARK: - QuestionOption

    func testQuestionOptionIdentifiable() {
        let option = QuestionOption(id: "opt_1", label: "Option 1", icon: "✅", subtitle: nil)
        XCTAssertEqual(option.id, "opt_1")
        XCTAssertEqual(option.label, "Option 1")
    }

    // MARK: - Delegate protocol default implementations

    func testDelegateDefaultImplementations() {
        // Verify that the protocol has default implementations (compiles without error)
        class TestDelegate: AppDNAOnboardingDelegate {}
        let delegate = TestDelegate()
        delegate.onOnboardingStarted(flowId: "f")
        delegate.onOnboardingStepChanged(flowId: "f", stepId: "s", stepIndex: 0, totalSteps: 3)
        delegate.onOnboardingCompleted(flowId: "f", responses: [:])
        delegate.onOnboardingDismissed(flowId: "f", atStep: 0)
        // No assertions needed — just verifies defaults exist and don't crash
    }

    // MARK: - Birth date → age computation (v1.0.48)
    // Mirrors the calculation used in DateWheelPickerBlockView.persistDate()
    // so we have a regression guard for the `<field_id>_age` sibling key.

    private func computeAge(birthDate: Date, today: Date) -> Int {
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: today).year ?? 0
        return max(0, years)
    }

    func testAgeCalculationStandardCase() {
        var components = DateComponents()
        components.year = 2000; components.month = 4; components.day = 1
        let birth = Calendar.current.date(from: components)!
        var today = DateComponents()
        today.year = 2026; today.month = 4; today.day = 14
        let now = Calendar.current.date(from: today)!
        XCTAssertEqual(computeAge(birthDate: birth, today: now), 26)
    }

    func testAgeCalculationBeforeBirthdayThisYear() {
        // Born Dec 31 2000; today Apr 14 2026 → still 25 (birthday hasn't passed).
        var b = DateComponents(); b.year = 2000; b.month = 12; b.day = 31
        let birth = Calendar.current.date(from: b)!
        var t = DateComponents(); t.year = 2026; t.month = 4; t.day = 14
        let now = Calendar.current.date(from: t)!
        XCTAssertEqual(computeAge(birthDate: birth, today: now), 25)
    }

    func testAgeCalculationFutureDateClampedToZero() {
        // Picker default is today; if the user picks the future, age must
        // not go negative — the SDK clamps with max(0, years).
        var b = DateComponents(); b.year = 2030; b.month = 1; b.day = 1
        let birth = Calendar.current.date(from: b)!
        var t = DateComponents(); t.year = 2026; t.month = 4; t.day = 14
        let now = Calendar.current.date(from: t)!
        XCTAssertEqual(computeAge(birthDate: birth, today: now), 0)
    }
}
