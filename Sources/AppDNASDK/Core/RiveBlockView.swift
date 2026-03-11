import SwiftUI
// import RiveRuntime — modeled for when dependency is added

public struct RiveBlock: Codable {
    public let rive_url: String
    public let artboard: String?
    public let state_machine: String?
    public let autoplay: Bool
    public let height: Double
    public let alignment: String
    public let inputs: [String: AnyCodable]?
    public let trigger_on_step_complete: String?
}

public struct RiveBlockView: View {
    let block: RiveBlock

    private var alignmentValue: Alignment {
        switch block.alignment {
        case "left": return .leading
        case "right": return .trailing
        default: return .center
        }
    }

    public var body: some View {
        // Placeholder — real implementation uses RiveViewModel
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
            VStack(spacing: 4) {
                Image(systemName: "film.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.blue)
                Text("Rive Animation")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if let sm = block.state_machine {
                    Text("State: \(sm)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(height: CGFloat(block.height))
        .frame(maxWidth: .infinity, alignment: alignmentValue)
    }
}
