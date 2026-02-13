import XCTest
@testable import AppDNASDK

final class PaywallConfigDecodingTests: XCTestCase {

    // MARK: - Full config decoding

    func testDecodeFullPaywallConfig() throws {
        let json = """
        {
            "id": "annual_promo",
            "name": "Annual Promotion",
            "layout": {
                "type": "stack",
                "spacing": 16,
                "padding": 20
            },
            "sections": [
                {
                    "type": "header",
                    "data": {
                        "title": "Unlock Premium",
                        "subtitle": "Get access to all features",
                        "image_url": "https://example.com/header.png"
                    }
                },
                {
                    "type": "features",
                    "data": {
                        "features": ["Unlimited access", "No ads", "Priority support"]
                    }
                },
                {
                    "type": "plans",
                    "data": {
                        "plans": [
                            {
                                "id": "annual",
                                "product_id": "com.app.annual",
                                "name": "Annual",
                                "price": "$49.99",
                                "period": "year",
                                "badge": "Best Value",
                                "trial_duration": "7 days",
                                "is_default": true
                            },
                            {
                                "id": "monthly",
                                "product_id": "com.app.monthly",
                                "name": "Monthly",
                                "price": "$9.99",
                                "period": "month",
                                "is_default": false
                            }
                        ]
                    }
                },
                {
                    "type": "cta",
                    "data": {
                        "cta": {
                            "text": "Start Free Trial",
                            "style": "primary"
                        }
                    }
                },
                {
                    "type": "social_proof",
                    "data": {
                        "rating": 4.8,
                        "review_count": 12500,
                        "testimonial": "Best app I've ever used!"
                    }
                }
            ],
            "dismiss": {
                "type": "x_button",
                "delay_seconds": 3
            },
            "background": {
                "type": "gradient",
                "colors": ["#1a1a2e", "#16213e"]
            }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(PaywallConfig.self, from: json)

        XCTAssertEqual(config.id, "annual_promo")
        XCTAssertEqual(config.name, "Annual Promotion")
        XCTAssertEqual(config.layout.type, "stack")
        XCTAssertEqual(config.layout.spacing, 16)
        XCTAssertEqual(config.sections.count, 5)
    }

    // MARK: - Section types

    func testDecodeHeaderSection() throws {
        let json = """
        {
            "type": "header",
            "data": {
                "title": "Welcome",
                "subtitle": "Choose your plan",
                "image_url": "https://example.com/img.png"
            }
        }
        """.data(using: .utf8)!

        let section = try JSONDecoder().decode(PaywallSection.self, from: json)
        XCTAssertEqual(section.type, "header")
        XCTAssertEqual(section.data?.title, "Welcome")
        XCTAssertEqual(section.data?.subtitle, "Choose your plan")
        XCTAssertEqual(section.data?.imageUrl, "https://example.com/img.png")
    }

    func testDecodeFeaturesSection() throws {
        let json = """
        {
            "type": "features",
            "data": {
                "features": ["Feature A", "Feature B", "Feature C"]
            }
        }
        """.data(using: .utf8)!

        let section = try JSONDecoder().decode(PaywallSection.self, from: json)
        XCTAssertEqual(section.type, "features")
        XCTAssertEqual(section.data?.features?.count, 3)
        XCTAssertEqual(section.data?.features?.first, "Feature A")
    }

    func testDecodePlansSection() throws {
        let json = """
        {
            "type": "plans",
            "data": {
                "plans": [
                    {
                        "id": "plan_1",
                        "product_id": "com.app.plan1",
                        "name": "Basic",
                        "price": "$4.99",
                        "period": "month"
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        let section = try JSONDecoder().decode(PaywallSection.self, from: json)
        XCTAssertEqual(section.data?.plans?.count, 1)
        XCTAssertEqual(section.data?.plans?.first?.productId, "com.app.plan1")
        XCTAssertEqual(section.data?.plans?.first?.price, "$4.99")
    }

    func testDecodeSocialProofSection() throws {
        let json = """
        {
            "type": "social_proof",
            "data": {
                "rating": 4.7,
                "review_count": 5000,
                "testimonial": "Amazing app!"
            }
        }
        """.data(using: .utf8)!

        let section = try JSONDecoder().decode(PaywallSection.self, from: json)
        XCTAssertEqual(section.data?.rating, 4.7)
        XCTAssertEqual(section.data?.reviewCount, 5000)
        XCTAssertEqual(section.data?.testimonial, "Amazing app!")
    }

    // MARK: - Optional fields

    func testDecodeWithMissingOptionalFields() throws {
        let json = """
        {
            "id": "minimal",
            "name": "Minimal Paywall",
            "layout": { "type": "stack" },
            "sections": []
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(PaywallConfig.self, from: json)
        XCTAssertEqual(config.id, "minimal")
        XCTAssertNil(config.dismiss)
        XCTAssertNil(config.background)
        XCTAssertNil(config.layout.spacing)
        XCTAssertTrue(config.sections.isEmpty)
    }

    func testDecodePlanWithMissingOptionalFields() throws {
        let json = """
        {
            "id": "plan_basic",
            "product_id": "com.app.basic",
            "name": "Basic",
            "price": "$0.99"
        }
        """.data(using: .utf8)!

        let plan = try JSONDecoder().decode(PaywallPlan.self, from: json)
        XCTAssertEqual(plan.id, "plan_basic")
        XCTAssertNil(plan.period)
        XCTAssertNil(plan.badge)
        XCTAssertNil(plan.trialDuration)
        XCTAssertNil(plan.isDefault)
    }

    // MARK: - Dismiss config

    func testDecodeDismissWithDelay() throws {
        let json = """
        {
            "type": "x_button",
            "delay_seconds": 5,
            "text": "Close"
        }
        """.data(using: .utf8)!

        let dismiss = try JSONDecoder().decode(PaywallDismiss.self, from: json)
        XCTAssertEqual(dismiss.type, "x_button")
        XCTAssertEqual(dismiss.delaySeconds, 5)
        XCTAssertEqual(dismiss.text, "Close")
    }

    // MARK: - Background config

    func testDecodeGradientBackground() throws {
        let json = """
        {
            "type": "gradient",
            "colors": ["#FF0000", "#0000FF"]
        }
        """.data(using: .utf8)!

        let bg = try JSONDecoder().decode(PaywallBackground.self, from: json)
        XCTAssertEqual(bg.type, "gradient")
        XCTAssertEqual(bg.colors?.count, 2)
    }

    func testDecodeColorBackground() throws {
        let json = """
        {
            "type": "color",
            "value": "#1a1a2e"
        }
        """.data(using: .utf8)!

        let bg = try JSONDecoder().decode(PaywallBackground.self, from: json)
        XCTAssertEqual(bg.type, "color")
        XCTAssertEqual(bg.value, "#1a1a2e")
    }
}
