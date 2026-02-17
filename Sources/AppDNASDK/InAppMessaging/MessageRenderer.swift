import SwiftUI

/// Routes to the appropriate message view based on message_type.
struct MessageRenderer: View {
    let messageId: String
    let config: MessageConfig
    let onCTATap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        switch config.message_type {
        case .banner:
            BannerView(content: config.content, onCTATap: onCTATap, onDismiss: onDismiss)
        case .modal:
            ModalView(content: config.content, onCTATap: onCTATap, onDismiss: onDismiss)
        case .fullscreen:
            FullscreenView(content: config.content, onCTATap: onCTATap, onDismiss: onDismiss)
        case .tooltip:
            TooltipView(content: config.content, onCTATap: onCTATap, onDismiss: onDismiss)
        }
    }
}
