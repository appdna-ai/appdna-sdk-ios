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

    var body: some View {
        let variant = block.loading_variant ?? "checklist"
        let itemList = block.loading_items ?? []
        let progressCol = Color(hex: block.progress_color ?? "#6366F1")
        let checkCol = Color(hex: block.check_color ?? "#22C55E")
        let totalMs = block.total_duration_ms ?? itemList.reduce(0) { $0 + ($1.duration_ms ?? 1000) }

        VStack(spacing: 16) {
            if block.show_percentage == true {
                Text("\(Int(overallProgress * 100))%")
                    .font(.title2.weight(.bold))
                    .foregroundColor(progressCol)
            }

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
        case "circular":
            return AnyView(
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                        .frame(width: 80, height: 80)
                    Circle()
                        .trim(from: 0, to: overallProgress)
                        .stroke(progressCol, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: overallProgress)
                }
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

// MARK: - Circular Gauge Block View (SPEC-089d AC-022)

/// Renders a circular arc gauge with center label. Supports animated fill.
struct CircularGaugeBlockView: View {
    let block: ContentBlock

    @State private var animatedProgress: CGFloat = 0

    var body: some View {
        let value = CGFloat(block.gauge_value ?? block.progress_value ?? 0)
        let maxVal = CGFloat(block.max_value ?? 100)
        let targetProgress = maxVal > 0 ? min(value / maxVal, 1.0) : 0
        let size = CGFloat(block.height ?? 120)
        let strokeW = CGFloat(block.stroke_width ?? 10)
        let fillCol = Color(hex: block.bar_color ?? block.active_color ?? "#6366F1")
        let trackCol = Color(hex: block.track_color ?? "#E5E7EB")
        let labelCol = Color(hex: block.label_color ?? block.text_color ?? "#000000")
        let labelFontSz = CGFloat(block.label_font_size ?? block.font_size ?? 20)
        let shouldAnimate = block.animate ?? true
        let animDuration = Double(block.animation_duration_ms ?? 800) / 1000.0
        let showPct = block.show_percentage ?? false

        ZStack {
            // Track
            Circle()
                .stroke(trackCol, lineWidth: strokeW)
            // Filled arc
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(fillCol, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Center label
            VStack(spacing: 2) {
                Text(showPct ? "\(Int(animatedProgress * 100))%" : (block.text ?? "\(Int(value))"))
                    .font(.system(size: labelFontSz, weight: .bold))
                    .foregroundColor(labelCol)
                if let sub = block.sublabel {
                    Text(sub)
                        .font(.caption)
                        .foregroundColor(labelCol.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
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

    @State private var selectedDate = Date()
    @State private var showPicker = false

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
                        Image(systemName: "calendar")
                            .foregroundColor(highlightCol)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)

                if showPicker {
                    DatePicker("", selection: $selectedDate, displayedComponents: components)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .accentColor(highlightCol)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            } else {
                // Inline mode (default)
                DatePicker("", selection: $selectedDate, displayedComponents: components)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .accentColor(highlightCol)
                    .frame(maxWidth: .infinity)
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
                .accentColor(highlightCol)
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
                    AsyncImage(url: url) { phase in
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
