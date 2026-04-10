import SwiftUI
import MapKit
import PhotosUI
// MARK: - Rating Block View (SPEC-089d AC-019)

/// Stateful star rating input rendered as an independent SwiftUI view.
struct RatingBlockView: View {
    let block: ContentBlock
    let onAction: (_ action: String, _ actionValue: String?) -> Void

    @State private var selectedRating: Double = 0

    var body: some View {
        let maxStars = block.max_stars ?? 5
        let starSz = CGFloat(block.star_size ?? 32)
        let filledCol = Color(hex: block.filled_color ?? "#FBBF24")
        let emptyCol = Color(hex: block.empty_color ?? "#D1D5DB")
        let halfEnabled = block.allow_half ?? false

        VStack(spacing: 8) {
            if let label = block.rating_label {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }

            HStack(spacing: 4) {
                ForEach(1...maxStars, id: \.self) { index in
                    starImage(for: Double(index), filled: filledCol, empty: emptyCol, halfEnabled: halfEnabled)
                        .font(.system(size: starSz))
                        .onTapGesture {
                            selectedRating = Double(index)
                        }
                        .gesture(
                            halfEnabled ?
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let halfThreshold = starSz / 2
                                    if value.location.x < halfThreshold {
                                        selectedRating = Double(index) - 0.5
                                    } else {
                                        selectedRating = Double(index)
                                    }
                                }
                            : nil
                        )
                        .accessibilityLabel("\(index) star\(index > 1 ? "s" : "")")
                }
            }
        }
        .onAppear {
            selectedRating = block.default_rating ?? 0
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int(selectedRating)) of \(maxStars) stars")
    }

    @ViewBuilder
    private func starImage(for value: Double, filled: Color, empty: Color, halfEnabled: Bool) -> some View {
        if selectedRating >= value {
            Image(systemName: "star.fill")
                .foregroundColor(filled)
        } else if halfEnabled && selectedRating >= value - 0.5 {
            Image(systemName: "star.leadinghalf.filled")
                .foregroundColor(filled)
        } else {
            Image(systemName: "star")
                .foregroundColor(empty)
        }
    }
}

// MARK: - Countdown Timer Block View (SPEC-089d AC-018)

/// Stateful countdown timer driven by `Timer.publish`.
struct CountdownTimerBlockView: View {
    let block: ContentBlock
    let onAction: (_ action: String, _ actionValue: String?) -> Void

