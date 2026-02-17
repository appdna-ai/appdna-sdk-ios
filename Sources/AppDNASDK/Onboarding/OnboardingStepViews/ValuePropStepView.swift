import SwiftUI

/// Value proposition step: title, icon+title+subtitle items, CTA.
struct ValuePropStepView: View {
    let config: StepConfig
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            if let title = config.title {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
            }

            // Value prop items
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(config.items ?? []) { item in
                        HStack(spacing: 16) {
                            Text(item.icon)
                                .font(.system(size: 36))
                                .frame(width: 48, height: 48)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline)

                                Text(item.subtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 24)
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
