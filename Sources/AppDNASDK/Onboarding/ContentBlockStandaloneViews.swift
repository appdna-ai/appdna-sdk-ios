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

// MARK: - Circular Gauge Block View (SPEC-089d AC-022)

/// Renders a circular arc gauge with center label. Supports animated fill.
struct CircularGaugeBlockView: View {
    let block: ContentBlock

    @State private var animatedProgress: CGFloat = 0

    var body: some View {
        let value = CGFloat(block.gauge_value ?? block.progress_value ?? 0)
        let minVal = CGFloat(block.min_value ?? 0)
        let maxVal = CGFloat(block.max_value ?? 100)
        let targetProgress = (maxVal - minVal) > 0 ? min((value - minVal) / (maxVal - minVal), 1.0) : 0
        let size = CGFloat(block.height ?? 200)
        let strokeW = CGFloat(block.stroke_width ?? 12)
        let fillCol = Color(hex: block.bar_color ?? block.active_color ?? "#6366F1")
        let trackCol = Color(hex: block.track_color ?? "#E5E7EB")
        let labelCol = Color(hex: block.label_color ?? block.text_color ?? "#000000")
        let labelFontSz = CGFloat(block.label_font_size ?? block.font_size ?? 24)
        let shouldAnimate = block.animate ?? true
        let animDuration = Double(block.animation_duration_ms ?? 800) / 1000.0
        let showPct = block.show_percentage ?? false

        let variant = block.gauge_variant ?? "arc"

        let needleCol = Color(hex: block.border_color ?? block.label_color ?? block.text_color ?? "#1F2937")
        let minLabel = block.min_label ?? "\(Int(minVal))"
        let maxLabel = block.max_label ?? "\(Int(maxVal))"
        let minMaxFontSz = CGFloat(block.min_max_font_size ?? 13)

        VStack(spacing: 8) {
            ZStack {
                switch variant {
                case "speedometer":
                    // Thick semi-circle arc (220° sweep for a wider speedometer look)
                    let sweepAngle: Double = 220
                    let startAngle: Double = 160 // Start from lower-left
                    let trimStart: CGFloat = CGFloat(startAngle) / 360.0
                    let trimEnd: CGFloat = CGFloat(startAngle + sweepAngle) / 360.0

                    // Track
                    Circle()
                        .trim(from: trimStart, to: trimEnd)
                        .stroke(trackCol, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                    // Fill
                    Circle()
                        .trim(from: trimStart, to: trimStart + (trimEnd - trimStart) * animatedProgress)
                        .stroke(fillCol, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                    // Needle
                    let needleAngle = startAngle + sweepAngle * Double(animatedProgress)
                    let needleLen = size / 2 - strokeW * 1.5 - 12
                    ZStack {
                        // Needle line
                        Capsule()
                            .fill(needleCol)
                            .frame(width: 3, height: needleLen)
                            .offset(y: -needleLen / 2)
                            .rotationEffect(.degrees(needleAngle + 90))
                        // Center dot
                        Circle()
                            .fill(needleCol)
                            .frame(width: 10, height: 10)
                    }

                    // Center value below needle
                    VStack(spacing: 2) {
                        Text(showPct ? "\(Int(animatedProgress * 100))%" : (block.text ?? "\(Int(value))"))
                            .font(.system(size: labelFontSz, weight: .bold))
                            .foregroundColor(labelCol)
                        if let sub = block.sublabel {
                            Text(sub)
                                .font(.system(size: min(labelFontSz * 0.5, 13)))
                                .foregroundColor(labelCol.opacity(0.6))
                        }
                    }
                    .offset(y: size * 0.12)

                case "radial":
                    Circle()
                        .stroke(trackCol, lineWidth: strokeW * 2)
                    Circle()
                        .trim(from: 0, to: animatedProgress)
                        .stroke(fillCol, style: StrokeStyle(lineWidth: strokeW * 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(showPct ? "\(Int(animatedProgress * 100))%" : (block.text ?? "\(Int(value))"))
                            .font(.system(size: labelFontSz, weight: .bold))
                            .foregroundColor(labelCol)
                        if let sub = block.sublabel {
                            Text(sub).font(.caption).foregroundColor(labelCol.opacity(0.7))
                        }
                    }

                default: // "arc"
                    Circle()
                        .stroke(trackCol, lineWidth: strokeW)
                    Circle()
                        .trim(from: 0, to: animatedProgress)
                        .stroke(fillCol, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                        .rotationEffect(.degrees(-90))
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
            .frame(width: size, height: variant == "speedometer" ? size * 0.65 : size)

            // Min/Max labels
            if variant == "speedometer" {
                HStack {
                    Text(minLabel)
                        .font(.system(size: minMaxFontSz, weight: .medium))
                        .foregroundColor(labelCol.opacity(0.5))
                    Spacer()
                    Text(maxLabel)
                        .font(.system(size: minMaxFontSz, weight: .medium))
                        .foregroundColor(labelCol.opacity(0.5))
                }
                .frame(width: size * 0.75)
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

        // Read picker_variant from field_config (console option): "graphical" (default) | "wheel" | "compact"
        let variant = (block.field_config?["picker_variant"]?.value as? String)
            ?? (block.field_config?["date_picker_variant"]?.value as? String)
            ?? "graphical"
        // Read additional styling options from field_config
        let calendarBg = (block.field_config?["calendar_bg_color"]?.value as? String)
            ?? block.calendar_bg_color ?? "#FFFFFF"
        let wheelBg = (block.field_config?["wheel_bg_color"]?.value as? String) ?? calendarBg
        let pickerCornerRadius = CGFloat((block.field_config?["picker_corner_radius"]?.value as? Double) ?? 12)
        let wheelTextColorHex = (block.field_config?["wheel_text_color"]?.value as? String)
        let pickerBorderColor = (block.field_config?["picker_border_color"]?.value as? String)
        let pickerBorderWidth = CGFloat((block.field_config?["picker_border_width"]?.value as? Double) ?? 0)
        let pickerPadding = CGFloat((block.field_config?["picker_padding"]?.value as? Double) ?? 0)

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
                    .accentColor(highlightCol)
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
                        .accentColor(highlightCol)
                        .tint(highlightCol)
                        .frame(maxWidth: .infinity)
                )
            } else {
                // Default: graphical calendar
                return AnyView(
                    DatePicker("", selection: $selectedDate, in: dateRange, displayedComponents: components)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .accentColor(highlightCol)
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
