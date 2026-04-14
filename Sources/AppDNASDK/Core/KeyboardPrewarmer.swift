import UIKit

/// Pre-warms the iOS keyboard system so the first keystroke in an onboarding
/// text / location field doesn't incur the 200–400ms lag iOS normally pays
/// on first-ever keyboard presentation (loading keyboard extensions,
/// dictionary, autocomplete suggestions, haptic engine).
///
/// We briefly add a zero-frame `UITextField` to the key window, make it
/// first responder, then immediately resign and remove it. The keyboard
/// subsystem initializes but never shows visibly because the field has
/// no frame.
///
/// Guarded by a once-flag — repeated `prewarmOnce()` calls are no-ops.
enum KeyboardPrewarmer {
    private static var hasRun = false

    static func prewarmOnce() {
        guard !hasRun else { return }
        hasRun = true
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                .first else { return }
            // Offscreen position keeps it out of the user's view while still
            // allowing UIKit to treat it as part of the responder chain.
            // `isHidden = true` silently excludes the field from responder
            // chain — `becomeFirstResponder` no-ops. Tiny frame far off the
            // left edge does the trick without any visible flash.
            let field = UITextField(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
            field.alpha = 0.01 // UIKit sometimes skips layout on alpha = 0
            window.addSubview(field)
            let didFocus = field.becomeFirstResponder()
            // Yield a tick so UIKit starts loading keyboard extensions /
            // dictionary / haptic engine, then tear down.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                field.resignFirstResponder()
                field.removeFromSuperview()
            }
            #if DEBUG
            if !didFocus {
                print("[AppDNA] KeyboardPrewarmer: becomeFirstResponder failed")
            }
            #endif
        }
    }
}
