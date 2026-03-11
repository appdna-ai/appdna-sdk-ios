import SwiftUI
// Note: In real build, would import Lottie — we model the API for when dependency is added
// import Lottie

public struct LottieBlock: Codable {
    public let lottie_url: String?
    public let lottie_json: [String: AnyCodable]?
    public let autoplay: Bool
    public let loop: Bool
    public let speed: Double
    public let width: Double?
    public let height: Double
    public let alignment: String
    public let play_on_scroll: Bool?
    public let play_on_tap: Bool?
    public let color_overrides: [String: String]?
}

public struct LottieBlockView: View {
    let block: LottieBlock

    private var alignmentValue: Alignment {
        switch block.alignment {
        case "left": return .leading
        case "right": return .trailing
        default: return .center
        }
    }

    public var body: some View {
        // Placeholder that shows animation URL — real implementation uses LottieView from lottie-ios
        // When lottie-ios is added as SPM dependency, replace with:
        // LottieView(animation: .init(url: URL(string: block.lottie_url ?? "")))
        //     .playbackMode(block.loop ? .playing(.toProgress(1, loopMode: .loop)) : .playing(.toProgress(1, loopMode: .playOnce)))
        //     .animationSpeed(block.speed)
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.1))
            VStack(spacing: 4) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.purple)
                Text("Lottie Animation")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let url = block.lottie_url {
                    Text(URL(string: url)?.lastPathComponent ?? "")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(height: CGFloat(block.height))
        .frame(maxWidth: block.width.map { CGFloat($0) } ?? .infinity, alignment: alignmentValue)
    }
}
