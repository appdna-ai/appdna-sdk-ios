import SwiftUI

/// Welcome step: title, subtitle, optional image, CTA button.
struct WelcomeStepView: View {
    let config: StepConfig
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Optional image
            if let urlString = config.image_url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280, maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    case .failure:
                        EmptyView()
                    default:
                        ProgressView()
                            .frame(width: 200, height: 200)
                    }
                }
            }

            VStack(spacing: 12) {
                if let title = config.title {
                    Text(title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                }

                if let subtitle = config.subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            Button(action: onNext) {
                Text(config.cta_text ?? "Get Started")
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
