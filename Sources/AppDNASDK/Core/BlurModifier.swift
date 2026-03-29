import SwiftUI

public struct BlurConfig: Codable {
    public let radius: Double?
    public let tint: String?
    public let saturation: Double?
}

public struct BlurBackdropModifier: ViewModifier {
    let config: BlurConfig

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // System material for glassmorphism
                    if (config.radius ?? 0) > 0 {
                        Color.clear
                            .background(.ultraThinMaterial)
                            .blur(radius: CGFloat(config.radius ?? 0) / 3)
                    }

                    // Optional tint overlay
                    if let tint = config.tint {
                        Color(hex: tint).opacity(0.15)
                    }
                }
            )
            .saturation(config.saturation ?? 1.8)
    }
}

extension View {
    public func applyBlurBackdrop(_ config: BlurConfig?) -> some View {
        Group {
            if let config = config, (config.radius ?? 0) > 0 {
                self.modifier(BlurBackdropModifier(config: config))
            } else {
                self
            }
        }
    }
}