    @State private var remainingSeconds: Int = 0
    @State private var expired: Bool = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if expired {
                expiredView
            } else {
                digitalTimerView
            }
        }
        .onAppear {
            remainingSeconds = block.duration_seconds ?? 60
        }
        .onReceive(timer) { _ in
            guard !expired else { return }
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            }
            if remainingSeconds <= 0 {
                expired = true
                handleExpiry()
            }
        }
    }

    // Digital variant (default): HStack of time unit columns
    private var digitalTimerView: some View {
        let timeColor = Color(hex: block.text_color ?? "#000000")
        let accentCol = Color(hex: block.accent_color ?? "#6366F1")
        let fontSize = CGFloat(block.font_size ?? 28)
        let lbls = block.labels

        let days = remainingSeconds / 86400
        let hours = (remainingSeconds % 86400) / 3600
        let minutes = (remainingSeconds % 3600) / 60
        let seconds = remainingSeconds % 60

        return HStack(spacing: 16) {
            if block.show_days != false && days > 0 {
                timerUnit(value: days, label: lbls?.days ?? "Days", fontSize: fontSize, color: timeColor, accent: accentCol)
            }
            if block.show_hours != false {
                timerUnit(value: hours, label: lbls?.hours ?? "Hours", fontSize: fontSize, color: timeColor, accent: accentCol)
            }
            if block.show_minutes != false {
                timerUnit(value: minutes, label: lbls?.minutes ?? "Min", fontSize: fontSize, color: timeColor, accent: accentCol)
            }
            if block.show_seconds != false {
                timerUnit(value: seconds, label: lbls?.seconds ?? "Sec", fontSize: fontSize, color: timeColor, accent: accentCol)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func timerUnit(value: Int, label: String, fontSize: CGFloat, color: Color, accent: Color) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "%02d", value))
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(accent)
        }
    }

    @ViewBuilder
    private var expiredView: some View {
        switch block.on_expire_action {
        case "hide":
            EmptyView()
        case "show_expired_text":
            Text(block.expired_text ?? "Time's up!")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
        default:
            // auto_advance or no action specified -- show brief expired text
            Text(block.expired_text ?? "Time's up!")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func handleExpiry() {
        if block.on_expire_action == "auto_advance" {
            onAction("next", nil)
        }
    }
}

// MARK: - Animated Loading Block View (SPEC-089d AC-017)

/// Stateful animated loading / checklist block driven by sequential timers.
struct AnimatedLoadingBlockView: View {
    let block: ContentBlock
    let onAction: (_ action: String, _ actionValue: String?) -> Void

    @State private var completedCount: Int = 0
    @State private var overallProgress: CGFloat = 0
    @State private var timerCancellable: Timer? = nil
    @State private var spinAngle: Double = 0

    var body: some View {
        let variant = block.loading_variant ?? "checklist"
        let itemList = block.loading_items ?? []
        let progressCol = Color(hex: block.progress_color ?? "#6366F1")
        let checkCol = Color(hex: block.check_color ?? "#22C55E")
        let totalMs = block.total_duration_ms ?? itemList.reduce(0) { $0 + ($1.duration_ms ?? 1000) }

        VStack(spacing: 16) {
            // Percentage is rendered inside each variant (circular ring center, linear bar, etc.)
            // to avoid duplicate display. See loadingVariantView for per-variant rendering.

            loadingVariantView(variant: variant, itemList: itemList, progressCol: progressCol, checkCol: checkCol)
        }
        .onAppear {
            startSequentialTimer(items: itemList, totalMs: totalMs)
        }
        .onDisappear {
            timerCancellable?.invalidate()
        }
    }

    /// Type-erased loading variant to avoid @ViewBuilder switch in body.
    private func loadingVariantView(variant: String, itemList: [LoadingItemConfig], progressCol: Color, checkCol: Color) -> AnyView {
        switch variant {
        case "orbiting_icons":
            return AnyView(OrbitingIconsLoaderView(
                block: block,
                items: itemList,
                progress: overallProgress,
                completedCount: completedCount,
                progressCol: progressCol
            ))

        case "circular":
            return AnyView(
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: max(0.05, overallProgress))
                            .stroke(progressCol, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90 + spinAngle))
                            .animation(.linear(duration: 0.3), value: overallProgress)
                        if block.show_percentage == true {
                            Text("\(Int(overallProgress * 100))%")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(progressCol)
                        }
                    }
                    .frame(width: 80, height: 80)
                    .padding(8) // Ensure circle stroke isn't clipped
                    .onAppear { withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { spinAngle = 360 } }

                    // Show current loading item label
                    if completedCount < itemList.count {
                        Text(itemList[completedCount].label ?? "")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                            .animation(.easeInOut, value: completedCount)
                    }
                }
                .frame(maxWidth: .infinity)
            )

        case "linear":
            return AnyView(
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(progressCol)
                            .frame(width: geometry.size.width * overallProgress, height: 8)
                            .animation(.linear(duration: 0.3), value: overallProgress)
                    }
                }
                .frame(height: 8)
            )

        default: // checklist
            return AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(itemList.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 12) {
                            ZStack {
                                if index < completedCount {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(checkCol)
                                        .transition(.scale.combined(with: .opacity))
                                } else if index == completedCount {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .transition(.opacity)
                                } else {
                                    Circle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                                        .frame(width: 22, height: 22)
                                }
                            }
                            .frame(width: 28, height: 28)
                            .animation(.easeInOut(duration: 0.3), value: completedCount)

                            Text(item.label ?? "")
                                .font(.subheadline)
                                .foregroundColor(index <= completedCount ? .primary : .secondary)
                        }
                    }
                }
            )
        }
    }

    private func startSequentialTimer(items: [LoadingItemConfig], totalMs: Int) {
        guard !items.isEmpty else {
            // No items: just run a single progress over totalMs
            let duration = Double(totalMs) / 1000.0
            let tickInterval = 0.05
            var elapsed = 0.0
            timerCancellable = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { timer in
                elapsed += tickInterval
                let progress = min(elapsed / duration, 1.0)
                DispatchQueue.main.async {
                    overallProgress = CGFloat(progress)
                }
                if elapsed >= duration {
                    timer.invalidate()
                    if block.auto_advance == true {
                        DispatchQueue.main.async {
                            onAction("next", nil)
                        }
                    }
                }
            }
            return
        }

        // Sequential item completion
        var cumulativeDelay = 0.0
        let totalDuration = Double(items.reduce(0) { $0 + ($1.duration_ms ?? 1000) })

        for (index, item) in items.enumerated() {
            let itemDuration = Double(item.duration_ms ?? 1000) / 1000.0
            cumulativeDelay += itemDuration

            let capturedDelay = cumulativeDelay
            let capturedIndex = index

            DispatchQueue.main.asyncAfter(deadline: .now() + capturedDelay) {
                withAnimation {
                    completedCount = capturedIndex + 1
                    overallProgress = totalDuration > 0 ? CGFloat(capturedDelay / (totalDuration / 1000.0)) : 1.0
                }

                // If last item, handle auto_advance
                if capturedIndex == items.count - 1 {
                    overallProgress = 1.0
                    if block.auto_advance == true {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            onAction("next", nil)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Orbiting Icons Loader View

/// Radial loader: a central dot/image with N icons orbiting around it on a ring.
/// Each icon has its own background color and image/emoji. Used for "Aligning the
/// stars" style screens (Astro Future, SynergyChart).
///
/// Configuration (all via `block.field_config`):
///   - `orbit_radius` (Double)     — radius of the orbit circle, default 80
///   - `orbit_duration_ms` (Int)   — ms for a full rotation, default 6000
///   - `central_image_url` (String)
///   - `central_bg_color` (String)
///   - `central_size` (Double)     — diameter of central circle, default 10
///   - `ring_color` (String)       — optional visible ring stroke color
///   - `ring_width` (Double)       — ring stroke width, default 1
///   - `animated_bg` (String)      — "none" (default), "constellation", "pulse"
///   - `animated_bg_color` (String)
///   - `size` (Double)             — total frame size (square), default 240
///
/// Each item in `block.loading_items` becomes one orbiting icon. The item can
/// specify:
///   - `icon_url` or `icon`         — image/emoji to display
///   - `icon_bg_color`              — hex background color for the icon bubble
///   - `icon_size`                  — diameter of the icon, default 48
///   - `icon_orbit_angle`           — optional fixed angle 0-360; nil = auto-distribute
///   - `label` (String)             — text to show during this icon's active phase
struct OrbitingIconsLoaderView: View {
    let block: ContentBlock
    let items: [LoadingItemConfig]
    let progress: CGFloat
    let completedCount: Int
    let progressCol: Color

    @State private var rotation: Double = 0
    @State private var bgPulse: CGFloat = 0

    var body: some View {
        // Pull orbiting config from field_config (dictionary-based, no schema changes)
        let cfg = block.field_config
        let size: CGFloat = CGFloat((cfgDouble(cfg?["size"])) ?? 240)
        let orbitRadius: CGFloat = CGFloat((cfgDouble(cfg?["orbit_radius"])) ?? 80)
        let orbitDurationMs: Double = Double((cfg?["orbit_duration_ms"]?.value as? Int) ?? (cfgDouble(cfg?["orbit_duration_ms"])).map { Int($0) } ?? 6000)
        let centralSize: CGFloat = CGFloat((cfgDouble(cfg?["central_size"])) ?? 10)
        let centralImageUrl = cfg?["central_image_url"]?.value as? String
        let centralBgColorHex = cfg?["central_bg_color"]?.value as? String ?? "#FEE2E2"
        let ringColorHex = cfg?["ring_color"]?.value as? String
        let ringWidth: CGFloat = CGFloat((cfgDouble(cfg?["ring_width"])) ?? 1)
        let animatedBg = (cfg?["animated_bg"]?.value as? String) ?? "none"
        let animatedBgHex = cfg?["animated_bg_color"]?.value as? String ?? "#EEEEEE"
        let labelSize = CGFloat((cfgDouble(cfg?["label_font_size"])) ?? 17)
        let subtitleSize = CGFloat((cfgDouble(cfg?["subtitle_font_size"])) ?? 14)
        let subtitleColorHex = cfg?["subtitle_color"]?.value as? String ?? "#E11D48"
        let labelColorHex = cfg?["label_color"]?.value as? String ?? "#0F172A"
        let showPercentage = block.show_percentage ?? false
        let pctLocation = (cfg?["percentage_location"]?.value as? String) ?? "below"

        VStack(spacing: 20) {
            ZStack {
                // Animated background (optional)
                if animatedBg == "constellation" {
                    ConstellationBackground(color: Color(hex: animatedBgHex).opacity(0.4))
                        .frame(width: size * 1.2, height: size * 1.2)
                        .blendMode(.multiply)
                } else if animatedBg == "pulse" {
                    Circle()
                        .fill(Color(hex: animatedBgHex).opacity(0.15 + 0.15 * bgPulse))
                        .frame(width: size * (1.0 + 0.1 * bgPulse), height: size * (1.0 + 0.1 * bgPulse))
                }

                // Orbit rings — visible path lines for orbiting icons
                let effectiveRingColor = ringColorHex ?? "#D1D5DB"
                // Use configured opacity or a visible default (0.5) so rings
                // are clearly visible on both light and dark backgrounds.
                let ringOpacity = CGFloat((cfgDouble(cfg?["ring_opacity"])) ?? 0.5)
                Circle()
                    .stroke(Color(hex: effectiveRingColor).opacity(ringOpacity), lineWidth: ringWidth)
                    .frame(width: orbitRadius * 2, height: orbitRadius * 2)

                // Inner ring (at 60% radius) for depth
                Circle()
                    .stroke(Color(hex: effectiveRingColor).opacity(ringOpacity * 0.4), lineWidth: max(1, ringWidth * 0.5))
                    .frame(width: orbitRadius * 1.2, height: orbitRadius * 1.2)

                // Central dot/image
                if let urlStr = centralImageUrl, let url = URL(string: urlStr) {
                    BundledAsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color(hex: centralBgColorHex))
                    }
                    .frame(width: centralSize, height: centralSize)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(hex: centralBgColorHex))
                        .frame(width: centralSize, height: centralSize)
                }

                // Orbiting icons — two layers rotating in opposite directions
                // for a richer "solar system" effect. Odd-indexed icons orbit
                // on an inner ring counter-clockwise; even on outer clockwise.
                // Each icon gets a subtle scale pulse for a breathing effect.

                // Outer orbit (clockwise)
                ZStack {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        if idx % 2 == 0 || items.count <= 2 {
                            let baseAngle = item.icon_orbit_angle ?? (360.0 * Double(idx) / Double(max(items.count, 1)))
                            let angleRad = baseAngle * .pi / 180
                            let xOff = CGFloat(cos(angleRad)) * orbitRadius
                            let yOff = CGFloat(sin(angleRad)) * orbitRadius
                            let iconSize: CGFloat = CGFloat(item.icon_size ?? 48)
                            let iconBgHex = item.icon_bg_color ?? "#BE123C"
                            OrbitingIconView(item: item, size: iconSize, bgColor: Color(hex: iconBgHex))
                                .scaleEffect(1.0 + 0.08 * bgPulse)
                                .offset(x: xOff, y: yOff)
                        }
                    }
                }
                .rotationEffect(Angle(degrees: rotation))

                // Inner orbit (counter-clockwise, smaller radius) — only when 3+ items
                if items.count > 2 {
                    ZStack {
                        ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                            if idx % 2 == 1 {
                                let innerRadius = orbitRadius * 0.6
                                let baseAngle = item.icon_orbit_angle ?? (360.0 * Double(idx) / Double(max(items.count, 1)))
                                let angleRad = baseAngle * .pi / 180
                                let xOff = CGFloat(cos(angleRad)) * innerRadius
                                let yOff = CGFloat(sin(angleRad)) * innerRadius
                                let iconSize: CGFloat = CGFloat(item.icon_size ?? 40) * 0.85
                                let iconBgHex = item.icon_bg_color ?? "#BE123C"
                                OrbitingIconView(item: item, size: iconSize, bgColor: Color(hex: iconBgHex))
                                    .scaleEffect(1.0 + 0.05 * bgPulse)
                                    .opacity(0.9)
                                    .offset(x: xOff, y: yOff)
                            }
                        }
                    }
                    .rotationEffect(Angle(degrees: -rotation * 0.7))
                }
            }
            .frame(width: size, height: size)
            .onAppear {
                withAnimation(.linear(duration: orbitDurationMs / 1000.0).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
                // Breathing pulse — always on for premium feel
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    bgPulse = 1.0
                }
            }

            // Above percentage
            if showPercentage && pctLocation == "above" {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: labelSize, weight: .bold))
                    .foregroundColor(Color(hex: labelColorHex))
            }

            // Title label (from block.text OR first item label)
            if let title = block.text, !title.isEmpty {
                Text(title)
                    .font(.system(size: labelSize, weight: .semibold))
                    .foregroundColor(Color(hex: labelColorHex))
                    .multilineTextAlignment(.center)
            }

            // Active item subtitle label
            if completedCount < items.count, let subtitle = items[completedCount].label, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: subtitleSize))
                    .foregroundColor(Color(hex: subtitleColorHex))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .animation(.easeInOut, value: completedCount)
            }

            // Below percentage
            if showPercentage && pctLocation == "below" {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: labelSize, weight: .bold))
                    .foregroundColor(Color(hex: labelColorHex))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A single orbiting icon — circular bubble with image, emoji icon, or
