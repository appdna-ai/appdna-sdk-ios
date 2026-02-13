import SwiftUI
import AppDNASDK

@main
struct AppDNAExampleApp: App {
    init() {
        // Configure AppDNA SDK on launch
        AppDNA.configure(
            apiKey: "pk_sandbox_your_key_here",
            environment: .sandbox,
            options: AppDNAOptions(
                flushInterval: 10,    // Shorter for demo purposes
                batchSize: 5,         // Smaller for demo purposes
                configTTL: 60,
                logLevel: .debug,     // Verbose for development
                billingProvider: .storeKit2
            )
        )

        AppDNA.onReady {
            print("[Example] AppDNA SDK is ready!")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
