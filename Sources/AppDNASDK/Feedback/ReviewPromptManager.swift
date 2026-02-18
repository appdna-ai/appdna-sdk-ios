import Foundation
import UIKit
import StoreKit

/// Manages review prompt presentation: two-step and direct native review.
final class ReviewPromptManager {
    static let shared = ReviewPromptManager()

    private let defaults = UserDefaults.standard
    private let prefix = "ai.appdna.sdk.review."

    private init() {}

    // MARK: - Two-step review prompt

    /// Present "Do you enjoy [App]?" → yes → native review, no → decline event.
    func triggerTwoStepReview(appName: String? = nil) {
        let name = appName ?? Bundle.main.displayName ?? "this app"

        DispatchQueue.main.async { [weak self] in
            let alert = UIAlertController(
                title: "Enjoying \(name)?",
                message: "We'd love to hear your feedback!",
                preferredStyle: .alert
            )

            alert.addAction(UIAlertAction(title: "Yes! \u{1F60A}", style: .default) { _ in
                AppDNA.track(event: "review_prompt_accepted", properties: nil)
                self?.requestNativeReview()
            })

            alert.addAction(UIAlertAction(title: "Not really", style: .cancel) { _ in
                AppDNA.track(event: "review_prompt_declined", properties: nil)
            })

            self?.presentAlert(alert)
            AppDNA.track(event: "review_prompt_shown", properties: ["prompt_type": "two_step"])
        }
    }

    // MARK: - Direct native review prompt

    /// Trigger native SKStoreReviewController immediately.
    func triggerReview() {
        DispatchQueue.main.async { [weak self] in
            self?.requestNativeReview()
            AppDNA.track(event: "review_prompt_shown", properties: ["prompt_type": "direct"])
        }
    }

    // MARK: - Private

    private func requestNativeReview() {
        // Track that we requested a review
        let count = defaults.integer(forKey: "\(prefix)request_count")
        defaults.set(count + 1, forKey: "\(prefix)request_count")
        defaults.set(Date(), forKey: "\(prefix)last_request_date")

        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    private func presentAlert(_ alert: UIAlertController) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        topVC.present(alert, animated: true)
    }
}

// MARK: - Bundle helper

extension Bundle {
    var displayName: String? {
        object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? object(forInfoDictionaryKey: "CFBundleName") as? String
    }
}