/// SF Symbol inside.
private struct OrbitingIconView: View {
    let item: LoadingItemConfig
    let size: CGFloat
    let bgColor: Color

    var body: some View {
        ZStack {
            Circle().fill(bgColor)
            if let urlStr = item.icon_url, let url = URL(string: urlStr) {
                BundledAsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: size * 0.55, height: size * 0.55)
            } else if let icon = item.icon, !icon.isEmpty {
                // Emoji vs SF Symbol: SF Symbol names are always ASCII
                // ("heart.fill", "mars", "venus"). Emoji are non-ASCII.
                if icon.allSatisfy({ $0.isASCII }) {
                    Image(systemName: icon)
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundColor(.white)
                } else {
                    Text(icon).font(.system(size: size * 0.45))
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: bgColor.opacity(0.3), radius: 8, y: 2)
    }
}

/// Faint constellation dots + lines drifting background for orbiting loader.
private struct ConstellationBackground: View {
    let color: Color
    @State private var phase: Double = 0

    var body: some View {
        Canvas { ctx, size in
            let dots: [(CGPoint, CGFloat)] = [
                (CGPoint(x: size.width * 0.15, y: size.height * 0.2), 2),
                (CGPoint(x: size.width * 0.85, y: size.height * 0.15), 3),
                (CGPoint(x: size.width * 0.25, y: size.height * 0.75), 2),
                (CGPoint(x: size.width * 0.75, y: size.height * 0.8), 2),
                (CGPoint(x: size.width * 0.5, y: size.height * 0.4), 3),
                (CGPoint(x: size.width * 0.1, y: size.height * 0.55), 2),
                (CGPoint(x: size.width * 0.9, y: size.height * 0.5), 2),
                (CGPoint(x: size.width * 0.45, y: size.height * 0.85), 2),
            ]
            for (p, r) in dots {
                let opacity = 0.3 + 0.5 * abs(sin(phase + Double(p.x)))
                ctx.fill(
                    Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                    with: .color(color.opacity(opacity))
                )
            }
            // Connecting lines between nearest dots
            for i in 0..<dots.count {
                for j in (i + 1)..<dots.count {
                    let a = dots[i].0
                    let b = dots[j].0
                    let dx = a.x - b.x
                    let dy = a.y - b.y
                    let dist = sqrt(dx * dx + dy * dy)
                    if dist < size.width * 0.3 {
                        var path = Path()
                        path.move(to: a)
                        path.addLine(to: b)
                        ctx.stroke(path, with: .color(color.opacity(0.15)), lineWidth: 0.5)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: true)) {
                phase = .pi
            }
        }
    }
}

// MARK: - Circular Gauge Block View (SPEC-089d AC-022)

// MARK: - Speedometer Arc Shape (precise geometry via Path.addArc)

/// Draws a partial arc using explicit Path.addArc. Used for the speedometer gauge
/// to avoid the Circle().trim inscription bug where the stroke clips at frame edges.
private struct SpeedometerArcShape: Shape {
    /// Progress 0.0...1.0 — determines how far along the arc the stroke extends.
    var progress: CGFloat
    /// Full sweep angle in degrees (e.g. 220 for speedometer).
    let sweepDegrees: Double
    /// Radius of the arc.
    let radius: CGFloat
    /// Absolute Y position of the arc's center within the parent frame.
    let centerY: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: centerY)
        // Symmetric around 12 o'clock (top). In SwiftUI (y-down), 270° points north.
        // Start angle = 270 - halfSweep, sweeping visually CW (clockwise=false in math sense).
        let halfSweep = sweepDegrees / 2.0
        let startAngle = Angle.degrees(270 - halfSweep)
        let endAngle = Angle.degrees(270 - halfSweep + sweepDegrees * Double(progress))
        if progress > 0 {
            path.addArc(
                center: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )
        }
        return path
    }
}

