import SwiftUI
import MapKit
import PhotosUI
// MARK: - Form Input Block Views (SPEC-089d Phase 3: AC-040 through AC-053)

/// Helper view to render a form field label above the input control.
struct FormFieldLabelView: View {
    let block: ContentBlock

    var body: some View {
        if let label = block.field_label ?? block.rating_label ?? block.text, !label.isEmpty {
            let required = block.field_required ?? false
            HStack(spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Color(hex: block.field_style?.label_color ?? "#374151"))
                if required {
                    Text("*")
                        .foregroundColor(.red)
                }
            }
        }
    }
}

/// Helper function for calling FormFieldLabelView from within views.
@ViewBuilder
func formFieldLabel(_ block: ContentBlock) -> some View {
    FormFieldLabelView(block: block)
}

/// Extract a numeric value from AnyCodable, handling both Int and Double.
/// JSON integers decode as Int via AnyCodable, so `as? Double` silently fails.
func cfgDouble(_ val: AnyCodable?) -> Double? {
    guard let v = val?.value else { return nil }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return nil
}

/// Gradient direction helpers for angle-based gradients.
func gradientStart(_ angleDeg: Double) -> UnitPoint {
    let rad = angleDeg * .pi / 180
    return UnitPoint(x: 0.5 - cos(rad) * 0.5, y: 0.5 + sin(rad) * 0.5)
}
func gradientEnd(_ angleDeg: Double) -> UnitPoint {
    let rad = angleDeg * .pi / 180
    return UnitPoint(x: 0.5 + cos(rad) * 0.5, y: 0.5 - sin(rad) * 0.5)
}

/// Read configurable field height — checks element_height first (console sizing),
/// then falls back to field_config.field_height (legacy).
/// Returns nil if neither is set.
func fieldHeight(_ block: ContentBlock) -> CGFloat? {
    // element_height takes priority (set via console height control)
    if let eh = block.element_height {
        if let sv = SizeValue.parse(eh) {
            switch sv {
            case .px(let val): return val
            case .percent(let frac): return UIScreen.main.bounds.height * frac
            default: break
            }
        }
    }
    // Fallback: field_config.field_height (points)
    return cfgDouble(block.field_config?["field_height"]).map { CGFloat($0) }
}

/// Generic text-based input (text, number, email, phone, url).
struct FormInputTextBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]
    let keyboardType: UIKeyboardType

    @State private var text: String = ""

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let placeholder = block.field_placeholder ?? block.text ?? ""
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)
        // Read keyboard appearance from field_config (console option):
        // "default" (respect device) | "light" | "dark"
        let keyboardAppearanceRaw = block.field_config?["keyboard_appearance"]?.value as? String
        let useUIKitField = keyboardAppearanceRaw == "light" || keyboardAppearanceRaw == "dark"

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            Group {
                if useUIKitField {
                    // Use UIKit-backed field to get explicit keyboardAppearance control
                    UIKitTextField(
                        text: $text,
                        placeholder: placeholder,
                        keyboardType: keyboardType,
                        keyboardAppearance: .from(keyboardAppearanceRaw),
                        returnKeyType: .done
                    )
                    .frame(height: 24)
                } else {
                    // Default SwiftUI TextField — unchanged behavior
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textFieldStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .frame(minHeight: fieldHeight(block), alignment: .center)
            .background(Color(hex: block.field_style?.background_color ?? "#FFFFFF"))
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: CGFloat(block.field_style?.border_width ?? 1))
            )
            .onChange(of: text) { newValue in
                inputValues[fieldId] = newValue
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if text.isEmpty, let saved = inputValues[fieldId] as? String { text = saved } }
    }
}

/// Multi-line text area input.
struct FormInputTextAreaBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var text: String = ""

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)
        let minLines = (block.field_config?["min_lines"]?.value as? Int) ?? 3

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            TextEditor(text: $text)
                .frame(minHeight: CGFloat(minLines * 22))
                .padding(4)
                .background(Color(hex: block.field_style?.background_color ?? "#FFFFFF"))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: CGFloat(block.field_style?.border_width ?? 1))
                )
                .onChange(of: text) { newValue in
                    inputValues[fieldId] = newValue
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if text.isEmpty, let saved = inputValues[fieldId] as? String { text = saved } }
    }
}

/// Password input with show/hide toggle.
struct FormInputPasswordBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var text: String = ""
    @State private var showPassword: Bool = false

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let placeholder = block.field_placeholder ?? "Password"
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)
        let keyboardAppearanceRaw = block.field_config?["keyboard_appearance"]?.value as? String
        let useUIKitField = keyboardAppearanceRaw == "light" || keyboardAppearanceRaw == "dark"

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            HStack {
                Group {
                    if useUIKitField {
                        UIKitTextField(
                            text: $text,
                            placeholder: placeholder,
                            keyboardAppearance: .from(keyboardAppearanceRaw),
                            isSecure: !showPassword,
                            textContentType: .password,
                            autocorrection: false,
                            autocapitalization: .none,
                            returnKeyType: .done
                        )
                        .frame(height: 24)
                    } else if showPassword {
                        TextField(placeholder, text: $text)
                            .textFieldStyle(.plain)
                    } else {
                        SecureField(placeholder, text: $text)
                            .textFieldStyle(.plain)
                    }
                }

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .frame(minHeight: fieldHeight(block))
            .background(Color(hex: block.field_style?.background_color ?? "#FFFFFF"))
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: CGFloat(block.field_style?.border_width ?? 1))
            )
            .onChange(of: text) { newValue in
                inputValues[fieldId] = newValue
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if text.isEmpty, let saved = inputValues[fieldId] as? String { text = saved } }
    }
}

