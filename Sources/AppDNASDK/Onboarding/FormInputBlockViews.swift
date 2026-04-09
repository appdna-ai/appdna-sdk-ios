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

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textFieldStyle(.plain)
                .padding(12)
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

        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            HStack {
                if showPassword {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                } else {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                }

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
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
            .accentColor(accentColor)
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
        .background(Color(hex: block.field_style?.background_color ?? "#FFFFFF"))
        .cornerRadius(CGFloat(block.field_style?.corner_radius ?? 8))
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(block.field_style?.corner_radius ?? 8))
                .stroke(Color(hex: block.field_style?.border_color ?? "#D1D5DB"), lineWidth: 1)
        )
        .onChange(of: selectedValue) { newValue in
            inputValues[fieldId] = newValue
        }
    }

    // MARK: - Stacked (vertical cards with radio indicator)

    @ViewBuilder
    private func stackedSelectView(options: [InputOption], fieldId: String) -> some View {
        // Accent color — prefer fill_color, fall back to focused_border_color (console uses this), then active_color
        let accentHex = block.field_style?.fill_color
            ?? block.field_style?.focused_border_color
            ?? block.active_color
            ?? "#6366F1"
        let fillCol = Color(hex: accentHex)
        let cornerR = CGFloat(block.field_style?.corner_radius ?? 10)

        // Read option-specific colors from field_config (matches console preview logic)
        let cfgOptBg = (block.field_config?["bg_color"]?.value as? String).map { Color(hex: $0) }
        let cfgOptText = (block.field_config?["text_color"]?.value as? String).map { Color(hex: $0) }
        let cfgOptBorder = (block.field_config?["border_color"]?.value as? String).map { Color(hex: $0) }
        let cfgSelectedBg = (block.field_config?["selected_bg_color"]?.value as? String).map { Color(hex: $0) }
        let cfgSelectedText = (block.field_config?["selected_text_color"]?.value as? String).map { Color(hex: $0) }

        // Selected bg — field_config.selected_bg_color > accent at 15%
        let selectedBgCol = cfgSelectedBg ?? fillCol.opacity(0.15)
        // Unselected bg — field_config.bg_color > field_style.background_color > white
        let optionBg: Color = cfgOptBg
            ?? block.field_style?.background_color.map { Color(hex: $0) }
            ?? Color.white
        // Unselected text — field_config.text_color > field_style.text_color > block.text_color > primary
        let textCol: Color = cfgOptText
            ?? block.field_style?.text_color.map { Color(hex: $0) }
            ?? block.text_color.map { Color(hex: $0) }
            ?? block.style?.color.map { Color(hex: $0) }
            ?? .primary
        // Selected text — field_config.selected_text_color > textCol
        let selectedTextCol: Color = cfgSelectedText ?? textCol
        // Unselected border — field_config.border_color > field_style.border_color > accent at 30%
        let unselectedBorderCol: Color = cfgOptBorder
            ?? block.field_style?.border_color.map { Color(hex: $0) }
            ?? fillCol.opacity(0.3)

        VStack(spacing: 8) {
            ForEach(options) { option in
                let isSelected = isMultiSelect
                    ? selectedValues.contains(option.resolvedValue)
                    : selectedValue == option.resolvedValue
                Button {
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
                } label: {
                    HStack(spacing: 12) {
                        if let imgUrl = option.image_url, let url = URL(string: imgUrl) {
                            BundledAsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.gray.opacity(0.2)
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        if let icon = option.icon, !icon.isEmpty {
                            Text(icon)
                        }
                        Text(option.label ?? "")
                            .font(.subheadline)
                            .foregroundColor(isSelected ? selectedTextCol : textCol)
                        Spacer()
                        Image(systemName: isSelected
                            ? (isMultiSelect ? "checkmark.circle.fill" : "largecircle.fill.circle")
                            : "circle")
                            .foregroundColor(fillCol)
                            .font(.title3)
                    }
                    .padding(12)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: cornerR)
                                .fill(isSelected ? selectedBgCol : optionBg)
                            RoundedRectangle(cornerRadius: cornerR)
                                .strokeBorder(
                                    isSelected ? fillCol : unselectedBorderCol,
                                    lineWidth: isSelected ? 2 : 1
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Grid (2-column grid)

    @ViewBuilder
    private func gridSelectView(options: [InputOption], fieldId: String) -> some View {
        let accentHex = block.field_style?.fill_color
            ?? block.field_style?.focused_border_color
            ?? block.active_color
            ?? "#6366F1"
        let fillCol = Color(hex: accentHex)
        let cornerR = CGFloat(block.field_style?.corner_radius ?? 10)

        // Read option-specific colors from field_config (matches console preview logic)
        let cfgOptBg = (block.field_config?["bg_color"]?.value as? String).map { Color(hex: $0) }
        let cfgOptText = (block.field_config?["text_color"]?.value as? String).map { Color(hex: $0) }
        let cfgOptBorder = (block.field_config?["border_color"]?.value as? String).map { Color(hex: $0) }
        let cfgSelectedBg = (block.field_config?["selected_bg_color"]?.value as? String).map { Color(hex: $0) }
        let cfgSelectedText = (block.field_config?["selected_text_color"]?.value as? String).map { Color(hex: $0) }

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
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(options) { option in
                let isSelected = selectedValue == option.resolvedValue
                Button {
                    selectedValue = option.resolvedValue
                    inputValues[fieldId] = option.resolvedValue
                } label: {
                    VStack(spacing: 6) {
                        // Optional image
                        if let imgUrl = option.image_url, let url = URL(string: imgUrl) {
                            BundledAsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.gray.opacity(0.2)
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        // Optional icon emoji
                        if let icon = option.icon, !icon.isEmpty {
                            Text(icon).font(.title2)
                        }
                        Text(option.label ?? "")
                            .font(.subheadline)
                            .foregroundColor(isSelected ? selectedTextCol : textCol)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .padding(10)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: cornerR)
                                .fill(isSelected ? selectedBgCol : optionBg)
                            RoundedRectangle(cornerRadius: cornerR)
                                .strokeBorder(
                                    isSelected ? fillCol : unselectedBorderCol,
                                    lineWidth: isSelected ? 2 : 1
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
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
    @FocusState private var isFocused: Bool
    @StateObject private var searchCompleter = LocationSearchCompleter()

    var body: some View {
        let fieldId = block.field_id ?? block.id
        let borderColor = Color(hex: block.field_style?.border_color ?? "#D1D5DB")
        let cornerRadius = CGFloat(block.field_style?.corner_radius ?? 8)

        // Label + input VStack. The dropdown is attached as an .overlay DIRECTLY
        // on the input HStack (not the outer VStack) so GeometryReader inside the
        // overlay reads the input's frame immediately — no PreferenceKey timing
        // issues. The VStack's layout height stays fixed regardless of dropdown
        // state, preventing ScrollView reflow and keyboard-avoidance repositioning.
        VStack(alignment: .leading, spacing: 6) {
            formFieldLabel(block)

            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundColor(.secondary)
                TextField(block.field_placeholder ?? "Search location...", text: $text)
                    .focused($isFocused)
                    .font(.subheadline)
                    .onChange(of: text) { newValue in
                        searchCompleter.search(query: newValue)
                        showResults = isFocused && !newValue.isEmpty
                        inputValues[fieldId] = newValue
                    }
                if !text.isEmpty {
                    Button { text = ""; showResults = false; inputValues[fieldId] = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
                if searchCompleter.isSearching {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(12)
            .background(Color(hex: block.field_style?.background_color ?? "#F9FAFB"))
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
            // Dropdown overlay — uses .position() instead of .offset() so hit
            // testing works on the extended content. Fixed-height container
            // (300pt) wraps the dropdown items for consistent hit testing.
            .overlay(alignment: .topLeading) {
                if showResults && !searchCompleter.results.isEmpty {
                    GeometryReader { inputGeo in
                        // Fixed dropdown slot height — 60pt per item, 5 items = 300pt
                        let slotHeight: CGFloat = 300
                        VStack(alignment: .leading, spacing: 0) {
                            let visible = Array(searchCompleter.results.prefix(5).enumerated())
                            ForEach(visible, id: \.offset) { idx, result in
                                Button {
                                    selectResult(result, fieldId: fieldId)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "mappin")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.title)
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            if !result.subtitle.isEmpty {
                                                Text(result.subtitle)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
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
                            Spacer(minLength: 0)  // fill remaining slot height
                        }
                        .frame(width: inputGeo.size.width, height: slotHeight, alignment: .top)
                        .background(Color(.systemBackground))
                        .cornerRadius(cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(borderColor, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        // .position places the view's CENTER at the given point
                        // AND updates hit-testing to that location (unlike .offset)
                        .position(
                            x: inputGeo.size.width / 2,
                            y: inputGeo.size.height + 4 + slotHeight / 2
                        )
                    }
                    .zIndex(1000)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .zIndex(showResults ? 10 : 0)  // ensure dropdown renders above subsequent siblings
        .onChange(of: isFocused) { focused in
            // Hide dropdown immediately when focus is lost (tap outside, Return, etc.)
            if !focused {
                showResults = false
            }
        }
        .onAppear {
            if text.isEmpty {
                let fieldId = block.field_id ?? block.id
                if let saved = inputValues[fieldId] as? [String: Any], let addr = saved["address"] as? String {
                    text = addr
                } else if let saved = inputValues[fieldId] as? String, !saved.isEmpty {
                    text = saved
                }
            }
        }
    }

    private func selectResult(_ result: MKLocalSearchCompletion, fieldId: String) {
        let displayText = result.subtitle.isEmpty ? result.title : "\(result.title), \(result.subtitle)"
        text = displayText
        showResults = false

        // Resolve coordinates via MKLocalSearch
        let searchRequest = MKLocalSearch.Request(completion: result)
        let search = MKLocalSearch(request: searchRequest)
        search.start { response, _ in
            guard let mapItem = response?.mapItems.first else {
                // Store formatted address without coordinates
                inputValues[fieldId] = ["address": displayText]
                return
            }
            let coordinate = mapItem.placemark.coordinate
            inputValues[fieldId] = [
                "address": displayText,
                "latitude": coordinate.latitude,
                "longitude": coordinate.longitude,
            ]
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
                                .stroke(borderColor, lineWidth: 1)
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