/// Renders a circular arc gauge with center label. Supports animated fill.
struct CircularGaugeBlockView: View {
    let block: ContentBlock

    @State private var animatedProgress: CGFloat = 0

    var body: some View {
        let value = CGFloat(block.gauge_value ?? block.progress_value ?? 0)
        let minVal = CGFloat(block.min_value ?? 0)
        let maxVal = CGFloat(block.max_value ?? 100)
        let targetProgress = (maxVal - minVal) > 0 ? min((value - minVal) / (maxVal - minVal), 1.0) : 0
        // Speedometer defaults to 280 (min 240 enforced); arc/radial default 200
        let variant = block.gauge_variant ?? "arc"
        let defaultSize: Double = variant == "speedometer" ? 280 : 200
        let rawSize = CGFloat(block.height ?? defaultSize)
        // Enforce minimum size for speedometer to prevent tiny gauges
        let size = variant == "speedometer" ? max(rawSize, 240) : rawSize
        let strokeW = CGFloat(block.stroke_width ?? 14)
        let fillCol = Color(hex: block.bar_color ?? block.active_color ?? "#6366F1")
        let trackCol = Color(hex: block.track_color ?? "#E5E7EB")
        let labelCol = Color(hex: block.label_color ?? block.text_color ?? "#000000")
        let labelFontSz = CGFloat(block.label_font_size ?? block.font_size ?? 24)
        let shouldAnimate = block.animate ?? true
        let animDuration = Double(block.animation_duration_ms ?? 800) / 1000.0
        let showPct = block.show_percentage ?? false
        // Percentage placement: "center" (default), "below", "above", "none"
        let pctLocation = block.percentage_location ?? "center"

        // Gradient fill — if gradient_start_color + gradient_end_color are set,
        // use an AngularGradient for the fill stroke instead of solid color.
        // This enables the pink→red arc fill from screenshot 3.
        let cfg = block.field_config
        let gradStartHex = cfg?["gradient_start_color"]?.value as? String
        let gradEndHex = cfg?["gradient_end_color"]?.value as? String
        let useGradient = gradStartHex != nil && gradEndHex != nil

        // Needle/arrow styling — prefer dedicated arrow_color over fallbacks
        let needleCol = Color(hex: block.arrow_color ?? block.label_color ?? "#1F2937")
        let needleW = CGFloat(block.arrow_stroke_width ?? 3)
        let minLabel = block.min_label ?? "\(Int(minVal))"
        let maxLabel = block.max_label ?? "\(Int(maxVal))"
        let minMaxFontSz = CGFloat(block.min_max_font_size ?? 13)
        let minMaxCol = Color(hex: block.min_max_color ?? block.label_color ?? "#000000")

        // Speedometer sweep — 220° symmetric around top (12 o'clock)
        let speedoSweep: Double = 220
        let radius: CGFloat = size / 2 - strokeW / 2

        VStack(spacing: 4) {
            if showPct && pctLocation == "above" {
                Text("\(Int(animatedProgress * 100))%")
                    .font(.system(size: labelFontSz, weight: .bold))
                    .foregroundColor(labelCol)
            }

            if variant == "speedometer" {
                // Speedometer — explicit frame + Path-based rendering + .position() for pixel-perfect layout.
                // Arc visual center: x = size/2, y = radius + strokeW/2 (so top stroke stops at y=0, not clipped)
                let centerX = size / 2
                let centerY = radius + strokeW / 2
                // Arc endpoint coordinates (lower-left and lower-right), relative to arc center
                let endpointAngleRad: Double = (speedoSweep / 2.0) * .pi / 180.0
                let endpointOffsetX = CGFloat(sin(endpointAngleRad)) * radius      // ≈ 0.94 * radius
                let endpointOffsetY = CGFloat(abs(cos(endpointAngleRad))) * radius // ≈ 0.34 * radius (below center)
                // Frame height: from y=0 (top of stroke) to below endpoint labels
                let frameHeight = centerY + endpointOffsetY + strokeW / 2 + minMaxFontSz * 1.8 + 24

                ZStack(alignment: .topLeading) {
                    // Track (full arc)
                    SpeedometerArcShape(progress: 1.0, sweepDegrees: speedoSweep, radius: radius, centerY: centerY)
                        .stroke(trackCol, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                    // Fill (animated) — supports gradient or solid
                    if useGradient, let startHex = gradStartHex, let endHex = gradEndHex {
                        SpeedometerArcShape(progress: animatedProgress, sweepDegrees: speedoSweep, radius: radius, centerY: centerY)
                            .stroke(
                                AngularGradient(
                                    colors: [Color(hex: startHex), Color(hex: endHex)],
                                    center: UnitPoint(x: 0.5, y: centerY / (centerY + radius)),
                                    startAngle: .degrees(270 - speedoSweep / 2),
                                    endAngle: .degrees(270 - speedoSweep / 2 + speedoSweep * Double(animatedProgress))
                                ),
                                style: StrokeStyle(lineWidth: strokeW, lineCap: .round)
                            )
                    } else {
                        SpeedometerArcShape(progress: animatedProgress, sweepDegrees: speedoSweep, radius: radius, centerY: centerY)
                            .stroke(fillCol, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                    }

                    // Needle — rotated around its own hub center, then positioned at arc center
                    let needleLen = radius - strokeW / 2 - 12
                    let needleAngleFromUp = -speedoSweep / 2.0 + speedoSweep * Double(animatedProgress)
                    ZStack {
                        Capsule()
                            .fill(needleCol)
                            .frame(width: needleW, height: needleLen)
                            .offset(y: -needleLen / 2)
                            .rotationEffect(.degrees(needleAngleFromUp))
                        Circle()
                            .fill(needleCol)
                            .frame(width: max(12, needleW * 3.5), height: max(12, needleW * 3.5))
                    }
                    .position(x: centerX, y: centerY)

                    // Min/Max labels — positioned just below the arc endpoints
                    Text(minLabel)
                        .font(.system(size: minMaxFontSz, weight: .medium))
                        .foregroundColor(minMaxCol)
                        .fixedSize()
                        .position(
                            x: centerX - endpointOffsetX,
                            y: centerY + endpointOffsetY + strokeW / 2 + minMaxFontSz
                        )
                    Text(maxLabel)
                        .font(.system(size: minMaxFontSz, weight: .medium))
                        .foregroundColor(minMaxCol)
                        .fixedSize()
                        .position(
                            x: centerX + endpointOffsetX,
                            y: centerY + endpointOffsetY + strokeW / 2 + minMaxFontSz
                        )

                    // Center value label — positioned inside the "bowl" (below arc center line)
                    if pctLocation == "center" {
                        VStack(spacing: 2) {
                            Text(
                                showPct
                                    ? "\(Int(animatedProgress * 100))%"
                                    : ((block.text?.isEmpty == false) ? block.text! : "\(Int(value))")
                            )
                                .font(.system(size: labelFontSz, weight: .bold))
                                .foregroundColor(labelCol)
                            if let sub = block.sublabel, !sub.isEmpty {
                                Text(sub)
                                    .font(.system(size: min(labelFontSz * 0.5, 13)))
                                    .foregroundColor(labelCol.opacity(0.6))
                            }
                        }
                        .fixedSize()
                        .position(x: centerX, y: centerY + radius * 0.5)
                    }
                }
                .frame(width: size, height: frameHeight)
            } else {
                // Arc / radial variants use a regular square ZStack with Circle+trim
                ZStack {
                    switch variant {
                    case "radial":
                        Circle()
                            .stroke(trackCol, lineWidth: strokeW * 2)
                        if useGradient, let startHex = gradStartHex, let endHex = gradEndHex {
                            Circle()
                                .trim(from: 0, to: animatedProgress)
                                .stroke(
                                    AngularGradient(colors: [Color(hex: startHex), Color(hex: endHex)], center: .center, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * Double(animatedProgress))),
                                    style: StrokeStyle(lineWidth: strokeW * 2, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                        } else {
                            Circle()
                                .trim(from: 0, to: animatedProgress)
                                .stroke(fillCol, style: StrokeStyle(lineWidth: strokeW * 2, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        if pctLocation == "center" {
                            VStack(spacing: 2) {
                                Text(showPct ? "\(Int(animatedProgress * 100))%" : (block.text ?? "\(Int(value))"))
                                    .font(.system(size: labelFontSz, weight: .bold))
                                    .foregroundColor(labelCol)
                                if let sub = block.sublabel {
                                    Text(sub).font(.caption).foregroundColor(labelCol.opacity(0.7))
                                }
                            }
                        }

                    default: // "arc"
                        Circle()
                            .stroke(trackCol, lineWidth: strokeW)
                        if useGradient, let startHex = gradStartHex, let endHex = gradEndHex {
                            Circle()
                                .trim(from: 0, to: animatedProgress)
                                .stroke(
                                    AngularGradient(colors: [Color(hex: startHex), Color(hex: endHex)], center: .center, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * Double(animatedProgress))),
                                    style: StrokeStyle(lineWidth: strokeW, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                        } else {
                            Circle()
                                .trim(from: 0, to: animatedProgress)
                                .stroke(fillCol, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        if pctLocation == "center" {
                            VStack(spacing: 2) {
                                Text(showPct ? "\(Int(animatedProgress * 100))%" : (block.text ?? "\(Int(value))"))
                                    .font(.system(size: labelFontSz, weight: .bold))
                                    .foregroundColor(labelCol)
                                if let sub = block.sublabel {
                                    Text(sub).font(.caption).foregroundColor(labelCol.opacity(0.7))
                                }
                            }
                        }
                    }
                }
                .frame(width: size, height: size)
                .padding(strokeW / 2) // Prevent stroke clipping at frame edges
            }

            if showPct && pctLocation == "below" {
                Text("\(Int(animatedProgress * 100))%")
                    .font(.system(size: labelFontSz, weight: .bold))
                    .foregroundColor(labelCol)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if shouldAnimate {
                withAnimation(.easeInOut(duration: animDuration)) {
                    animatedProgress = targetProgress
                }
            } else {
                animatedProgress = targetProgress
            }
        }
    }

}

// MARK: - Date Wheel Picker Block View (SPEC-089d AC-023)

/// Multi-column date picker using native iOS wheel picker style.
struct DateWheelPickerBlockView: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var selectedDate: Date = {
        let cal = Calendar.current
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    }()
    @State private var showPicker = false
    @State private var showDateToast = false

    /// Parse relative date strings like "today", "-18y", "-100y", "+1y", "-30d", or ISO date "2000-01-01"
    private static func parseDate(_ str: String?) -> Date? {
        guard let str, !str.isEmpty else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed == "today" || trimmed == "now" { return Date() }
        let cal = Calendar.current
        // Relative: -18y, +1y, -30d, -6m
        let lastChar = trimmed.last
        if let lastChar, "dmy".contains(lastChar) {
            let numStr = String(trimmed.dropLast())
            if let amount = Int(numStr) {
                switch lastChar {
                case "d": return cal.date(byAdding: .day, value: amount, to: Date())
                case "m": return cal.date(byAdding: .month, value: amount, to: Date())
                case "y": return cal.date(byAdding: .year, value: amount, to: Date())
                default: break
                }
            }
        }
        // Absolute ISO date
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: str)
    }

    private var dateRange: ClosedRange<Date> {
        let cal = Calendar.current
        var minDate: Date
        var maxDate: Date

        // Start with wide defaults
        minDate = cal.date(byAdding: .year, value: -150, to: Date()) ?? Date.distantPast
        maxDate = cal.date(byAdding: .year, value: 50, to: Date()) ?? Date.distantFuture

        // Apply explicit min/max
        if let parsed = Self.parseDate(block.min_date) { minDate = parsed }
        if let parsed = Self.parseDate(block.max_date) { maxDate = parsed }

        // Apply allow_future / allow_past toggles
        if block.allow_future == false {
            let today = cal.startOfDay(for: Date())
            maxDate = min(maxDate, today)
        }
        if block.allow_past == false {
            let today = cal.startOfDay(for: Date())
            minDate = max(minDate, today)
        }

        return minDate...maxDate
    }

    var body: some View {
        let highlightCol = Color(hex: block.highlight_color ?? "#6366F1")
        let isFieldMode = block.picker_presentation == "field"
        // Read picker_mode from config (console saves "date" or "datetime")
        // Fall back to block type for legacy compatibility
        let components: DatePickerComponents = {
            let mode = block.picker_mode
            if mode == "datetime" || mode == "date_time" { return [.date, .hourAndMinute] }
            if mode == "time" { return [.hourAndMinute] }
            switch block.type {
            case .input_time: return [.hourAndMinute]
            case .input_datetime: return [.date, .hourAndMinute]
            default: return [.date]
            }
        }()

        // Read picker_variant from field_config (console option): "graphical" | "wheel" | "compact".
        // When in datetime mode we default to "wheel" because graphical+wheel
        // stacked vertically exceeds most screen heights and gets clipped by the
        // pinned CTA button. Date-only can still default to "graphical" (calendar).
        let explicitVariant = (block.field_config?["picker_variant"]?.value as? String)
            ?? (block.field_config?["date_picker_variant"]?.value as? String)
        let isDatetimeMode = components.contains(.date) && components.contains(.hourAndMinute)
        let variant = explicitVariant ?? (isDatetimeMode ? "wheel" : "graphical")
        // Read additional styling options from field_config
        let calendarBg = (block.field_config?["calendar_bg_color"]?.value as? String)
            ?? block.calendar_bg_color ?? "#FFFFFF"
        let wheelBg = (block.field_config?["wheel_bg_color"]?.value as? String) ?? calendarBg
        let pickerCornerRadius = CGFloat((cfgDouble(block.field_config?["picker_corner_radius"])) ?? 12)
        let wheelTextColorHex = (block.field_config?["wheel_text_color"]?.value as? String)
        let pickerBorderColor = (block.field_config?["picker_border_color"]?.value as? String)
        let pickerBorderWidth = CGFloat((cfgDouble(block.field_config?["picker_border_width"])) ?? 0)
        let pickerPadding = CGFloat((cfgDouble(block.field_config?["picker_padding"])) ?? 0)

        VStack(spacing: 8) {
            if isFieldMode {
                // Field mode: tap to open
                Button {
                    withAnimation { showPicker.toggle() }
                } label: {
                    HStack {
                        Text(formatDate(selectedDate, components: components))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: components == [.hourAndMinute] ? "clock" : "calendar")
                            .foregroundColor(highlightCol)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)

                if showPicker {
                    datePickerContent(
                        components: components,
                        variant: variant,
                        highlightCol: highlightCol,
                        calendarBg: calendarBg,
                        wheelBg: wheelBg,
                        pickerCornerRadius: pickerCornerRadius,
                        wheelTextColorHex: wheelTextColorHex,
                        pickerBorderColor: pickerBorderColor,
                        pickerBorderWidth: pickerBorderWidth,
                        pickerPadding: pickerPadding,
                        defaultSpacing: 16
                    )
                }
            } else {
                // Inline mode (default)
                datePickerContent(
                    components: components,
                    variant: variant,
                    highlightCol: highlightCol,
                    calendarBg: calendarBg,
                    wheelBg: wheelBg,
                    pickerCornerRadius: pickerCornerRadius,
                    wheelTextColorHex: wheelTextColorHex,
                    pickerBorderColor: pickerBorderColor,
                    pickerBorderWidth: pickerBorderWidth,
                    pickerPadding: pickerPadding,
                    defaultSpacing: 8
                )
            }
        }
        .onChange(of: selectedDate) { newDate in
            // Clamp to valid range and show toast if out of bounds
            let range = dateRange
            if newDate < range.lowerBound {
                selectedDate = range.lowerBound
                showDateValidationToast()
            } else if newDate > range.upperBound {
                selectedDate = range.upperBound
                showDateValidationToast()
            }
            persistDate()
        }
        .onAppear { restoreDate() }
        .overlay(alignment: .bottom) {
            if showDateToast {
                Text(block.date_validation_message ?? defaultValidationMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(12)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var defaultValidationMessage: String {
        if block.allow_future == false { return "Please select a date in the past" }
        if block.allow_past == false { return "Please select a future date" }
        return "Please select a valid date"
    }

    private func showDateValidationToast() {
        withAnimation { showDateToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showDateToast = false }
        }
    }

    private func persistDate() {
        let fieldId = block.field_id ?? block.id
        let formatter = ISO8601DateFormatter()
        inputValues[fieldId] = formatter.string(from: selectedDate)
    }

    private func restoreDate() {
        let fieldId = block.field_id ?? block.id
        if let saved = inputValues[fieldId] as? String {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: saved) {
                selectedDate = date
            }
        }
    }

    private func formatDate(_ date: Date, components: DatePickerComponents) -> String {
        let f = DateFormatter()
        if components.contains(.date) && components.contains(.hourAndMinute) {
            f.dateStyle = .medium; f.timeStyle = .short
        } else if components.contains(.hourAndMinute) {
            f.dateStyle = .none; f.timeStyle = .short
        } else {
            f.dateStyle = .medium; f.timeStyle = .none
        }
        return f.string(from: date)
    }

    // MARK: - Date Picker Rendering Helper
    @ViewBuilder
    private func datePickerContent(
        components: DatePickerComponents,
        variant: String,
        highlightCol: Color,
        calendarBg: String,
        wheelBg: String,
        pickerCornerRadius: CGFloat,
        wheelTextColorHex: String?,
        pickerBorderColor: String?,
        pickerBorderWidth: CGFloat,
        pickerPadding: CGFloat,
        defaultSpacing: CGFloat
    ) -> some View {
        let spacing = CGFloat(block.picker_spacing ?? Double(defaultSpacing))
        let useWheel = variant == "wheel"
        let useCompact = variant == "compact"

        if components.contains(.date) && components.contains(.hourAndMinute) {
            // DateTime: date above, time wheel below (user requested this order)
            VStack(spacing: spacing) {
                datePart(
                    components: [.date],
                    useWheel: useWheel,
                    useCompact: useCompact,
                    highlightCol: highlightCol,
                    bgHex: calendarBg,
                    wheelBgHex: wheelBg,
                    cornerRadius: pickerCornerRadius,
                    wheelTextColorHex: wheelTextColorHex,
                    pickerBorderColor: pickerBorderColor,
                    pickerBorderWidth: pickerBorderWidth,
                    pickerPadding: pickerPadding
                )
                datePart(
                    components: [.hourAndMinute],
                    useWheel: true, // Time is always wheel
                    useCompact: useCompact,
                    highlightCol: highlightCol,
                    bgHex: wheelBg,
                    wheelBgHex: wheelBg,
                    cornerRadius: pickerCornerRadius,
                    wheelTextColorHex: wheelTextColorHex,
                    pickerBorderColor: pickerBorderColor,
                    pickerBorderWidth: pickerBorderWidth,
                    pickerPadding: pickerPadding
                )
            }
        } else if components.contains(.date) {
            datePart(
                components: [.date],
                useWheel: useWheel,
                useCompact: useCompact,
                highlightCol: highlightCol,
                bgHex: calendarBg,
                wheelBgHex: wheelBg,
                cornerRadius: pickerCornerRadius,
                wheelTextColorHex: wheelTextColorHex,
                pickerBorderColor: pickerBorderColor,
                pickerBorderWidth: pickerBorderWidth,
                pickerPadding: pickerPadding
            )
        } else {
            // Time-only
            datePart(
                components: [.hourAndMinute],
                useWheel: true,
                useCompact: useCompact,
                highlightCol: highlightCol,
                bgHex: wheelBg,
                wheelBgHex: wheelBg,
                cornerRadius: pickerCornerRadius,
                wheelTextColorHex: wheelTextColorHex,
                pickerBorderColor: pickerBorderColor,
                pickerBorderWidth: pickerBorderWidth,
                pickerPadding: pickerPadding
            )
        }
    }

    @ViewBuilder
    private func datePart(
        components: DatePickerComponents,
        useWheel: Bool,
        useCompact: Bool,
        highlightCol: Color,
        bgHex: String,
        wheelBgHex: String,
        cornerRadius: CGFloat,
        wheelTextColorHex: String?,
        pickerBorderColor: String?,
        pickerBorderWidth: CGFloat,
        pickerPadding: CGFloat
    ) -> some View {
        let bg = Color(hex: bgHex)
        let isTime = components == [.hourAndMinute]
        let picker: AnyView = {
            if useWheel || isTime {
                let base = DatePicker("", selection: $selectedDate, in: dateRange, displayedComponents: components)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .tint(highlightCol)
                    .frame(maxWidth: .infinity)
                if let hex = wheelTextColorHex {
                    return AnyView(base.colorMultiply(Color(hex: hex)))
                }
                return AnyView(base)
            } else if useCompact {
                return AnyView(
                    DatePicker("", selection: $selectedDate, in: dateRange, displayedComponents: components)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(highlightCol)
                        .frame(maxWidth: .infinity)
                )
            } else {
                // Default: graphical calendar
                return AnyView(
                    DatePicker("", selection: $selectedDate, in: dateRange, displayedComponents: components)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(highlightCol)
                )
            }
        }()

        picker
            .padding(pickerPadding)
            .background(bg)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        Color(hex: pickerBorderColor ?? "#00000000"),
                        lineWidth: pickerBorderWidth
                    )
            )
    }
}

// MARK: - Wheel Picker Block View (SPEC-089d AC-013)

/// Numeric wheel picker for single-value selection.
struct WheelPickerBlockView: View {
    let block: ContentBlock

    @State private var selectedIndex: Int = 0

    var body: some View {
        let minVal = block.min_value ?? 0
        let maxVal = block.max_value_picker ?? 100
        let step = block.step_value ?? 1
        let defaultVal = block.default_picker_value ?? minVal
        let unitStr = block.unit ?? ""
        let unitPos = block.unit_position ?? "after"
        let highlightCol = Color(hex: block.highlight_color ?? block.active_color ?? "#6366F1")

        // Generate values
        let values: [Double] = {
            var vals: [Double] = []
            var current = minVal
            while current <= maxVal {
                vals.append(current)
                current += step
            }
            return vals.isEmpty ? [0] : vals
        }()

        let initialIndex = values.firstIndex(where: { $0 >= defaultVal }) ?? 0

        let isHorizontal = block.wheel_orientation == "horizontal" || block.orientation == "horizontal"

        VStack(spacing: 8) {
            if let label = block.rating_label ?? block.text {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if isHorizontal {
                // Horizontal snap scroll picker
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(0..<values.count, id: \.self) { idx in
                                let val = values[idx]
                                let formatted = val == val.rounded() ? String(Int(val)) : String(format: "%.1f", val)
                                let display = unitPos == "before" ? "\(unitStr)\(formatted)" : "\(formatted)\(unitStr)"
                                Button {
                                    withAnimation { selectedIndex = idx }
                                } label: {
                                    Text(display)
                                        .font(.system(size: selectedIndex == idx ? 28 : 18, weight: selectedIndex == idx ? .bold : .regular))
                                        .foregroundColor(selectedIndex == idx ? highlightCol : .gray)
                                        .frame(width: 60, height: 50)
                                }
                                .id(idx)
                            }
                        }
                        .padding(.horizontal, UIScreen.main.bounds.width / 2 - 30)
                    }
                    .onAppear { proxy.scrollTo(initialIndex, anchor: .center) }
                    .onChange(of: selectedIndex) { idx in
                        withAnimation { proxy.scrollTo(idx, anchor: .center) }
                    }
                }
                .frame(height: 60)
            } else {
                // Vertical wheel picker (default)
                Picker("", selection: $selectedIndex) {
                    ForEach(0..<values.count, id: \.self) { idx in
                        let val = values[idx]
                        let formatted = val == val.rounded() ? String(Int(val)) : String(format: "%.1f", val)
                        let display = unitPos == "before" ? "\(unitStr)\(formatted)" : "\(formatted)\(unitStr)"
                        Text(display).tag(idx)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .tint(highlightCol)
            }
        }
        .onAppear {
            selectedIndex = initialIndex
        }
    }
}

// MARK: - Pulsing Avatar Block View (SPEC-089d AC-014)

/// Avatar image with animated pulsing ring effects.
struct PulsingAvatarBlockView: View {
    let block: ContentBlock

    @State private var isPulsing = false

    var body: some View {
        let avatarSize = CGFloat(block.icon_size ?? block.height ?? 80)
        let pulseCol = Color(hex: block.pulse_color ?? "#6366F1")
        let ringCount = block.pulse_ring_count ?? 3
        let pulseDuration = block.pulse_speed ?? 1.5
        let borderW = CGFloat(block.border_width ?? 0)
        let borderCol = Color(hex: block.border_color ?? "#FFFFFF")

        let align: Alignment = {
            switch block.alignment {
            case "left": return .leading
            case "right": return .trailing
            default: return .center
            }
        }()

        ZStack {
            // Pulse rings
            ForEach(0..<ringCount, id: \.self) { ringIndex in
                Circle()
                    .stroke(pulseCol.opacity(0.3), lineWidth: 2)
                    .frame(width: avatarSize + CGFloat(ringIndex + 1) * 20,
                           height: avatarSize + CGFloat(ringIndex + 1) * 20)
                    .scaleEffect(isPulsing ? 1.2 : 1.0)
                    .opacity(isPulsing ? 0 : 0.6)
                    .animation(
                        Animation.easeInOut(duration: pulseDuration)
                            .repeatForever(autoreverses: false)
                            .delay(pulseDuration / Double(ringCount) * Double(ringIndex)),
                        value: isPulsing
                    )
            }

            // Avatar image
            Group {
                if let urlString = block.image_url, let url = URL(string: urlString) {
                    BundledAsyncPhaseImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        default:
                            Circle().fill(Color.gray.opacity(0.2))
                        }
                    }
                } else {
                    Circle().fill(Color.gray.opacity(0.2))
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: avatarSize * 0.4))
                                .foregroundColor(.gray)
                        )
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
            .overlay(
                borderW > 0
                    ? Circle().stroke(borderCol, lineWidth: borderW)
                    : nil
            )

            // Badge
            if let badgeText = block.badge_text, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Color(hex: block.badge_text_color ?? "#FFFFFF"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: block.badge_bg_color ?? "#EF4444"))
                    .clipShape(Capsule())
                    .offset(x: avatarSize * 0.35, y: -avatarSize * 0.35)
            }
        }
        // Ensure enough space for the outermost pulsing ring at max scale
        .frame(
            width: avatarSize + CGFloat(ringCount + 1) * 20 * 1.3,
            height: avatarSize + CGFloat(ringCount + 1) * 20 * 1.3
        )
        .frame(maxWidth: .infinity, alignment: align)
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Star Background Block View (SPEC-089d AC-027)

/// Animated star/particle background using Canvas + TimelineView.
struct StarBackgroundBlockView: View {
    let block: ContentBlock

    @State private var particles: [StarParticle] = []
    @State private var isActive = true

    var body: some View {
        let color = Color(hex: block.active_color ?? block.text_color ?? "#FFFFFF")
        let opacity = block.block_style?.opacity ?? 0.8
        let particleCount: Int = {
            switch block.density {
            case "sparse": return 20
            case "dense": return 100
            default: return 50
            }
        }()
        let speedFactor: CGFloat = {
            switch block.speed {
            case "slow": return 0.3
            case "fast": return 1.5
            default: return 0.8
            }
        }()
        let minSize = CGFloat(block.size_range?.first ?? 1)
        let maxSize = CGFloat(block.size_range?.last ?? 3)
        let isFullscreen = block.fullscreen ?? false
        let height = CGFloat(block.height ?? 200)

        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            Canvas { context, size in
                for particle in particles {
                    let rect = CGRect(
                        x: particle.x,
                        y: particle.y,
                        width: particle.size,
                        height: particle.size
                    )
                    context.opacity = particle.opacity * opacity
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(color)
                    )
                }
            }
            .onChange(of: timeline.date) { _ in
                updateParticles(speedFactor: speedFactor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: isFullscreen ? .infinity : height)
        .clipped()
        .onAppear {
            initializeParticles(count: particleCount, minSize: minSize, maxSize: maxSize)
        }
        .onDisappear {
            isActive = false
        }
    }

    private func initializeParticles(count: Int, minSize: CGFloat, maxSize: CGFloat) {
        particles = (0..<count).map { _ in
            StarParticle(
                x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                y: CGFloat.random(in: 0...(UIScreen.main.bounds.height)),
                size: CGFloat.random(in: minSize...maxSize),
                opacity: Double.random(in: 0.2...1.0),
                speed: CGFloat.random(in: 0.2...1.0)
            )
        }
    }

    private func updateParticles(speedFactor: CGFloat) {
        for i in particles.indices {
            particles[i].y += particles[i].speed * speedFactor
            particles[i].opacity += Double.random(in: -0.02...0.02)
            particles[i].opacity = max(0.1, min(1.0, particles[i].opacity))

            // Wrap around when particle falls off screen
            if particles[i].y > UIScreen.main.bounds.height {
                particles[i].y = -particles[i].size
                particles[i].x = CGFloat.random(in: 0...UIScreen.main.bounds.width)
            }
        }
    }
}

// MARK: - Pricing Card Block View (SPEC-089d Nurrai)

/// Renders pricing plan cards in stack or side-by-side layout.
struct PricingCardBlockView: View {
    let block: ContentBlock
    let onAction: (_ action: String, _ actionValue: String?) -> Void

    @State private var selectedPlanId: String? = nil

    var body: some View {
        let plans = block.pricing_plans ?? []
        let isSideBySide = block.pricing_layout == "side_by_side"
        let accentCol = Color(hex: block.active_color ?? block.bg_color ?? "#6366F1")

        Group {
            if isSideBySide {
                HStack(spacing: 12) {
                    ForEach(plans) { plan in
                        planCard(plan, accent: accentCol)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(plans) { plan in
                        planCard(plan, accent: accentCol)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func planCard(_ plan: PricingPlanConfig, accent: Color) -> some View {
        let isHighlighted = plan.is_highlighted ?? false
        let isSelected = selectedPlanId == plan.id

        return Button {
            selectedPlanId = plan.id
            onAction("select_plan", plan.id)
        } label: {
            VStack(spacing: 6) {
                // Badge
                if let badge = plan.badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(accent)
                        .clipShape(Capsule())
                }

                Text(plan.label ?? "")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)

                Text(plan.price ?? "")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)

                Text(plan.period ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(isSelected ? accent.opacity(0.05) : Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? accent : (isHighlighted ? accent : Color.gray.opacity(0.3)),
                        lineWidth: isSelected || isHighlighted ? 2 : 1
                    )
            )
            .shadow(color: isHighlighted ? accent.opacity(0.15) : .clear, radius: 4, y: 2)
        }
    }
}
