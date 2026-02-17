import SwiftUI

/// Custom step: generic layout renderer from config.
/// Renders a basic layout with title, subtitle, image, and CTA from the config dictionary.
struct CustomStepView: View {
    let config: StepConfig
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Render from layout config or fall back to basic title/CTA
            if let title = config.title {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let subtitle = config.subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if let urlString = config.image_url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280, maxHeight: 280)
                    default:
                        EmptyView()
                    }
                }
            }

            Spacer()

            Button(action: onNext) {
                Text(config.cta_text ?? "Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.accentColor)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}
