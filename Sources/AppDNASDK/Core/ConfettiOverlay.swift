import SwiftUI

public struct ParticleEffect: Codable {
    public let type: String        // "confetti", "sparkle", "fireworks", "snow", "hearts"
    public let trigger: String     // "on_appear", "on_step_complete", "on_purchase", "on_flow_complete"
    public let duration_ms: Int
    public let intensity: String   // "light", "medium", "heavy"
    public let colors: [String]?
}

public struct ConfettiOverlay: View {
    let effect: ParticleEffect
    @State private var isActive = false
    @State private var particles: [ConfettiParticle] = []

    private var particleCount: Int {
        switch effect.intensity {
        case "light": return 30
        case "heavy": return 120
        default: return 60
        }
    }

    private var effectColors: [Color] {
        if let customColors = effect.colors, !customColors.isEmpty {
            return customColors.map { Color(hex: $0) }
        }
        switch effect.type {
        case "hearts": return [.red, .pink, Color(hex: "#FF6B9D")]
        case "snow": return [.white, Color(white: 0.95), Color(white: 0.9)]
        case "sparkle": return [.yellow, .orange, Color(hex: "#FFD700")]
        case "fireworks": return [.red, .blue, .green, .yellow, .purple, .orange]
        default: return [.red, .blue, .green, .yellow, .purple, .orange, .pink]
        }
    }

    private var particleShape: String {
        switch effect.type {
        case "hearts": return "\u{2764}\u{FE0F}"
        case "snow": return "\u{2744}\u{FE0F}"
        case "sparkle": return "\u{2728}"
        case "fireworks": return "\u{1F386}"
        default: return "\u{25CF}"
        }
    }

    public var body: some View {
        ZStack {
            if isActive {
                ForEach(particles) { particle in
                    if effect.type == "confetti" {
                        Circle()
                            .fill(particle.color)
                            .frame(width: particle.size, height: particle.size)
                            .position(particle.position)
                            .opacity(particle.opacity)
                    } else {
                        Text(particleShape)
                            .font(.system(size: particle.size))
                            .position(particle.position)
                            .opacity(particle.opacity)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            if effect.trigger == "on_appear" {
                startAnimation()
            }
        }
    }

    private mutating func startAnimation() {
        isActive = true
        particles = (0..<particleCount).map { _ in
            ConfettiParticle(
                color: effectColors.randomElement() ?? .blue,
                size: CGFloat.random(in: 4...12),
                position: CGPoint(
                    x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                    y: -20
                ),
                opacity: 1.0
            )
        }

        // Animate particles falling
        withAnimation(.easeOut(duration: Double(effect.duration_ms) / 1000.0)) {
            particles = particles.map { p in
                var updated = p
                updated.position = CGPoint(
                    x: p.position.x + CGFloat.random(in: -50...50),
                    y: UIScreen.main.bounds.height + 50
                )
                updated.opacity = 0
                return updated
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(effect.duration_ms) / 1000.0) {
            isActive = false
        }
    }

    public mutating func triggerEffect() {
        startAnimation()
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let color: Color
    let size: CGFloat
    var position: CGPoint
    var opacity: Double
}