/// Date, Time, or DateTime picker input.
struct FormInputDateBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]
    let components: DatePickerComponents

    @State private var selectedDate = Date()

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let accentColor = Color(hex: block.field_style?.fill_color ?? block.active_color ?? "#6366F1")

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            DatePicker(
                "",
                selection: $selectedDate,
                displayedComponents: components
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(accentColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: selectedDate) { newValue in
                let formatter = ISO8601DateFormatter()
                inputValues[fieldId] = formatter.string(from: newValue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Dropdown select input with display_style support (dropdown, stacked, grid).
struct FormInputSelectBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var selectedValue: String = ""
    @State private var selectedValues: Set<String> = []

    private var isMultiSelect: Bool {
        block.multi_select == true ||
        (block.field_config?["multi_select"]?.value as? Bool) == true
    }

    /// Read display_style from field_config; defaults to "dropdown".
    private var displayStyle: String {
        (block.field_config?["display_style"]?.value as? String) ?? "dropdown"
    }

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let options = block.field_options ?? []

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            switch displayStyle {
            case "stacked":
                stackedSelectView(options: options, fieldId: fieldId)
            case "grid":
                gridSelectView(options: options, fieldId: fieldId)
            default: // "dropdown"
                dropdownSelectView(options: options, fieldId: fieldId)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            let fieldId = block.field_id ?? block.id
            if selectedValue.isEmpty, let saved = inputValues[fieldId] as? String {
                selectedValue = saved
            }
            if selectedValues.isEmpty, let saved = inputValues[fieldId] as? [String] {
                selectedValues = Set(saved)
            }
        }
    }

    // MARK: - Dropdown (default)

    @ViewBuilder
    private func dropdownSelectView(options: [InputOption], fieldId: String) -> some View {
        Picker("", selection: $selectedValue) {
            Text(block.field_placeholder ?? "Select...").tag("")
            ForEach(options) { option in
                Text(option.label ?? "").tag(option.resolvedValue)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .frame(minHeight: fieldHeight(block), alignment: .center)
        .background(Color(hex: block.field_style?.background_color ?? "#FFFFFF"))
        .cornerRadius(CGFloat(block.field_style?.corner_radius ?? 8))
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(block.field_style?.corner_radius ?? 8))
                .stroke(Color(hex: block.field_style?.border_color ?? "#D1D5DB"), lineWidth: CGFloat(block.field_style?.border_width ?? 1))
        )
        .onChange(of: selectedValue) { newValue in
            inputValues[fieldId] = newValue
        }
    }

    // MARK: - Stacked (vertical cards with configurable selection indicator)

    @ViewBuilder
    private func stackedSelectView(options: [InputOption], fieldId: String) -> some View {
        let cfg = block.field_config
        let accentHex = block.field_style?.fill_color
            ?? block.field_style?.focused_border_color
            ?? block.active_color
            ?? "#6366F1"
        let fillCol = Color(hex: accentHex)
        let cornerR = CGFloat(block.field_style?.corner_radius ?? 10)

        // Colors from field_config
        let cfgOptBg = (cfg?["bg_color"]?.value as? String).map { Color(hex: $0) }
        let cfgOptText = (cfg?["text_color"]?.value as? String).map { Color(hex: $0) }
        let cfgOptBorder = (cfg?["border_color"]?.value as? String).map { Color(hex: $0) }
        let cfgSelectedBg = (cfg?["selected_bg_color"]?.value as? String).map { Color(hex: $0) }
        let cfgSelectedText = (cfg?["selected_text_color"]?.value as? String).map { Color(hex: $0) }

        let selectedBgCol = cfgSelectedBg ?? fillCol.opacity(0.15)
        let optionBg: Color = cfgOptBg
            ?? block.field_style?.background_color.map { Color(hex: $0) }
            ?? Color.white
        let textCol: Color = cfgOptText
            ?? block.field_style?.text_color.map { Color(hex: $0) }
            ?? block.text_color.map { Color(hex: $0) }
            ?? block.style?.color.map { Color(hex: $0) }
            ?? .primary
        let selectedTextCol: Color = cfgSelectedText ?? textCol
        let unselectedBorderCol: Color = cfgOptBorder
            ?? block.field_style?.border_color.map { Color(hex: $0) }
            ?? fillCol.opacity(0.3)

        // Selection indicator: "radio" (default), "border", "both", "none"
        let selectionIndicator = (cfg?["selection_indicator"]?.value as? String) ?? "radio"
        let showRadio = selectionIndicator == "radio" || selectionIndicator == "both"
        let showBorderHighlight = selectionIndicator == "border" || selectionIndicator == "both"
        // Radio fill: "circle" (default), "checkmark", or any emoji/SF Symbol
        let radioFill = (cfg?["radio_fill"]?.value as? String) ?? "circle"
        // Radio position
        let radioPosition = (cfg?["radio_position"]?.value as? String) ?? "right"
        let radioOnLeft = radioPosition == "left" || radioPosition == "leading"
        // Border widths
        let selectedBorderW = CGFloat((cfgDouble(cfg?["selected_border_width"])) ?? 2)
        let unselectedBorderW = CGFloat((cfgDouble(cfg?["unselected_border_width"])) ?? 1)
        // Background opacity + blur
        let bgOpacity = CGFloat((cfgDouble(cfg?["background_opacity"])) ?? 1.0)
        let useBlur = (cfg?["blur_background"]?.value as? Bool) == true

        // Text sizes
        let defaultTitleSize = (cfgDouble(cfg?["title_font_size"])) ?? 15
        let defaultSubtitleSize = (cfgDouble(cfg?["subtitle_font_size"])) ?? 12
        let defaultSubtitleColor = (cfg?["subtitle_color"]?.value as? String).map { Color(hex: $0) }
            ?? textCol.opacity(0.65)

        VStack(spacing: 8) {
            ForEach(options) { option in
                let isSelected = isMultiSelect
                    ? selectedValues.contains(option.resolvedValue)
                    : selectedValue == option.resolvedValue

                // Per-option color overrides — each option can have its own highlight
                let optSelectedBg = option.selected_bg_color.map { Color(hex: $0) } ?? selectedBgCol
                let optSelectedText = option.selected_text_color.map { Color(hex: $0) } ?? selectedTextCol
                let optTitleColor: Color = option.title_color.map { Color(hex: $0) }
                    ?? (isSelected ? optSelectedText : textCol)
                let optSubtitleColor: Color = option.subtitle_color.map { Color(hex: $0) }
                    ?? defaultSubtitleColor
                let optTitleSize: CGFloat = CGFloat(option.title_font_size ?? defaultTitleSize)
                let optSubtitleSize: CGFloat = CGFloat(option.subtitle_font_size ?? defaultSubtitleSize)
                let optTitleWeight: Font.Weight = fontWeight(option.title_font_weight)

                // Per-option border color overrides
                let optBorderCol = option.selected_border_color.map { Color(hex: $0) } ?? fillCol
                let optUnselBorderCol = option.border_color.map { Color(hex: $0) } ?? unselectedBorderCol

                Button {
                    toggleSelection(option: option, fieldId: fieldId)
                } label: {
                    HStack(spacing: 12) {
                        // Radio on left
                        if showRadio && radioOnLeft {
                            radioIndicator(isSelected: isSelected, fillCol: fillCol, radioFill: radioFill)
                        }
                        // Image with optional overlay circle
                        if let imgUrl = option.image_url, let url = URL(string: imgUrl) {
                            imageWithOverlay(url: url, option: option, isSelected: isSelected, size: 32)
                        }
                        if let icon = option.icon, !icon.isEmpty {
                            Text(icon)
                        }
                        // Title + subtitle — fixedSize vertical so text wraps fully
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label ?? "")
                                .font(.system(size: optTitleSize, weight: optTitleWeight))
                                .foregroundColor(optTitleColor)
                                .fixedSize(horizontal: false, vertical: true)
                            if let sub = option.subtitle, !sub.isEmpty {
                                Text(sub)
                                    .font(.system(size: optSubtitleSize))
                                    .foregroundColor(optSubtitleColor)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .layoutPriority(1)
                        Spacer(minLength: 0)
                        // Radio on right
                        if showRadio && !radioOnLeft {
                            radioIndicator(isSelected: isSelected, fillCol: fillCol, radioFill: radioFill)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        ZStack {
                            if useBlur {
                                RoundedRectangle(cornerRadius: cornerR)
                                    .fill(.ultraThinMaterial)
                            }
                            RoundedRectangle(cornerRadius: cornerR)
                                .fill((isSelected ? optSelectedBg : optionBg).opacity(bgOpacity))
                            if showBorderHighlight || selectionIndicator == "radio" || selectionIndicator == "none" {
                                RoundedRectangle(cornerRadius: cornerR)
                                    .strokeBorder(
                                        isSelected ? optBorderCol : optUnselBorderCol,
                                        lineWidth: isSelected && showBorderHighlight ? selectedBorderW : unselectedBorderW
                                    )
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Radio indicator helper

    @ViewBuilder
    private func radioIndicator(isSelected: Bool, fillCol: Color, radioFill: String) -> some View {
        switch radioFill {
        case "checkmark":
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? fillCol : .gray.opacity(0.4))
                .font(.title3)
        case "circle":
            Image(systemName: isSelected
                ? (isMultiSelect ? "checkmark.circle.fill" : "largecircle.fill.circle")
                : "circle")
                .foregroundColor(isSelected ? fillCol : .gray.opacity(0.4))
                .font(.title3)
        default:
            // Emoji or custom SF Symbol name
            if radioFill.count <= 2 && radioFill.unicodeScalars.allSatisfy({ $0.value > 127 }) {
                // Emoji
                Text(isSelected ? radioFill : "○")
                    .font(.title3)
            } else if UIImage(systemName: radioFill) != nil {
                // SF Symbol
                Image(systemName: isSelected ? radioFill : "circle")
                    .foregroundColor(isSelected ? fillCol : .gray.opacity(0.4))
                    .font(.title3)
            } else {
                // Fallback to default circle
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? fillCol : .gray.opacity(0.4))
                    .font(.title3)
            }
        }
    }

    // MARK: - Image with overlay circle helper

    @ViewBuilder
    private func imageWithOverlay(url: URL, option: InputOption, isSelected: Bool, size: CGFloat) -> some View {
        ZStack {
            BundledAsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Optional colored overlay circle
            if let overlayHex = option.image_overlay_color {
                let overlayOpacity = option.image_overlay_opacity ?? 0.3
                Circle()
                    .fill(Color(hex: overlayHex).opacity(overlayOpacity))
                    .frame(width: size, height: size)
            }
        }
    }

    // MARK: - Selection toggle helper

    private func toggleSelection(option: InputOption, fieldId: String) {
        if isMultiSelect {
            if selectedValues.contains(option.resolvedValue) {
                selectedValues.remove(option.resolvedValue)
            } else {
                selectedValues.insert(option.resolvedValue)
            }
            inputValues[fieldId] = Array(selectedValues)
        } else {
            selectedValue = option.resolvedValue
            inputValues[fieldId] = option.resolvedValue
        }
    }

    private func fontWeight(_ raw: String?) -> Font.Weight {
        switch raw {
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        default: return .regular
        }
    }

    // MARK: - Grid (configurable columns with toggle icons, blur, tooltip)

    @ViewBuilder
    private func gridSelectView(options: [InputOption], fieldId: String) -> some View {
        let cfg = block.field_config
        let accentHex = block.field_style?.fill_color
            ?? block.field_style?.focused_border_color
            ?? block.active_color
            ?? "#6366F1"
        let fillCol = Color(hex: accentHex)
        let cornerR = CGFloat(block.field_style?.corner_radius ?? 10)

        let cfgOptBg = (cfg?["bg_color"]?.value as? String).map { Color(hex: $0) }
        let cfgOptText = (cfg?["text_color"]?.value as? String).map { Color(hex: $0) }
        let cfgOptBorder = (cfg?["border_color"]?.value as? String).map { Color(hex: $0) }
        let cfgSelectedBg = (cfg?["selected_bg_color"]?.value as? String).map { Color(hex: $0) }
        let cfgSelectedText = (cfg?["selected_text_color"]?.value as? String).map { Color(hex: $0) }

        let selectedBgCol = cfgSelectedBg ?? fillCol.opacity(0.15)
        let optionBg: Color = cfgOptBg
            ?? block.field_style?.background_color.map { Color(hex: $0) }
            ?? Color.white
        let textCol: Color = cfgOptText
            ?? block.field_style?.text_color.map { Color(hex: $0) }
            ?? block.text_color.map { Color(hex: $0) }
            ?? block.style?.color.map { Color(hex: $0) }
            ?? .primary
        let selectedTextCol: Color = cfgSelectedText ?? textCol
        let unselectedBorderCol: Color = cfgOptBorder
            ?? block.field_style?.border_color.map { Color(hex: $0) }
            ?? fillCol.opacity(0.3)

        // Grid configuration
        let colCount = max(Int((cfgDouble(cfg?["grid_columns"])) ?? 2), 1)
        let selectedBorderW = CGFloat((cfgDouble(cfg?["selected_border_width"])) ?? 2)
        let unselectedBorderW = CGFloat((cfgDouble(cfg?["unselected_border_width"])) ?? 1)
        let bgOpacity = CGFloat((cfgDouble(cfg?["background_opacity"])) ?? 1.0)
        let useBlur = (cfg?["blur_background"]?.value as? Bool) == true
        // Default toggle icons for grid (per-option overrides take priority)
        let defaultSelectedIcon = (cfg?["selected_icon"]?.value as? String)
        let defaultUnselectedIcon = (cfg?["unselected_icon"]?.value as? String)
        // Show toggle icon overlay (top-right badge showing +/check)
        let showToggleIcon = (cfg?["show_toggle_icon"]?.value as? Bool) ?? (defaultSelectedIcon != nil)
        // Tooltip below grid
        let tooltipText = (cfg?["tooltip_text"]?.value as? String)
        let tooltipIcon = (cfg?["tooltip_icon"]?.value as? String) ?? "info.circle"

        VStack(spacing: 8) {
            // Manual grid — LazyVGrid clips wrapped text (ignores fixedSize for row height).
            let rowCount = (options.count + colCount - 1) / colCount
            ForEach(0..<rowCount, id: \.self) { rowIdx in
                HStack(spacing: 8) {
                    ForEach(0..<colCount, id: \.self) { colIdx in
                        let optIdx = rowIdx * colCount + colIdx
                        if optIdx < options.count {
                            let option = options[optIdx]
                            let isSelected = isMultiSelect
                                ? selectedValues.contains(option.resolvedValue)
                                : selectedValue == option.resolvedValue
                            let optBorderCol = option.selected_border_color.map { Color(hex: $0) } ?? fillCol
                            let optUnselBorderCol = option.border_color.map { Color(hex: $0) } ?? unselectedBorderCol
                            let optSelectedBg = option.selected_bg_color.map { Color(hex: $0) } ?? selectedBgCol
                            let optSelectedText = option.selected_text_color.map { Color(hex: $0) } ?? selectedTextCol

                            Button {
                                toggleSelection(option: option, fieldId: fieldId)
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    VStack(spacing: 6) {
                                        // Image with optional overlay
                                        if let imgUrl = option.image_url, let url = URL(string: imgUrl) {
                                            imageWithOverlay(url: url, option: option, isSelected: isSelected, size: 40)
                                        }
                                        // Icon with state change (selected/unselected variants)
                                        if let icon = option.icon, !icon.isEmpty {
                                            let resolvedIcon = isSelected
                                                ? (option.selected_icon ?? defaultSelectedIcon ?? icon)
                                                : (option.unselected_icon ?? defaultUnselectedIcon ?? icon)
                                            if UIImage(systemName: resolvedIcon) != nil {
                                                Image(systemName: resolvedIcon)
                                                    .font(.title2)
                                                    .foregroundColor(isSelected ? optSelectedText : textCol)
                                            } else {
                                                Text(resolvedIcon).font(.title2)
                                            }
                                        }
                                        // Label + subtitle
                                        Text(option.label ?? "")
                                            .font(.subheadline)
                                            .foregroundColor(isSelected ? optSelectedText : textCol)
                                            .multilineTextAlignment(.center)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if let sub = option.subtitle, !sub.isEmpty {
                                            Text(sub)
                                                .font(.caption)
                                                .foregroundColor(textCol.opacity(0.65))
                                                .multilineTextAlignment(.center)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(10)

                                    // Toggle icon badge (top-right)
                                    if showToggleIcon {
                                        let selIcon = option.selected_icon ?? defaultSelectedIcon ?? "checkmark"
                                        let unselIcon = option.unselected_icon ?? defaultUnselectedIcon ?? "plus"
                                        let badgeIcon = isSelected ? selIcon : unselIcon
                                        Group {
                                            if UIImage(systemName: badgeIcon) != nil {
                                                Image(systemName: badgeIcon)
                                                    .font(.system(size: 10, weight: .bold))
                                            } else {
                                                Text(badgeIcon).font(.system(size: 10))
                                            }
                                        }
                                        .foregroundColor(isSelected ? optSelectedText : textCol.opacity(0.5))
                                        .frame(width: 20, height: 20)
                                        .background(Circle().fill(isSelected ? fillCol.opacity(0.2) : Color.clear))
                                        .padding(6)
                                    }
                                }
                                .background {
                                    ZStack {
                                        if useBlur {
                                            RoundedRectangle(cornerRadius: cornerR)
                                                .fill(.ultraThinMaterial)
                                        }
                                        RoundedRectangle(cornerRadius: cornerR)
                                            .fill((isSelected ? optSelectedBg : optionBg).opacity(bgOpacity))
                                        RoundedRectangle(cornerRadius: cornerR)
                                            .strokeBorder(
                                                isSelected ? optBorderCol : optUnselBorderCol,
                                                lineWidth: isSelected ? selectedBorderW : unselectedBorderW
                                            )
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }

            // Tooltip below grid
            if let tooltip = tooltipText, !tooltip.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: tooltipIcon)
                        .font(.caption)
                        .foregroundColor(textCol.opacity(0.5))
                    Text(tooltip)
                        .font(.caption)
                        .foregroundColor(textCol.opacity(0.5))
                }
                .padding(.top, 4)
            }
        }
    }
}

/// Slider input for single numeric value.
struct FormInputSliderBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var value: Double = 50

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let minVal = block.min_value ?? 0
        let maxVal = block.max_value_picker ?? 100
        let stepVal = block.step_value ?? 1
        let showValue = (block.field_config?["show_value"]?.value as? Bool) ?? true
        let unitStr = block.unit ?? ""
        let trackCol = Color(hex: block.field_style?.track_color ?? block.track_color ?? "#E5E7EB")
        let fillCol = Color(hex: block.field_style?.fill_color ?? block.active_color ?? "#6366F1")

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                formFieldLabel(block)
                Spacer()
                if showValue {
                    let formatted = value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
                    Text("\(formatted)\(unitStr)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(fillCol)
                }
            }

            Slider(value: $value, in: minVal...maxVal, step: stepVal)
                .tint(fillCol)
                .onChange(of: value) { newValue in
                    inputValues[fieldId] = newValue
                }
        }
        .onAppear {
            if let saved = inputValues[fieldId] as? Double { value = saved }
            else { value = block.default_picker_value ?? minVal; inputValues[fieldId] = value }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Toggle (switch) input.
struct FormInputToggleBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var isOn: Bool = false

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let onColor = Color(hex: block.field_style?.toggle_on_color ?? "#6366F1")
        let label = block.field_label ?? block.toggle_label ?? ""

        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(onColor)
                .onChange(of: isOn) { newValue in
                    inputValues[fieldId] = newValue
                }
        }
        .onAppear {
            if let saved = inputValues[fieldId] as? Bool { isOn = saved }
            else { isOn = block.toggle_default ?? false; inputValues[fieldId] = isOn }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Stepper input for incrementing/decrementing numeric value.
struct FormInputStepperBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var value: Int = 0

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let minVal = Int(block.min_value ?? 0)
        let maxVal = Int(block.max_value_picker ?? 100)
        let stepVal = Int(block.step_value ?? 1)
        let unitStr = block.unit ?? ""

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            Stepper(value: $value, in: minVal...maxVal, step: stepVal) {
                Text("\(value)\(unitStr)")
                    .font(.body.weight(.medium))
            }
            .onChange(of: value) { newValue in
                inputValues[fieldId] = newValue
            }
        }
        .onAppear {
            if let saved = inputValues[fieldId] as? Int { value = saved }
            else { value = Int(block.default_picker_value ?? Double(minVal)); inputValues[fieldId] = value }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Segmented picker input.
struct FormInputSegmentedBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var selectedValue: String = ""

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let options = block.field_options ?? []

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            Picker("", selection: $selectedValue) {
                ForEach(options) { option in
                    Text(option.label ?? "").tag(option.resolvedValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedValue) { newValue in
                inputValues[fieldId] = newValue
            }
        }
        .onAppear {
            if let saved = inputValues[fieldId] as? String, !saved.isEmpty { selectedValue = saved }
            else if selectedValue.isEmpty, let first = options.first {
                selectedValue = first.resolvedValue
                inputValues[fieldId] = first.resolvedValue
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Star rating input (form variant -- reuses rating block logic).
struct FormInputRatingBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var selectedRating: Double = 0

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let maxStars = block.max_stars ?? 5
        let starSz = CGFloat(block.star_size ?? 32)
        let filledCol = Color(hex: block.filled_color ?? block.field_style?.fill_color ?? "#FBBF24")
        let emptyCol = Color(hex: block.empty_color ?? "#D1D5DB")

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            HStack(spacing: 4) {
                ForEach(1...maxStars, id: \.self) { index in
                    Image(systemName: selectedRating >= Double(index) ? "star.fill" : "star")
                        .font(.system(size: starSz))
                        .foregroundColor(selectedRating >= Double(index) ? filledCol : emptyCol)
                        .onTapGesture {
                            selectedRating = Double(index)
                            inputValues[fieldId] = selectedRating
                        }
                }
            }
        }
        .onAppear {
            let fieldId = block.field_id ?? block.id
            if let saved = inputValues[fieldId] as? Double { selectedRating = saved }
            else { selectedRating = block.default_rating ?? 0 }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Range slider (dual-thumb) input.
struct FormInputRangeSliderBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var lowValue: Double = 0
    @State private var highValue: Double = 100

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let minVal = block.min_value ?? 0
        let maxVal = block.max_value_picker ?? 100
        let unitStr = block.unit ?? ""
        let fillCol = Color(hex: block.field_style?.fill_color ?? block.active_color ?? "#6366F1")

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                formFieldLabel(block)
                Spacer()
                Text("\(Int(lowValue))\(unitStr) - \(Int(highValue))\(unitStr)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(fillCol)
            }

            VStack(spacing: 4) {
                HStack {
                    Text("Min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Slider(value: $lowValue, in: minVal...maxVal)
                        .tint(fillCol)
                }
                HStack {
                    Text("Max")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Slider(value: $highValue, in: minVal...maxVal)
                        .tint(fillCol)
                }
            }
            .onChange(of: lowValue) { _ in
                if lowValue > highValue { highValue = lowValue }
                inputValues[fieldId] = ["min": lowValue, "max": highValue]
            }
            .onChange(of: highValue) { _ in
                if highValue < lowValue { lowValue = highValue }
                inputValues[fieldId] = ["min": lowValue, "max": highValue]
            }
        }
        .onAppear {
            if let saved = inputValues[fieldId] as? [String: Any] {
                lowValue = saved["min"] as? Double ?? block.min_value ?? 0
                highValue = saved["max"] as? Double ?? block.max_value_picker ?? 100
            } else {
                lowValue = block.min_value ?? 0
                highValue = block.max_value_picker ?? 100
                inputValues[fieldId] = ["min": lowValue, "max": highValue]
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Chips/tag input -- multi-select toggleable chips.
struct FormInputChipsBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var selectedValues: Set<String> = []

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let options = block.field_options ?? []
        let fillCol = Color(hex: block.field_style?.fill_color ?? block.active_color ?? "#6366F1")
        let maxSelections = (block.field_config?["max_selections"]?.value as? Int)

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            // FlowLayout approximation using wrapping HStack
            FlowLayoutView(spacing: 8) {
                ForEach(options) { option in
                    let isSelected = selectedValues.contains(option.resolvedValue)
                    Button {
                        if isSelected {
                            selectedValues.remove(option.resolvedValue)
                        } else {
                            if let max = maxSelections, selectedValues.count >= max {
                                return // At max selections
                            }
                            selectedValues.insert(option.resolvedValue)
                        }
                        inputValues[fieldId] = Array(selectedValues)
                    } label: {
                        Text(option.label ?? "")
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? fillCol : Color.gray.opacity(0.1))
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(isSelected ? fillCol : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            let fieldId = block.field_id ?? block.id
            if let saved = inputValues[fieldId] as? [String] { selectedValues = Set(saved) }
        }
    }
}

/// Color picker -- grid of preset color swatches.
struct FormInputColorBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var selectedColor: String = ""

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let presetColors: [String] = {
            if let colors = block.field_config?["preset_colors"]?.value as? [String] {
                return colors
            }
            return ["#EF4444", "#F97316", "#EAB308", "#22C55E", "#3B82F6", "#6366F1", "#A855F7", "#EC4899", "#000000", "#6B7280"]
        }()

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(presetColors, id: \.self) { color in
                    Circle()
                        .fill(Color(hex: color))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(selectedColor == color ? Color.primary : Color.clear, lineWidth: 2)
                                .padding(2)
                        )
                        .onTapGesture {
                            selectedColor = color
                            inputValues[fieldId] = color
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            let fieldId = block.field_id ?? block.id
            if let saved = inputValues[fieldId] as? String { selectedColor = saved }
        }
    }
}

/// Placeholder for complex inputs (location, image_picker, signature) -- renders icon + label.
struct FormInputPlaceholderBlock: View {
    let block: ContentBlock
    let iconName: String
    let label: String

    var body: some View {
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundColor(.secondary)
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(16)
            .background(Color(hex: block.field_style?.background_color ?? "#F9FAFB"))
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - AC-046: Location Input with MKLocalSearchCompleter autocomplete

/// Observable wrapper around MKLocalSearchCompleter for location autocomplete.
class LocationSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func search(query: String) {
        guard !query.isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        completer.queryFragment = query
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.results = Array(completer.results.prefix(5))
            self.isSearching = false
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.results = []
            self.isSearching = false
        }
    }
}

/// Location input with autocomplete powered by MKLocalSearchCompleter.
/// User types to search, selects a result, and the formatted address + coordinates are stored.
struct FormInputLocationPlaceholderBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var text: String = ""
    @State private var showResults = false
    @State private var isFocused: Bool = false
    @StateObject private var searchCompleter = LocationSearchCompleter()

    /// True while we're restoring text from saved inputValues so the
    /// .onChange(of: text) handler doesn't clobber the full dict with a
    /// raw string.
    @State private var isRestoringFromSaved = false

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)
        let borderWidth = CGFloat(block.field_style?.border_width ?? 1)
        // Same default background as FormInputTextBlock — location must look
        // like any other iOS text field, not a differently-styled widget.
        let bgColor = Color(hex: block.field_style?.background_color ?? "#FFFFFF")
        // Always use UIKitTextField for location — SwiftUI's TextField
        // triggers ScrollView auto-scroll-to-focus which pushes the field up
        // when the keyboard appears. UIKit fields don't participate in that.
        let keyboardAppearanceRaw = block.field_config?["keyboard_appearance"]?.value as? String
        // Show prefix location icon? (default true — user can opt out per-block)
        let showIcon = (block.field_config?["show_prefix_icon"]?.value as? Bool) ?? true

        // Inline layout — dropdown is a real VStack child, which grows the
        // location block downward (siblings BELOW get pushed; siblings ABOVE
        // stay). The parent ScrollView has .ignoresSafeArea(.keyboard) to
        // prevent keyboard auto-scroll from repositioning above siblings.
        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            HStack(spacing: 8) {
                if showIcon {
                    Image(systemName: "location.fill")
                        .foregroundColor(.secondary)
                }
                UIKitTextField(
                    text: $text,
                    placeholder: block.field_placeholder ?? "Search location...",
                    keyboardAppearance: .from(keyboardAppearanceRaw),
                    autocorrection: false,
                    autocapitalization: .words,
                    returnKeyType: .search,
                    isFocused: Binding(
                        get: { isFocused },
                        set: { isFocused = $0 }
                    )
                )
                .frame(height: 24)
                .onChange(of: text) { newValue in
                    // Skip the onChange that fires when we programmatically set
                    // text from a saved dict — we must NOT overwrite the full
                    // dict with the raw string. Same when a suggestion is
                    // selected (we set text before storing the dict).
                    if isRestoringFromSaved { return }
                    searchCompleter.search(query: newValue)
                    showResults = isFocused && !newValue.isEmpty
                    // Only store the raw string if the user is ACTIVELY typing.
                    // Once a suggestion is selected, selectResult writes the
                    // structured dict and this onChange won't fire again until
                    // the user starts typing over it.
                    inputValues[fieldId] = newValue
                }
                if !text.isEmpty {
                    Button {
                        text = ""
                        showResults = false
                        inputValues[fieldId] = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
                if searchCompleter.isSearching {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(12)
            .frame(minHeight: fieldHeight(block))
            .background(bgColor)
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: borderWidth)
            )

            if showResults && !searchCompleter.results.isEmpty {
                // Dropdown styling from field_config
                let cfg = block.field_config
                let ddBgHex = cfg?["dropdown_bg_color"]?.value as? String
                let ddTextHex = cfg?["dropdown_text_color"]?.value as? String
                let ddSubtextHex = cfg?["dropdown_subtext_color"]?.value as? String
                let ddIconHex = cfg?["dropdown_icon_color"]?.value as? String
                let ddIconBgHex = cfg?["dropdown_icon_bg_color"]?.value as? String
                let ddIconBgGrad = cfg?["dropdown_icon_bg_gradient"]?.value as? [String: Any]
                let ddOpacity = cfgDouble(cfg?["dropdown_opacity"]) ?? 1.0
                let ddFontSize = cfgDouble(cfg?["dropdown_font_size"]) ?? 14
                let ddSubFontSize = cfgDouble(cfg?["dropdown_sub_font_size"]) ?? 12

                let ddBg: Color = ddBgHex.map { Color(hex: $0) } ?? Color(.systemBackground)
                let ddText: Color = ddTextHex.map { Color(hex: $0) } ?? .primary
                let ddSubtext: Color = ddSubtextHex.map { Color(hex: $0) } ?? .secondary
                let ddIcon: Color = ddIconHex.map { Color(hex: $0) } ?? .white

                VStack(alignment: .leading, spacing: 0) {
                    let visible = Array(searchCompleter.results.prefix(5).enumerated())
                    ForEach(visible, id: \.offset) { idx, result in
                        Button {
                            selectResult(result, fieldId: fieldId)
                        } label: {
                            HStack(spacing: 8) {
                                // Icon with optional gradient background
                                ZStack {
                                    if let grad = ddIconBgGrad,
                                       let colors = grad["colors"] as? [String], colors.count >= 2 {
                                        let angle = grad["angle"] as? Double ?? 180
                                        let gradColors = colors.map { Color(hex: $0) }
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(LinearGradient(
                                                colors: gradColors,
                                                startPoint: gradientStart(angle),
                                                endPoint: gradientEnd(angle)
                                            ))
                                    } else if let iconBg = ddIconBgHex {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(hex: iconBg))
                                    }
                                    Image(systemName: "mappin")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(ddIcon)
                                }
                                .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(.system(size: CGFloat(ddFontSize)))
                                        .foregroundColor(ddText)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.system(size: CGFloat(ddSubFontSize)))
                                            .foregroundColor(ddSubtext)
                                    }
                                }
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < visible.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(ddBg.opacity(ddOpacity))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: isFocused) { focused in
            // Hide dropdown immediately when focus is lost (tap outside)
            if !focused {
                showResults = false
            }
        }
        .onAppear {
            // Restore previously entered/selected value WITHOUT clobbering the
            // stored dict. Uses isRestoringFromSaved to bypass the onChange(of: text)
            // handler so the full structured dict (lat/lng/city/state/country/
            // timezone) survives back-navigation.
            let fieldId = block.field_id ?? block.id
            if let savedDict = inputValues[fieldId] as? [String: Any] {
                // Full structured dict — rebuild display text from city/state/country
                let display = Self.formatLocationDisplay(from: savedDict)
                    ?? (savedDict["address"] as? String)
                    ?? ""
                if !display.isEmpty && text != display {
                    isRestoringFromSaved = true
                    text = display
                    // Re-yield so onChange(of:text) fires with isRestoringFromSaved
                    // still true, then clear the flag.
                    DispatchQueue.main.async {
                        isRestoringFromSaved = false
                    }
                }
                Log.debug("[LocationBlock] restored saved dict: \(savedDict)")
            } else if let savedStr = inputValues[fieldId] as? String, !savedStr.isEmpty {
                if text != savedStr {
                    isRestoringFromSaved = true
                    text = savedStr
                    DispatchQueue.main.async {
                        isRestoringFromSaved = false
                    }
                }
            }
        }
    }

    /// Formats a saved location dict as "City / State, Country" (with state)
    /// or "City, Country" (no state). Returns nil if city is missing.
    static func formatLocationDisplay(from dict: [String: Any]) -> String? {
        let city = (dict["city"] as? String) ?? ""
        let state = (dict["state"] as? String) ?? ""
        let country = (dict["country"] as? String) ?? ""
        guard !city.isEmpty else { return nil }
        if !state.isEmpty && !country.isEmpty {
            return "\(city) / \(state), \(country)"
        } else if !country.isEmpty {
            return "\(city), \(country)"
        } else {
            return city
        }
    }

    private func selectResult(_ result: MKLocalSearchCompletion, fieldId: String) {
        showResults = false
        isFocused = false  // dismiss keyboard + hide dropdown reliably

        // Resolve full placemark via MKLocalSearch to get city/state/country
        let searchRequest = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: searchRequest)
        search.start { response, _ in
            guard let mapItem = response?.mapItems.first else {
                // Fallback: store minimal data
                let fallback = result.subtitle.isEmpty ? result.title : "\(result.title), \(result.subtitle)"
                isRestoringFromSaved = true
                text = fallback
                DispatchQueue.main.async { isRestoringFromSaved = false }
                inputValues[fieldId] = ["address": fallback]
                print("[AppDNA] Location (no placemark): \(fallback)")
                return
            }
            let placemark = mapItem.placemark
            let coordinate = placemark.coordinate
            let city = placemark.locality ?? placemark.subAdministrativeArea ?? ""
            let state = placemark.administrativeArea ?? ""
            let country = placemark.country ?? ""

            // IMPORTANT: MKLocalSearch's MKPlacemark.timeZone is USUALLY NIL
            // for text-search results. Falling back to TimeZone.current returns
            // the DEVICE's timezone (e.g. Europe/Warsaw) — not the LOCATION's
            // timezone. To get the accurate timezone for the selected location,
            // we reverse-geocode via CLGeocoder which reliably populates
            // CLPlacemark.timeZone.
            //
            // Strategy: if MKPlacemark has a timezone, use it immediately.
            // Otherwise, update the field text + lat/lng/city/state/country
            // synchronously (fast UX), then fetch the timezone async and
            // overwrite the dict once we have it. The user won't be able to
            // advance for a few hundred ms, which is fine.

            // Helper that stores the dict + updates display + prints debug
            let finalize: (String) -> Void = { resolvedTimezone in
                let locationDict: [String: Any] = [
                    "city": city,
                    "state": state,
                    "country": country,
                    "timezone": resolvedTimezone,
                    "latitude": coordinate.latitude,
                    "longitude": coordinate.longitude,
                ]
                inputValues[fieldId] = locationDict

                let display = Self.formatLocationDisplay(from: locationDict) ?? result.title
                isRestoringFromSaved = true
                text = display
                DispatchQueue.main.async { isRestoringFromSaved = false }

                // Debug print for Xcode console — user explicitly asked for this
                print("""
                [AppDNA] Location selected:
                  city:      \(city)
                  state:     \(state)
                  country:   \(country)
                  timezone:  \(resolvedTimezone)
                  latitude:  \(coordinate.latitude)
                  longitude: \(coordinate.longitude)
                  display:   \(display)
                """)
            }

            if let tz = placemark.timeZone?.identifier {
                // Rare happy path — placemark already has timezone
                finalize(tz)
            } else {
                // Reverse geocode to fetch the LOCATION's timezone (not device tz)
                let geocoder = CLGeocoder()
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                geocoder.reverseGeocodeLocation(location) { placemarks, error in
                    let tz = placemarks?.first?.timeZone?.identifier ?? "UTC"
                    if let error = error {
                        print("[AppDNA] Reverse geocode timezone lookup failed: \(error.localizedDescription), defaulting to UTC")
                    }
                    finalize(tz)
                }
            }
        }
    }
}

// MARK: - AC-048: Image Picker with PhotosPicker (iOS 16+)

/// Image picker using PhotosPicker. Stores selected image data as base64 in inputValues.
struct FormInputImagePickerPlaceholderBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var thumbnailImage: UIImage? = nil

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)
        let borderWidth = CGFloat(block.field_style?.border_width ?? 1)

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            PhotosPicker(selection: $selectedItem, matching: .images) {
                if let thumbnailImage = thumbnailImage {
                    // Show selected image thumbnail
                    Image(uiImage: thumbnailImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .clipped()
                        .cornerRadius(cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(borderColor, lineWidth: borderWidth)
                        )
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                                .padding(8)
                        }
                } else {
                    // Empty state -- dashed border tap target
                    HStack(spacing: 8) {
                        Image(systemName: "photo.fill")
                            .foregroundColor(.secondary)
                        Text("Tap to pick image")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(16)
                    .background(Color(hex: block.field_style?.background_color ?? "#F9FAFB"))
                    .cornerRadius(cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(borderColor, style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
                    )
                }
            }
            .buttonStyle(.plain)
            .onChange(of: selectedItem) { newItem in
                guard let newItem = newItem else { return }
                newItem.loadTransferable(type: Data.self) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let data):
                            if let data = data {
                                self.selectedImageData = data
                                self.thumbnailImage = UIImage(data: data)
                                // Store base64 string and metadata in inputValues
                                let base64 = data.base64EncodedString()
                                inputValues[fieldId] = [
                                    "data": base64,
                                    "size": data.count,
                                    "mime_type": "image/jpeg",
                                ]
                            }
                        case .failure:
                            break
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - AC-051: Signature Input (interactive Canvas with touch drawing)

/// Interactive signature pad with basic touch/drag drawing.
struct FormInputSignatureBlock: View {
    let block: ContentBlock
    @Binding var inputValues: [String: Any]

    @State private var lines: [[CGPoint]] = []
    @State private var currentLine: [CGPoint] = []

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    for line in lines + [currentLine] {
                        guard line.count > 1 else { continue }
                        var path = Path()
                        path.move(to: line[0])
                        for point in line.dropFirst() {
                            path.addLine(to: point)
                        }
                        context.stroke(path, with: .color(.primary), lineWidth: 2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(Color(hex: block.field_style?.background_color ?? "#F9FAFB"))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, style: StrokeStyle(lineWidth: 1, dash: [6, 3]))
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            currentLine.append(value.location)
                        }
                        .onEnded { _ in
                            lines.append(currentLine)
                            currentLine = []
                            inputValues[fieldId] = "signed"
                        }
                )

                // Clear button
                if !lines.isEmpty {
                    Button {
                        lines = []
                        currentLine = []
                        inputValues.removeValue(forKey: fieldId)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .padding(8)
                    }
                }
            }

            if lines.isEmpty {
                Text("Draw your signature above")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Flow Layout (SPEC-089d Phase 3 -- for chips block)

/// Simple flow layout approximation using LazyVGrid with adaptive columns.
/// Wraps children to next line when they exceed available width.
struct FlowLayoutView<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        // Use adaptive grid items as a flow-layout approximation
        let columns = [GridItem(.adaptive(minimum: 60, maximum: .infinity), spacing: spacing)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            content()
        }
    }
}
