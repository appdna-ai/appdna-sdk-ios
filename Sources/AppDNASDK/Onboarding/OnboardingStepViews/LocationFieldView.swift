import SwiftUI

/// Structured location data returned by the geocoding autocomplete endpoint.
/// @see SPEC-089
public struct LocationData: Codable, Equatable {
    public let formatted_address: String
    public let city: String
    public let state: String
    public let state_code: String
    public let country: String
    public let country_code: String
    public let latitude: Double
    public let longitude: Double
    public let timezone: String
    public let timezone_offset: Int
    public let postal_code: String?
    public let raw_query: String
}

/// Autocomplete location field for onboarding form steps.
/// Debounces user input, calls backend proxy for suggestions, displays dropdown.
/// @see SPEC-089
struct LocationFieldView: View {
    let field: FormField
    @Binding var value: Any?
    let apiClient: APIClient?

    @State private var query = ""
    @State private var suggestions: [LocationData] = []
    @State private var isLoading = false
    @State private var isExpanded = false
    @State private var debounceTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    private var selectedLocation: LocationData? {
        if let loc = value as? LocationData { return loc }
        guard let dict = value as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: dict),
              let loc = try? JSONDecoder().decode(LocationData.self, from: jsonData) else { return nil }
        return loc
    }

    private var minChars: Int {
        (field.config?.location_min_chars as? Int) ?? 2
    }

    private var placeholder: String {
        (field.config?.location_placeholder as? String) ?? "Search for a location..."
    }

    var body: some View {
        // Inline layout — dropdown is a real VStack child (clickable + no
        // hit-test issues). Parent ScrollView uses .ignoresSafeArea(.keyboard)
        // to prevent keyboard auto-scroll from repositioning siblings.
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isFocused)
                    .onChange(of: query) { newValue in
                        onQueryChanged(newValue)
                    }

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if selectedLocation != nil {
                    Button(action: clearSelection) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            if isExpanded && !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.prefix(5).enumerated()), id: \.offset) { idx, suggestion in
                        Button(action: { selectSuggestion(suggestion) }) {
                            HStack {
                                Image(systemName: "mappin")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    // Primary line: City (or fallback to country if city empty)
                                    Text(suggestion.city.isEmpty ? suggestion.country : suggestion.city)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.primary)
                                    // Secondary line: "State, Country" or just "Country"
                                    // (no street names per user request)
                                    let secondary: String = {
                                        if !suggestion.state.isEmpty && !suggestion.country.isEmpty {
                                            return "\(suggestion.state), \(suggestion.country)"
                                        } else if !suggestion.country.isEmpty {
                                            return suggestion.country
                                        }
                                        return ""
                                    }()
                                    if !secondary.isEmpty {
                                        Text(secondary)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
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
                        if idx < min(suggestions.count, 5) - 1 {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
        }
        .onChange(of: isFocused) { focused in
            if !focused {
                // Delay slightly so button taps on dropdown items register first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if !isFocused {
                        isExpanded = false
                    }
                }
            }
        }
        .onAppear {
            // Restore from saved dict on re-entry (back navigation). Rebuild the
            // display query text from city/state/country so the field doesn't
            // show an empty placeholder after back-navigating to this step.
            if query.isEmpty, let dict = value as? [String: Any] {
                let city = (dict["city"] as? String) ?? ""
                let state = (dict["state"] as? String) ?? ""
                let country = (dict["country"] as? String) ?? ""
                if !city.isEmpty {
                    query = Self.formatDisplay(city: city, state: state, country: country)
                }
                print("[AppDNA] LocationField restored: \(dict)")
            }
        }
    }

    private func onQueryChanged(_ newValue: String) {
        debounceTask?.cancel()

        if newValue.count < minChars {
            suggestions = []
            isExpanded = false
            return
        }

        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            if !Task.isCancelled {
                await fetchSuggestions(query: newValue)
            }
        }
    }

    private func fetchSuggestions(query: String) async {
        guard let client = apiClient else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var body: [String: Any] = ["query": query, "limit": 5]
            if let t = field.config?.location_type { body["type"] = t }
            if let c = field.config?.location_bias_country { body["bias_country"] = c }
            if let l = field.config?.location_language { body["language"] = l }

            let jsonData = try JSONSerialization.data(withJSONObject: body)

            let endpoint = Endpoint.geocodeAutocomplete
            guard let url = endpoint.url(environment: client.environment) else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = jsonData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(client.apiKey, forHTTPHeaderField: "x-api-key")

            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let dataObj = json?["data"] as? [String: Any]
            let suggestionsArr = dataObj?["suggestions"] as? [[String: Any]] ?? []

            let decoded = suggestionsArr.compactMap { dict -> LocationData? in
                guard let itemData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                return try? JSONDecoder().decode(LocationData.self, from: itemData)
            }
            await MainActor.run {
                suggestions = decoded
                isExpanded = !decoded.isEmpty
            }
        } catch {
            print("[AppDNA] Location autocomplete failed: \(error)")
        }
    }

    private func selectSuggestion(_ suggestion: LocationData) {
        // Build display: "City / State, Country" or "City, Country"
        let display = Self.formatDisplay(
            city: suggestion.city,
            state: suggestion.state,
            country: suggestion.country
        )
        query = display

        // Store structured dict: country, city, state, timezone, lat, lon
        value = [
            "city": suggestion.city,
            "state": suggestion.state,
            "country": suggestion.country,
            "timezone": suggestion.timezone,
            "latitude": suggestion.latitude,
            "longitude": suggestion.longitude,
        ] as [String: Any]

        suggestions = []
        isExpanded = false
        isFocused = false  // dismiss keyboard

        // Debug print for Xcode console
        print("""
        [AppDNA] Location selected:
          city:      \(suggestion.city)
          state:     \(suggestion.state)
          country:   \(suggestion.country)
          timezone:  \(suggestion.timezone)
          latitude:  \(suggestion.latitude)
          longitude: \(suggestion.longitude)
          display:   \(display)
        """)
    }

    private func clearSelection() {
        query = ""
        value = nil
        suggestions = []
        isExpanded = false
    }

    /// Formats "City / State, Country" or "City, Country" based on whether state is present.
    static func formatDisplay(city: String, state: String, country: String) -> String {
        if !state.isEmpty && !country.isEmpty {
            return "\(city) / \(state), \(country)"
        } else if !country.isEmpty {
            return "\(city), \(country)"
        } else {
            return city
        }
    }
}
