import SwiftUI
import UIKit

/// Handles presenting server-driven screens in different modes (fullscreen, modal, bottom_sheet, push).
internal class ScreenPresenter {

    static func present(
        config: ScreenConfig,
        context: SectionContext,
        from viewController: UIViewController? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        let contextHolder = ScreenContextHolder(context: context)
        let renderer = ScreenRenderer(config: config, context: contextHolder)
        let hostingController = ScreenHostingController(rootView: AnyView(renderer), onDismiss: onDismiss)

        switch config.presentation {
        case "fullscreen":
            hostingController.modalPresentationStyle = .fullScreen
            hostingController.modalTransitionStyle = transitionStyle(config.transition)

        case "modal":
            hostingController.modalPresentationStyle = .pageSheet

        case "bottom_sheet":
            hostingController.modalPresentationStyle = .pageSheet
            if #available(iOS 15.0, *) {
                if let sheet = hostingController.sheetPresentationController {
                    sheet.detents = [.medium(), .large()]
                    sheet.prefersGrabberVisible = true
                }
            }

        case "push":
            if let navController = viewController?.navigationController {
                navController.pushViewController(hostingController, animated: true)
                return
            }
            // Fallback to modal if no nav controller
            hostingController.modalPresentationStyle = .fullScreen

        default:
            hostingController.modalPresentationStyle = .fullScreen
        }

        let presentBlock = {
            let presenter = viewController ?? UIApplication.shared.topViewController
            presenter?.present(hostingController, animated: true)
        }
        if Thread.isMainThread {
            presentBlock()
        } else {
            DispatchQueue.main.async { presentBlock() }
        }
    }

    static func presentFlow(
        flowManager: FlowManager,
        from viewController: UIViewController? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        guard let screenConfig = flowManager.currentScreen else { return }

        let context = SectionContext(
            screenId: flowManager.currentScreenId ?? "",
            flowId: flowManager.flowConfig.id,
            responses: flowManager.responses,
            onAction: { [weak flowManager] action in
                flowManager?.handleAction(action)
            },
            currentScreenIndex: flowManager.currentScreenIndex,
            totalScreens: flowManager.flowConfig.screens.count
        )

        present(config: screenConfig, context: context, from: viewController, onDismiss: onDismiss)
    }

    private static func transitionStyle(_ transition: String?) -> UIModalTransitionStyle {
        switch transition {
        case "slide_up": return .coverVertical
        case "slide_left": return .coverVertical // iOS doesn't have native slide-left modal
        case "fade": return .crossDissolve
        case "none": return .crossDissolve
        default: return .coverVertical
        }
    }
}

// MARK: - Hosting Controller with dismiss callback

private class ScreenHostingController: UIHostingController<AnyView> {
    var onDismiss: (() -> Void)?

    init(rootView: AnyView, onDismiss: (() -> Void)?) {
        self.onDismiss = onDismiss
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            onDismiss?()
            PresentationCoordinator.shared.onDismissed()
        }
    }
}

// MARK: - UIApplication extension for top view controller

extension UIApplication {
    var topViewController: UIViewController? {
        guard let windowScene = connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              var top = window.rootViewController else { return nil }

        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
