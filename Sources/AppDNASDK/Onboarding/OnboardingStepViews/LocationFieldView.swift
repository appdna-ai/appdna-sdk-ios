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

    private var selectedLocation: LocationData? {
        value as? LocationData
    }

    private var minChars: Int {
        (field.config?.location_min_chars as? Int) ?? 2
    }

    private var placeholder: String {
        (field.config?.location_placeholder as? String) ?? "Search for a location..."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Search input
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .onChange(of: query) { _, newValue in
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

            // Selected location display
            if let location = selectedLocation {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text(location.formatted_address)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
            }

            // Suggestions dropdown
            if isExpanded && !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions, id: \.formatted_address) { suggestion in
                        Button(action: { selectSuggestion(suggestion) }) {
                            HStack {
                                Image(systemName: "mappin")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(suggestion.city.isEmpty ? suggestion.formatted_address : suggestion.city)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.primary)
                                    if !suggestion.city.isEmpty {
                                        Text(suggestion.formatted_address)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        if suggestion.formatted_address != suggestions.last?.formatted_address {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
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
            let locationType = field.config?.location_type as? String
            let biasCountry = field.config?.location_bias_country as? String
            let language = field.config?.location_language as? String

            let body: [String: Any] = [
                "query": query,
                "type": locationType as Any,
                "bias_country": biasCountry as Any,
                "language": language as Any,
                "limit": 5,
            ].compactMapValues { $0 is NSNull ? nil : $0 }

            let data = try await client.post(endpoint: .geocodeAutocomplete, body: body)
            if let response = data as? [String: Any],
               let dataObj = response["data"] as? [String: Any],
               let suggestionsArr = dataObj["suggestions"] as? [[String: Any]] {
                let decoded = suggestionsArr.compactMap { dict -> LocationData? in
                    guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                    return try? JSONDecoder().decode(LocationData.self, from: jsonData)
                }
                await MainActor.run {
                    suggestions = decoded
                    isExpanded = !decoded.isEmpty
                }
            }
        } catch {
            print("[AppDNA] Location autocomplete failed: \(error)")
        }
    }

    private func selectSuggestion(_ suggestion: LocationData) {
        query = suggestion.formatted_address
        value = suggestion
        suggestions = []
        isExpanded = false
    }

    private func clearSelection() {
        query = ""
        value = nil
        suggestions = []
        isExpanded = false
    }
}
