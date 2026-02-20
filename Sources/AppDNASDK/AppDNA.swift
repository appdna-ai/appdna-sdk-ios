import Foundation
import UIKit
import UserNotifications

/// Main entry point for the AppDNA SDK.
/// All public methods are thread-safe.
public final class AppDNA: @unchecked Sendable {

    /// SDK version string.
    public static let sdkVersion = "1.0.0"

    /// Notification posted when remote config is refreshed.
    public static let configUpdated = Notification.Name("AppDNA.configUpdated")

    // MARK: - Delegates

    /// Delegate for push notification events (taps, receives).
    public static weak var pushDelegate: AppDNAPushDelegate?

    /// Delegate for billing/purchase events.
    public static weak var billingDelegate: AppDNABillingDelegate?

    /// Internal accessor for the push token manager (legacy).
    static var push: PushTokenManager? { shared.pushTokenManager }

    // MARK: - Module Namespaces (v1.0)

    /// Push notification module.
    public static let pushModule = PushModule(manager: nil)
    /// Billing module.
    public static let billing = BillingModule()
    /// Onboarding module.
    public static let onboarding = OnboardingModule(manager: nil)
    /// Paywall module.
    public static let paywall = PaywallModule(manager: nil)
    /// Remote config module.
    public static let remoteConfig = RemoteConfigModule(manager: nil)
    /// Feature flags module.
    public static let features = FeaturesModule(manager: nil)
    /// In-app messages module.
    public static let inAppMessages = InAppMessagesModule(manager: nil)
    /// Surveys module.
    public static let surveys = SurveysModule(manager: nil)
    /// Deep links module.
    public static let deepLinks = DeepLinksModule()
    /// Experiments module.
    public static let experiments = ExperimentsModule(manager: nil)

    // MARK: - Config Bundle (v1.0)

    /// Current config bundle version reported by events.
    internal static var currentBundleVersion: Int = 0

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
    private var surveyManager: SurveyManager?
    private var webEntitlementManager: WebEntitlementManager?
    private var deferredDeepLinkManager: DeferredDeepLinkManager?

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

