import SwiftUI
import AppDNASDK

struct ContentView: View {
    @State private var logOutput: [String] = []

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(logOutput.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 300)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .padding(.horizontal)

                VStack(spacing: 12) {
                    Button("Track Custom Event") {
                        AppDNA.track(event: "button_tapped", properties: [
                            "screen": "example",
                            "action": "custom_track",
                            "timestamp": ISO8601DateFormatter().string(from: Date()),
                        ])
                        log("Tracked: button_tapped")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Identify User") {
                        AppDNA.identify(userId: "example_user_123", traits: [
                            "plan": "premium",
                            "signup_date": "2026-01-01",
                        ])
                        log("Identified: example_user_123")
                    }
                    .buttonStyle(.bordered)

                    Button("Reset Identity") {
                        AppDNA.reset()
                        log("Identity reset")
                    }
                    .buttonStyle(.bordered)

                    Button("Get Experiment Variant") {
                        let variant = AppDNA.getExperimentVariant(experimentId: "paywall_v3")
                        log("Variant for paywall_v3: \(variant ?? "nil")")
                    }
                    .buttonStyle(.bordered)

                    Button("Check Feature Flag") {
                        let enabled = AppDNA.isFeatureEnabled(flag: "new_paywall_design")
                        log("Feature 'new_paywall_design': \(enabled)")
                    }
                    .buttonStyle(.bordered)

                    Button("Get Remote Config") {
                        let value = AppDNA.getRemoteConfig(key: "onboarding_variant")
                        log("Config 'onboarding_variant': \(String(describing: value))")
                    }
                    .buttonStyle(.bordered)

                    Button("Flush Events") {
                        AppDNA.flush()
                        log("Manual flush triggered")
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)

                    Button("Set Consent: OFF") {
                        AppDNA.setConsent(analytics: false)
                        log("Analytics consent: OFF")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button("Set Consent: ON") {
                        AppDNA.setConsent(analytics: true)
                        log("Analytics consent: ON")
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
                .padding(.horizontal)
            }
            .navigationTitle("AppDNA Example")
            .onAppear {
                log("App launched — SDK configuring...")
                AppDNA.onReady { [self] in
                    log("SDK ready!")
                }
            }
        }
    }

    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logOutput.append("[\(timestamp)] \(message)")
    }
}
