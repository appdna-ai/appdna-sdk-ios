import SafariServices
import UIKit

/// Opens URLs in an in-app Safari browser instead of leaving the app.
/// Used for terms & conditions, privacy policy, and other legal links.
enum InAppBrowser {
    static func present(url: URL) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            // Fallback to external browser if no root VC
            UIApplication.shared.open(url)
            return
        }

        let safari = SFSafariViewController(url: url)
        safari.preferredControlTintColor = UIColor(red: 99/255, green: 102/255, blue: 241/255, alpha: 1) // #6366F1
        safari.modalPresentationStyle = .pageSheet

        // Find the topmost presented VC to present from
        var topVC = root
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        topVC.present(safari, animated: true)
    }
}
