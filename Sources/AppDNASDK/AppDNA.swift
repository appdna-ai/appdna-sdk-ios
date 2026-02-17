import Foundation
import UIKit

/// Main entry point for the AppDNA SDK.
/// All public methods are thread-safe.
public final class AppDNA: @unchecked Sendable {

    /// SDK version string.
    public static let sdkVersion = "0.2.0"

    /// Notification posted when remote config is refreshed.
    public static let configUpdated = Notification.Name("AppDNA.configUpdated")

    // MARK: - Singleton

    private static let shared = AppDNA()
    private let queue = DispatchQueue(label: "ai.appdna.sdk.main", qos: .utility)

    // MARK: - Internal managers

    private var apiKey: String?
    private var environment: Environment = .production
    private var options: AppDNAOptions = AppDNAOptions()

    private var apiClient: APIClient?
    private var identityManager: IdentityManager?
    private var sessionManager: SessionManager?
    private var eventTracker: EventTracker?
    private var eventQueue: EventQueue?
    private var remoteConfigManager: RemoteConfigManager?
    private var featureFlagManager: FeatureFlagManager?
    private var experimentManager: ExperimentManager?
    private var paywallManager: PaywallManager?
    private var billingBridge: BillingBridgeProtocol?
    private var onboardingFlowManager: OnboardingFlowManager?
    private var messageManager: MessageManager?
    private var pushTokenManager: PushTokenManager?

    private var bootstrapData: BootstrapData?
    private var isConfigured = false
    private var readyCallbacks: [() -> Void] = []

    private init() {}

    // MARK: - Public API: Initialization

    /// Configure the SDK. Call once at app launch.
    public static func configure(
        apiKey: String,
        environment: Environment = .production,
        options: AppDNAOptions = AppDNAOptions()
    ) {
        shared.queue.async {
            shared.performConfigure(apiKey: apiKey, environment: environment, options: options)
        }
    }

    // MARK: - Public API: Identity

    /// Link the anonymous device to a known user.
    public static func identify(userId: String, traits: [String: Any]? = nil) {
        shared.queue.async {
            shared.identityManager?.identify(userId: userId, traits: traits)
            Log.info("Identified user: \(userId)")
        }
    }

    /// Clear user identity (keeps anonymous ID).
    public static func reset() {
        shared.queue.async {
            shared.identityManager?.reset()
            shared.experimentManager?.resetExposures()
            shared.messageManager?.resetSession()
            Log.info("Identity reset")
        }
    }

    // MARK: - Public API: Events

    /// Track a custom event.
    public static func track(event: String, properties: [String: Any]? = nil) {
        shared.queue.async {
            shared.eventTracker?.track(event: event, properties: properties)
            // Evaluate in-app messages on every tracked event
            shared.messageManager?.onEvent(eventName: event, properties: properties)
        }
    }

    /// Force flush all queued events immediately.
    public static func flush() {
        shared.queue.async {
            shared.eventQueue?.flush()
        }
    }

    // MARK: - Public API: Remote Config

    /// Get a remote config value by key.
    public static func getRemoteConfig(key: String) -> Any? {
        shared.remoteConfigManager?.getConfig(key: key)
    }

    /// Check if a feature flag is enabled.
    public static func isFeatureEnabled(flag: String) -> Bool {
        shared.featureFlagManager?.isEnabled(flag: flag) ?? false
    }

    // MARK: - Public API: Experiments

    /// Get the variant assignment for an experiment.
    /// Exposure is auto-tracked on first call per session.
    public static func getExperimentVariant(experimentId: String) -> String? {
        shared.experimentManager?.getVariant(experimentId: experimentId)
    }

    /// Check if the user is in a specific variant.
    public static func isInVariant(experimentId: String, variantId: String) -> Bool {
        shared.experimentManager?.isInVariant(experimentId: experimentId, variantId: variantId) ?? false
    }

    /// Get a specific config value from the assigned variant's payload.
    public static func getExperimentConfig(experimentId: String, key: String) -> Any? {
        shared.experimentManager?.getExperimentConfig(experimentId: experimentId, key: key)
    }