            // Start web entitlement observer for this user (v0.3)
            if let bootstrapData = shared.bootstrapData {
                shared.webEntitlementManager?.startObserving(
                    orgId: bootstrapData.orgId,
                    appId: bootstrapData.appId,
                    userId: userId
                )
            }
        }
    }

    /// Clear user identity (keeps anonymous ID).
    public static func reset() {
        shared.queue.async {
            shared.identityManager?.reset()
            shared.experimentManager?.resetExposures()
            shared.messageManager?.resetSession()
            shared.surveyManager?.resetSession()
            shared.webEntitlementManager?.stopObserving()
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
            // Evaluate surveys on every tracked event (v0.3)
            shared.surveyManager?.onEvent(eventName: event, properties: properties)
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

    // MARK: - Public API: Push Token (v0.2) + Push Tracking (v0.4 / SPEC-030)

    /// Set the APNS push token. Call from `didRegisterForRemoteNotificationsWithDeviceToken`.
    /// This registers the token with the backend for direct push delivery.
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

    /// Track that a push notification was delivered (call from UNNotificationServiceExtension or foreground handler).
    public static func trackPushDelivered(pushId: String) {
        shared.queue.async {
            shared.pushTokenManager?.trackDelivered(pushId: pushId)
        }
    }

    /// Track that a push notification was tapped (call from notification response handler).
    public static func trackPushTapped(pushId: String, action: String? = nil) {
        shared.queue.async {
            shared.pushTokenManager?.trackTapped(pushId: pushId, action: action)
        }
    }

    // MARK: - Public API: Push Registration (v0.4 / SPEC-030)

    /// Request push notification permission and register for remote notifications.
    /// Returns `true` if the user granted permission, `false` otherwise.
    @discardableResult
    public static func registerForPush() async -> Bool {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            shared.pushTokenManager?.setPushPermission(granted: granted)
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return granted
        } catch {
            Log.error("Failed to request push permission: \(error)")
            return false
        }
    }

    // MARK: - Public API: Web Entitlements (v0.3)

    /// Web subscription entitlement (from Stripe web checkout).
    public static var webEntitlement: WebEntitlement? {
        shared.webEntitlementManager?.currentEntitlement
    }

    /// Register a callback for when the web entitlement changes.
    public static func onWebEntitlementChanged(_ handler: @escaping (WebEntitlement?) -> Void) {
        NotificationCenter.default.addObserver(
            forName: .webEntitlementChanged,
            object: nil,
            queue: .main
        ) { notification in
            handler(notification.object as? WebEntitlement)
        }
    }

    // MARK: - Public API: Deferred Deep Links (v0.3)

    /// Check for a deferred deep link on first launch.
    /// Call after `AppDNA.configure()` and `AppDNA.onReady`.
    public static func checkDeferredDeepLink(completion: @escaping (DeferredDeepLink?) -> Void) {
        shared.queue.async {
            guard let manager = shared.deferredDeepLinkManager else {
                completion(nil)
                return
            }
            manager.checkDeferredDeepLink(completion: completion)
        }
    }

    // MARK: - Public API: Log Level (v1.0 / SPEC-041)

    /// Dynamically change the SDK log level at runtime.
    /// Matches unified API: `AppDNA.setLogLevel(.debug)`
    public static func setLogLevel(_ level: LogLevel) {
        Log.level = level
        Log.info("Log level changed to \(level)")
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

        // 5. Initialize push token manager (v0.2 + v0.4 SPEC-030: backend registration)
        self.pushTokenManager = PushTokenManager(keychainStore: keychainStore, eventTracker: tracker, apiClient: client)
        AppDNA.pushModule.manager = self.pushTokenManager

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

        // v0.3 managers
        let surveyMgr = SurveyManager(
            remoteConfigManager: remoteCfg,
            eventTracker: tracker,
            apiClient: self.apiClient
        )
        self.surveyManager = surveyMgr
        remoteCfg.onSurveyConfigsUpdated { configs in
            surveyMgr.updateConfigs(configs)
        }

        self.webEntitlementManager = WebEntitlementManager(eventTracker: tracker)

        if let bootstrapData = self.bootstrapData {
            self.deferredDeepLinkManager = DeferredDeepLinkManager(
                orgId: bootstrapData.orgId,
                appId: bootstrapData.appId,
                eventTracker: tracker
            )
        }

        // Fetch Firestore configs (includes onboarding + messages + surveys)
        remoteCfg.fetchConfigs()

        // Start web entitlement observer if user is identified
        if let userId = self.identityManager?.currentIdentity.userId,
           let bootstrapData = self.bootstrapData {
            self.webEntitlementManager?.startObserving(
                orgId: bootstrapData.orgId,
                appId: bootstrapData.appId,
                userId: userId
            )
        }

        // Wire module namespaces (v1.0)
        AppDNA.billing.bridge = self.billingBridge
        AppDNA.onboarding.manager = self.onboardingFlowManager
        AppDNA.paywall.paywallManager = self.paywallManager
        AppDNA.remoteConfig.manager = remoteCfg
        AppDNA.features.manager = self.featureFlagManager
        AppDNA.inAppMessages.manager = self.messageManager
        AppDNA.surveys.manager = self.surveyManager
        AppDNA.experiments.manager = self.experimentManager

        // Load config bundle version (v1.0 offline-first)
        self.loadConfigBundle()

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

    // MARK: - Config Bundle (v1.0 offline-first)

    /// Load config from bundle embedded in app binary.
    /// Priority: remote (already fetched) > cached > bundled.
    private func loadConfigBundle() {
        // Try to load bundled config from app resources
        guard let bundleURL = Bundle.main.url(forResource: "appdna-config", withExtension: "json"),
              let data = try? Data(contentsOf: bundleURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Log.debug("No bundled config found at appdna-config.json — using remote/cached only")
            return
        }

        let bundleVersion = json["bundle_version"] as? Int ?? 0
        AppDNA.currentBundleVersion = bundleVersion
        Log.info("Loaded bundled config (version \(bundleVersion))")
    }

    // MARK: - Helpers

    // MARK: - Lifecycle

    /// Shut down the SDK and release resources.
    /// Flushes the event queue and resets internal state.
    /// After calling shutdown the SDK must be re-configured before use.
    public static func shutdown() {
        shared.queue.async {
            shared.eventQueue?.flush()
            shared.eventQueue = nil
            shared.eventTracker = nil
            shared.sessionManager = nil
            shared.apiClient = nil
            shared.isConfigured = false
            Log.info("AppDNA SDK shut down")
        }
    }

    internal static func topViewController() -> UIViewController? {
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
