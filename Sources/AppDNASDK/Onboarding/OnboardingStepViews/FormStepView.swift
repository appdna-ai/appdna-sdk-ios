import SwiftUI

/// Form step: renders native input controls for each FormField (SPEC-082).
struct FormStepView: View {
    let config: StepConfig
    let onNext: ([String: Any]?) -> Void

    @State private var values: [String: Any] = [:]
    @State private var errors: [String: String] = [:]

    private var fields: [FormField] { config.fields ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    if let imageUrl = config.image_url, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }

                    if let title = config.title {
                        Text(title)
                            .font(.title2.bold())
                    }

                    if let subtitle = config.subtitle {
                        Text(subtitle)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    // Fields
                    ForEach(visibleFields) { field in
                        VStack(alignment: .leading, spacing: 6) {
                            if field.type != .toggle {
                                fieldLabel(field)
                            }
                            fieldControl(field)
                            if let error = errors[field.id] {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            // CTA
            Button(action: handleSubmit) {
                Text(config.cta_text ?? "Continue")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(canSubmit ? Color.accentColor : Color.gray.opacity(0.4))
                    .cornerRadius(14)
            }
            .disabled(!canSubmit)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            initializeDefaults()
        }
    }

    // MARK: - Field visibility

    private var visibleFields: [FormField] {
        fields.filter { field in
            guard let dep = field.depends_on else { return true }
            let depValue = values[dep.field_id]
            switch dep.operator_type {
            case "not_empty":
                return depValue != nil && "\(depValue!)" != ""
            case "empty":
                return depValue == nil || "\(depValue!)" == ""
            case "equals":
                guard let expected = dep.value?.value else { return false }
                return "\(depValue ?? "")" == "\(expected)"
            case "not_equals":
                guard let expected = dep.value?.value else { return true }
                return "\(depValue ?? "")" != "\(expected)"
            case "contains":
                guard let expected = dep.value?.value else { return false }
                return "\(depValue ?? "")".contains("\(expected)")
            case "gt":
                guard let expected = dep.value?.value as? Double,
                      let actual = depValue as? Double else { return false }
                return actual > expected
            case "lt":
                guard let expected = dep.value?.value as? Double,
                      let actual = depValue as? Double else { return false }
                return actual < expected
            default:
                return true
            }
        }
    }

    private var canSubmit: Bool {
        for field in visibleFields where field.required {
            let value = values[field.id]
            if value == nil { return false }
            if let str = value as? String, str.isEmpty { return false }
        }
        return true
    }

    // MARK: - Default values

    private func initializeDefaults() {
        for field in fields {
            if let defaultVal = field.config?.default_value?.value {
                if values[field.id] == nil {
                    values[field.id] = defaultVal
                }
            }
        }
    }

    // MARK: - Label

    private func fieldLabel(_ field: FormField) -> some View {
        HStack(spacing: 2) {
            Text(field.label)
                .font(.subheadline.weight(.medium))
            if field.required {
                Text("*")
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Field control dispatcher

    @ViewBuilder
    private func fieldControl(_ field: FormField) -> some View {
        switch field.type {
        case .text, .email, .phone:
            textField(field)
        case .textarea:
            textArea(field)
        case .number:
            numberField(field)
        case .date:
            datePicker(field)
        case .time:
            timePicker(field)
        case .datetime:
            dateTimePicker(field)
        case .select:
            selectField(field)
        case .slider:
            sliderField(field)
        case .toggle:
            toggleField(field)
        case .stepper:
            stepperField(field)
        case .segmented:
            segmentedField(field)
        }
    }

    // MARK: - Text

    private func textField(_ field: FormField) -> some View {
        let binding = Binding<String>(
            get: { values[field.id] as? String ?? "" },
            set: { values[field.id] = $0; errors[field.id] = nil }
        )
        return TextField(field.placeholder ?? "", text: binding)
            .textFieldStyle(.roundedBorder)
            .keyboardType(keyboardType(for: field))
            .autocapitalization(autocap(for: field))
    }

    private func textArea(_ field: FormField) -> some View {
        let binding = Binding<String>(
            get: { values[field.id] as? String ?? "" },
            set: { values[field.id] = $0; errors[field.id] = nil }
        )
        return TextEditor(text: binding)
            .frame(minHeight: 80, maxHeight: 150)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }

    private func numberField(_ field: FormField) -> some View {
        let binding = Binding<String>(
            get: {
                if let num = values[field.id] as? Double {
                    let places = field.config?.decimal_places ?? 0
                    return places > 0 ? String(format: "%.\(places)f", num) : String(Int(num))
                }
                return values[field.id] as? String ?? ""
            },
            set: {
                values[field.id] = Double($0)
                errors[field.id] = nil
            }
        )
        return HStack {
            TextField(field.placeholder ?? "0", text: binding)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
            if let unit = field.config?.unit {
                Text(unit)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Date/Time

    private func datePicker(_ field: FormField) -> some View {
        let binding = Binding<Date>(
            get: { values[field.id] as? Date ?? Date() },
            set: { values[field.id] = $0; errors[field.id] = nil }
        )
        return DatePicker(
            "",
            selection: binding,
            displayedComponents: .date
        )
        .datePickerStyle(.compact)
        .labelsHidden()
    }

    private func timePicker(_ field: FormField) -> some View {
        let binding = Binding<Date>(
            get: { values[field.id] as? Date ?? Date() },
            set: { values[field.id] = $0; errors[field.id] = nil }
        )
        return DatePicker(
            "",
            selection: binding,
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.compact)
        .labelsHidden()
    }

    private func dateTimePicker(_ field: FormField) -> some View {
        let binding = Binding<Date>(
            get: { values[field.id] as? Date ?? Date() },
            set: { values[field.id] = $0; errors[field.id] = nil }
        )
        return DatePicker(
            "",
            selection: binding,
            displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.compact)
        .labelsHidden()
    }

    // MARK: - Select

    private func selectField(_ field: FormField) -> some View {
        let options = field.options ?? []
        let binding = Binding<String>(
            get: { values[field.id] as? String ?? "" },
            set: { values[field.id] = $0; errors[field.id] = nil }
        )
        return Picker(field.placeholder ?? "Select", selection: binding) {
            Text(field.placeholder ?? "Select...").tag("")
            ForEach(options) { opt in
                Text(opt.label).tag(opt.id)
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: - Slider

    private func sliderField(_ field: FormField) -> some View {
        let minVal = field.config?.min_value ?? 0
        let maxVal = field.config?.max_value ?? 100
        let step = field.config?.step ?? 1
        let unit = field.config?.unit ?? ""

        let binding = Binding<Double>(
            get: { values[field.id] as? Double ?? minVal },
            set: { values[field.id] = $0 }
        )

        return VStack(spacing: 4) {
            HStack {
                Text("\(Int(binding.wrappedValue))\(unit.isEmpty ? "" : " \(unit)")")
                    .font(.headline)
                Spacer()
            }
            Slider(value: binding, in: minVal...maxVal, step: step)
            HStack {
                Text("\(Int(minVal))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(maxVal))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Toggle

    private func toggleField(_ field: FormField) -> some View {
        let binding = Binding<Bool>(
            get: { values[field.id] as? Bool ?? false },
            set: { values[field.id] = $0 }
        )
        return Toggle(field.label, isOn: binding)
    }

    // MARK: - Stepper

    private func stepperField(_ field: FormField) -> some View {
        let minVal = Int(field.config?.min_value ?? 0)
        let maxVal = Int(field.config?.max_value ?? 100)
        let step = Int(field.config?.step ?? 1)

        let binding = Binding<Int>(
            get: { values[field.id] as? Int ?? minVal },
            set: { values[field.id] = $0 }
        )

        return Stepper(value: binding, in: minVal...maxVal, step: step) {
            HStack {
                Text("\(binding.wrappedValue)")
                    .font(.headline)
                if let unit = field.config?.unit {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Segmented

    private func segmentedField(_ field: FormField) -> some View {
        let options = field.options ?? []
        let binding = Binding<String>(
            get: { values[field.id] as? String ?? options.first?.id ?? "" },
            set: { values[field.id] = $0 }
        )
        return Picker("", selection: binding) {
            ForEach(options) { opt in
                Text(opt.label).tag(opt.id)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Validation & Submit

    private func handleSubmit() {
        errors.removeAll()

        for field in visibleFields {
            if field.required {
                let val = values[field.id]
                if val == nil || (val is String && (val as! String).isEmpty) {
                    errors[field.id] = "\(field.label) is required"
                }
            }

            if let pattern = field.validation?.pattern,
               let val = values[field.id] as? String,
               !val.isEmpty {
                let regex = try? NSRegularExpression(pattern: pattern)
                let range = NSRange(val.startIndex..., in: val)
                if regex?.firstMatch(in: val, range: range) == nil {
                    errors[field.id] = field.validation?.pattern_message ?? "Invalid format"
                }
            }
        }

        if errors.isEmpty {
            // Convert values for response: dates to ISO strings, etc.
            var response: [String: Any] = [:]
            for (key, val) in values {
                if let date = val as? Date {
                    let formatter = ISO8601DateFormatter()
                    response[key] = formatter.string(from: date)
                } else {
                    response[key] = val
                }
            }
            onNext(response)
        }
    }

    // MARK: - Helpers

    private func keyboardType(for field: FormField) -> UIKeyboardType {
        switch field.type {
        case .email: return .emailAddress
        case .phone: return .phonePad
        case .number: return .decimalPad
        default:
            switch field.config?.keyboard_type {
            case "email": return .emailAddress
            case "number": return .numberPad
            case "phone": return .phonePad
            case "url": return .URL
            default: return .default
            }
        }
    }

    private func autocap(for field: FormField) -> UITextAutocapitalizationType {
        switch field.config?.autocapitalize {
        case "none": return .none
        case "words": return .words
        case "sentences": return .sentences
        case "characters": return .allCharacters
        default:
            return field.type == .email ? .none : .sentences
        }
    }
}