    // MARK: - Public API: Paywalls

    /// Present a paywall modally from the given view controller.
    public static func presentPaywall(
        id: String,
        from viewController: UIViewController,
        context: PaywallContext? = nil,
        delegate: AppDNAPaywallDelegate? = nil
    ) {
        DispatchQueue.main.async {
            shared.paywallManager?.present(
                id: id,
                from: viewController,
                context: context,
                delegate: delegate
            )
        }
    }

    // MARK: - Public API: Onboarding (v0.2)

    /// Present an onboarding flow by ID. Returns false if config is unavailable.
    @discardableResult
    public static func presentOnboarding(
        flowId: String? = nil,
        from viewController: UIViewController? = nil,
        delegate: AppDNAOnboardingDelegate? = nil
    ) -> Bool {
        guard let vc = viewController ?? topViewController() else {
            Log.warning("No view controller available for onboarding presentation")
            return false
        }

        var result = false
        // Must present on main thread
        if Thread.isMainThread {
            result = shared.onboardingFlowManager?.present(flowId: flowId, from: vc, delegate: delegate) ?? false
        } else {
            DispatchQueue.main.sync {
                result = shared.onboardingFlowManager?.present(flowId: flowId, from: vc, delegate: delegate) ?? false
            }
        }
        return result
    }

    // MARK: - Public API: Push Token (v0.2)

    /// Set the APNS push token. Call from `didRegisterForRemoteNotificationsWithDeviceToken`.
    public static func setPushToken(_ token: Data) {
        shared.queue.async {
            shared.pushTokenManager?.setPushToken(token)
        }
    }

    /// Report push permission status.
    public static func setPushPermission(granted: Bool) {
        shared.queue.async {
            shared.pushTokenManager?.setPushPermission(granted: granted)
        }
    }

    // MARK: - Public API: Privacy

    /// Set analytics consent. When false, events are silently dropped.
    public static func setConsent(analytics: Bool) {
        shared.queue.async {
            shared.eventTracker?.setConsent(analytics: analytics)
            Log.info("Consent updated: analytics=\(analytics)")
        }
    }

    // MARK: - Public API: Ready callback

    /// Register a callback that fires when the SDK is fully initialized.
    public static func onReady(_ callback: @escaping () -> Void) {
        shared.queue.async {
            if shared.isConfigured {
                DispatchQueue.main.async { callback() }
            } else {
                shared.readyCallbacks.append(callback)
            }
        }
    }

    // MARK: - Internal bootstrap

    private func performConfigure(apiKey: String, environment: Environment, options: AppDNAOptions) {
        guard !isConfigured else {
            Log.warning("AppDNA.configure() called multiple times — ignoring")
            return
        }

        self.apiKey = apiKey
        self.environment = environment
        self.options = options
        Log.level = options.logLevel

        Log.info("Configuring AppDNA SDK v\(AppDNA.sdkVersion) (\(environment.rawValue))")

        // 1. Initialize core managers
        let keychainStore = KeychainStore()
        let identityMgr = IdentityManager(keychainStore: keychainStore)
        self.identityManager = identityMgr

        let client = APIClient(apiKey: apiKey, environment: environment)
        self.apiClient = client

        let configCache = ConfigCache(ttl: options.configTTL)
        let eventStore = EventStore()

        // 2. Initialize event system
        let tracker = EventTracker(identityManager: identityMgr)
        self.eventTracker = tracker

        let eq = EventQueue(
            apiClient: client,
            eventStore: eventStore,
            eventTracker: tracker,
            batchSize: options.batchSize,
            flushInterval: options.flushInterval
        )
        self.eventQueue = eq
        tracker.setEventQueue(eq)

        // 3. Initialize session manager (tracks lifecycle events)
        let sessionMgr = SessionManager(eventTracker: tracker)
        self.sessionManager = sessionMgr
        identityMgr.sessionManager = sessionMgr

        // 4. Initialize billing bridge
        switch options.billingProvider {
        case .storeKit2:
            self.billingBridge = StoreKit2Bridge()
        case .revenueCat:
            #if canImport(RevenueCat)
            self.billingBridge = RevenueCatBridge(eventTracker: tracker)
            #else
            Log.warning("RevenueCat not available, falling back to StoreKit 2")
            self.billingBridge = StoreKit2Bridge()
            #endif
        case .adapty(let adaptyKey):
            self.billingBridge = AdaptyBridge(apiKey: adaptyKey, eventTracker: tracker)
        case .none:
            self.billingBridge = nil
        }

        // 5. Initialize push token manager (v0.2)
        self.pushTokenManager = PushTokenManager(keychainStore: keychainStore, eventTracker: tracker)

        // 6. Bootstrap async (fetch orgId/appId, then Firestore configs)
        Task { [weak self] in
            await self?.performBootstrap(client: client, configCache: configCache, identityMgr: identityMgr, tracker: tracker)
        }
    }

