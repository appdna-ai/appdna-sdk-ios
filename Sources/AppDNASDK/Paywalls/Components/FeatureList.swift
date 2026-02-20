import SwiftUI

/// Checkmark feature list for paywalls.
struct FeatureList: View {
    let features: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(features, id: \.self) { feature in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.body)
                    Text(feature)
                        .font(.body)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal)
    }
}