    private func performBootstrap(
        client: APIClient,
        configCache: ConfigCache,
        identityMgr: IdentityManager,
        tracker: EventTracker
    ) async {
        do {
            let data: BootstrapData = try await client.request(.bootstrap)
            queue.async { [weak self] in
                self?.bootstrapData = data
            }
            Log.info("Bootstrap successful: orgId=\(data.orgId), appId=\(data.appId)")

            queue.async { [weak self] in
                guard let self else { return }
                self.initializeManagers(
                    firestorePath: data.firestorePath,
                    configCache: configCache,
                    identityMgr: identityMgr,
                    tracker: tracker
                )
            }
        } catch {
            Log.error("Bootstrap failed: \(error.localizedDescription) — using cached config")
            queue.async { [weak self] in
                guard let self else { return }
                self.initializeManagers(
                    firestorePath: nil,
                    configCache: configCache,
                    identityMgr: identityMgr,
                    tracker: tracker
                )
            }
        }
    }

    private func initializeManagers(
        firestorePath: String?,
        configCache: ConfigCache,
        identityMgr: IdentityManager,
        tracker: EventTracker
    ) {
        let remoteCfg = RemoteConfigManager(
            firestorePath: firestorePath,
            configCache: configCache,
            configTTL: self.options.configTTL
        )
        remoteCfg.setEventTracker(tracker)
        self.remoteConfigManager = remoteCfg

        self.featureFlagManager = FeatureFlagManager(remoteConfigManager: remoteCfg)

        self.experimentManager = ExperimentManager(
            remoteConfigManager: remoteCfg,
            identityManager: identityMgr,
            eventTracker: tracker
        )

        self.paywallManager = PaywallManager(
            remoteConfigManager: remoteCfg,
            billingBridge: self.billingBridge,
            eventTracker: tracker
        )

        // v0.2 managers
        self.onboardingFlowManager = OnboardingFlowManager(
            remoteConfigManager: remoteCfg,
            eventTracker: tracker
        )

        self.messageManager = MessageManager(
            remoteConfigManager: remoteCfg,
            eventTracker: tracker
        )

        // Fetch Firestore configs (includes onboarding + messages)
        remoteCfg.fetchConfigs()

        // Mark ready
        self.isConfigured = true
        tracker.track(event: "sdk_initialized", properties: nil)
        Log.info("SDK ready")

        let callbacks = self.readyCallbacks
        self.readyCallbacks = []
        for cb in callbacks {
            DispatchQueue.main.async { cb() }
        }
    }

    // MARK: - Helpers

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var vc = root
        while let presented = vc.presentedViewController {
            vc = presented
        }
        return vc
    }
}

// MARK: - Bootstrap response

struct BootstrapData: Codable {
    let orgId: String
    let appId: String
    let firestorePath: String
    let settings: BootstrapSettings
}

struct BootstrapSettings: Codable {
    let flushInterval: Int
    let batchSize: Int
    let configTTL: Int
}
