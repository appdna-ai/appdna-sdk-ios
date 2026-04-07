import Foundation
import UIKit
import SwiftUI
import UserNotifications
import os
import FirebaseCore
import FirebaseFirestore

/// Main entry point for the AppDNA SDK.
/// All public methods are thread-safe.
public final class AppDNA: @unchecked Sendable {

    /// SDK version string.
    public static let sdkVersion = "1.0.32"

    /// Firestore instance used by the SDK.
    /// Uses a secondary Firebase app ("appdna") if GoogleService-Info-AppDNA.plist is found,
    /// otherwise falls back to the default Firebase app's Firestore instance.
    /// NOTE: Must NOT have a default value — Swift evaluates the default on first access
    /// (even writes), and Firestore.firestore() crashes if no default Firebase app exists.
    internal static var firestoreDB: Firestore?

    /// Notification posted when remote config is refreshed.
    public static let configUpdated = Notification.Name("AppDNA.configUpdated")

    /// Observer token for web entitlement changes (registered at most once).
    private static var webEntitlementObserverToken: NSObjectProtocol?
    /// Callbacks registered via `onWebEntitlementChanged`.
    private static var webEntitlementChangeHandlers: [(WebEntitlement?) -> Void] = []

    // MARK: - Delegates

    /// Delegate for push notification events (taps, receives).
    public static weak var pushDelegate: AppDNAPushDelegate?

    /// Delegate for billing/purchase events.
    public static weak var billingDelegate: AppDNABillingDelegate?

    /// Delegate for server-driven screen events (SPEC-089c).
    public static weak var screenDelegate: AppDNAScreenDelegate?

    /// Internal accessor for the push token manager (legacy).
    static var push: PushTokenManager? { shared.pushTokenManager }
    static var geocodeClient: APIClient? { shared.apiClient }

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

    // MARK: - Custom View Registry (SPEC-089d AC-026)

    /// Registry of developer-provided custom views keyed by `view_key`.
    /// Used by the `custom_view` content block to render developer escape-hatch views.
    public static var registeredCustomViews: [String: () -> AnyView] = [:]

    /// Register a custom SwiftUI view factory for use in onboarding content blocks.
    /// - Parameters:
    ///   - key: The `view_key` value from the block config.
    ///   - factory: A closure returning an `AnyView`.
    public static func registerCustomView(_ key: String, factory: @escaping () -> AnyView) {
        registeredCustomViews[key] = factory
    }

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

    internal var apiClient: APIClient?
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
    private var screenManager: ScreenManager?

    private var bootstrapData: BootstrapData?
    private var isConfigured = false
    private var readyCallbacks: [() -> Void] = []

    private init() {}

    // MARK: - Public API: Initialization

    /// Configure the SDK. Call once at app launch. Subsequent calls are ignored.
    /// Firebase is initialized on the main thread first, then the rest runs on a background queue.
    public static func configure(
        apiKey: String,
        environment: Environment = .production,
        options: AppDNAOptions = AppDNAOptions()
    ) {
        // Guard against multiple calls — atomic check before async dispatch
        shared.initLock.lock()
        guard !shared.isConfigured else {
            shared.initLock.unlock()
            Log.warning("AppDNA.configure() called multiple times — ignoring")
            return
        }
        shared.isConfigured = true
        shared.initLock.unlock()

        // Firebase MUST be initialized on the main thread to avoid main-thread checker warnings.
        DispatchQueue.main.async {
            shared.initializeFirebase()
            // Then do the rest on background queue
            shared.queue.async {
                shared.performConfigure(apiKey: apiKey, environment: environment, options: options)
            }
        }
    }

    // MARK: - Public API: Identity

    /// Link the anonymous device to a known user.
    public static func identify(userId: String, traits: [String: Any]? = nil) {
        shared.queue.async {
            let previousAnonId = shared.identityManager?.currentIdentity.anonId
            let previousUserId = shared.identityManager?.currentIdentity.userId
            shared.identityManager?.identify(userId: userId, traits: traits)
            Log.info("Identified user: \(userId)")

            // Fire identify event for backend alias/merge
            var identifyProps: [String: Any] = [
                "user_id": userId,
                "anon_id": previousAnonId ?? "",
            ]
            if let prev = previousUserId, prev != userId {
                identifyProps["previous_user_id"] = prev
            }
            if let traits = traits {
                identifyProps["traits"] = traits
            }
            shared.eventTracker?.track(event: "identify", properties: identifyProps)

            // Send identify to backend alias endpoint
            var aliasBody: [String: Any] = [
                "anon_id": previousAnonId ?? "",
                "user_id": userId,
            ]
            if let traits = traits { aliasBody["traits"] = traits }
            shared.apiClient?.post(path: "/api/v1/sdk/identify", body: aliasBody) { result in
                switch result {
                case .success: Log.debug("Identity alias synced: \(previousAnonId ?? "?") → \(userId)")
                case .failure(let err): Log.debug("Identity alias sync failed: \(err.localizedDescription)")
                }
            }

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

    /// SPEC-067: Force an immediate config refresh, bypassing the cache TTL.
    public static func forceRefreshConfig() {
        shared.remoteConfigManager?.forceRefresh()
    }

    /// Check if a feature flag is enabled.
    public static func isFeatureEnabled(flag: String) -> Bool {
        shared.featureFlagManager?.isEnabled(flag: flag) ?? false
    }

    // MARK: - Internal accessors for SDK modules (SPEC-083, SPEC-088)

    /// Current user ID (or anonymous ID).
    static var currentUserId: String? {
        shared.identityManager?.currentIdentity.userId ?? shared.identityManager?.currentIdentity.anonId
    }

    /// Current app ID from bootstrap.
    static var currentAppId: String? {
        shared.bootstrapData?.appId
    }

    /// Resolve a remote config flag value as a string (for webhook header interpolation).
    static func getRemoteConfigFlag(_ key: String) -> String? {
        shared.remoteConfigManager?.getConfig(key: key) as? String
    }

    /// Internal reference to identity manager for TemplateEngine (SPEC-088).
    static var identityManagerRef: IdentityManager? {
        shared.identityManager
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

    // MARK: - Public API: Server-Driven Screens (SPEC-089c)

    /// Show a server-driven screen by ID. The screen config is fetched from cache or Firestore.
    public static func showScreen(_ screenId: String, completion: ((ScreenResult) -> Void)? = nil) {
        ScreenManager.shared.showScreen(screenId, completion: completion)
    }

    /// Show a server-driven multi-screen flow by ID.
    public static func showFlow(_ flowId: String, completion: ((FlowResult) -> Void)? = nil) {
        ScreenManager.shared.showFlow(flowId, completion: completion)
    }

    /// Dismiss the currently presented server-driven screen or flow.
    public static func dismissScreen() {
        ScreenManager.shared.dismissScreen()
    }

    /// Enable navigation interception. SDK will inject server-driven screens between
    /// app navigations based on console-configured interception rules.
    public static func enableNavigationInterception(forScreens: [String]? = nil) {
        ScreenManager.shared.enableNavigationInterception(forScreens: forScreens)
        NavigationInterceptor.shared.enable()
    }

    /// Disable navigation interception.
    public static func disableNavigationInterception() {
        ScreenManager.shared.disableNavigationInterception()
        NavigationInterceptor.shared.disable()
    }

    /// Preview a screen from raw JSON (debug builds only).
    #if DEBUG
    public static func previewScreen(json: String, completion: ((ScreenResult) -> Void)? = nil) {
        ScreenManager.shared.previewScreen(json: json, completion: completion)
    }
    #endif

    /// Check if analytics consent is granted. Used by zero-code mechanisms.
    public static func isConsentGranted() -> Bool {
        shared.eventTracker?.isConsentGranted ?? true
    }

    /// Get current user traits for audience rule evaluation.
    public static func getUserTraits() -> [String: Any] {
        shared.identityManager?.currentIdentity.traits ?? [:]
    }

    /// Shorthand to show a paywall by ID (used by screen action routing).
    public static func showPaywall(_ id: String) {
        guard let vc = topViewController() else { return }
        presentPaywall(id: id, from: vc)
    }

    /// Shorthand to show a survey by ID (used by screen action routing).
    public static func showSurvey(_ id: String) {
        shared.surveyManager?.present(surveyId: id)
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
    /// Only one NotificationCenter observer is registered; all handlers are dispatched from it.
    public static func onWebEntitlementChanged(_ handler: @escaping (WebEntitlement?) -> Void) {
        webEntitlementChangeHandlers.append(handler)

        // Register the observer only once (first handler registration)
        guard webEntitlementObserverToken == nil else { return }
        webEntitlementObserverToken = NotificationCenter.default.addObserver(
            forName: .webEntitlementChanged,
            object: nil,
            queue: .main
        ) { notification in
            let entitlement = notification.object as? WebEntitlement
            for h in webEntitlementChangeHandlers {
                h(entitlement)
            }
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

    // MARK: - Public API: Diagnostics

    /// Print a comprehensive SDK health report to the console.
    /// Call after `configure()` has had time to complete (e.g. after 3-5 seconds or in viewDidAppear).
    /// Checks: API key format, bootstrap status, Firebase initialization, Firestore connectivity, event queue health.
    public static func diagnose() {
        shared.queue.async {
            var lines: [String] = []
            lines.append("╔══════════════════════════════════════════")
            lines.append("║  AppDNA SDK Diagnostic Report  v\(sdkVersion)")
            lines.append("╠══════════════════════════════════════════")

            // 1. API Key
            if let key = shared.apiKey {
                if key.hasPrefix("adn_live_") {
                    lines.append("║ ✅ API Key: production key (adn_live_...\(String(key.suffix(4))))")
                } else if key.hasPrefix("adn_test_") {
                    lines.append("║ ✅ API Key: sandbox key (adn_test_...\(String(key.suffix(4))))")
                } else {
                    lines.append("║ ❌ API Key: invalid format — must start with adn_live_ or adn_test_")
                }
            } else {
                lines.append("║ ❌ API Key: not set — configure() not called?")
            }

            // 2. Environment
            lines.append("║ ✅ Environment: \(shared.environment.rawValue)")

            // 3. Bootstrap
            if let data = shared.bootstrapData {
                lines.append("║ ✅ Bootstrap: orgId=\(data.orgId), appId=\(data.appId)")
                lines.append("║    Firestore path: \(data.firestorePath)")
            } else {
                lines.append("║ ❌ Bootstrap: failed or not completed — check API key and network")
            }

            // 4. Firebase
            if FirebaseApp.app(name: "appdna") != nil {
                lines.append("║ ✅ Firebase: secondary app 'appdna' configured")
            } else if FirebaseApp.app() != nil {
                lines.append("║ ⚠️ Firebase: using default app (NOT AppDNA secondary) — add GoogleService-Info-AppDNA.plist")
            } else {
                lines.append("║ ❌ Firebase: no Firebase app configured")
            }

            // 5. Identity
            if let identity = shared.identityManager {
                let id = identity.currentIdentity
                lines.append("║ ✅ Identity: anonId=\(String(id.anonId.prefix(8)))..., userId=\(id.userId ?? "none")")
            } else {
                lines.append("║ ❌ Identity: not initialized")
            }

            // 6. Event Queue
            if shared.eventQueue != nil {
                lines.append("║ ✅ Event Queue: initialized")
            } else {
                lines.append("║ ❌ Event Queue: not initialized")
            }

            // 7. Remote Config
            if shared.remoteConfigManager != nil {
                lines.append("║ ✅ Remote Config: initialized")
            } else {
                lines.append("║ ❌ Remote Config: not initialized")
            }

            // 8. Modules
            var modules: [String] = []
            if shared.paywallManager != nil { modules.append("paywalls") }
            if shared.onboardingFlowManager != nil { modules.append("onboarding") }
            if shared.messageManager != nil { modules.append("messages") }
            if shared.surveyManager != nil { modules.append("surveys") }
            if shared.billingBridge != nil { modules.append("billing") }
            if shared.pushTokenManager != nil { modules.append("push") }
            if shared.experimentManager != nil { modules.append("experiments") }
            lines.append("║ ✅ Modules: \(modules.isEmpty ? "none" : modules.joined(separator: ", "))")

            lines.append("╠══════════════════════════════════════════")
            let allGood = shared.apiKey != nil && shared.bootstrapData != nil && FirebaseApp.app(name: "appdna") != nil
            if allGood {
                lines.append("║ ✅ SDK is fully operational")
            } else {
                lines.append("║ ⚠️ SDK has issues — review items marked ❌ above")
            }
            lines.append("╚══════════════════════════════════════════")

            // Always print regardless of log level — diagnose() is an explicit developer call
            for line in lines {
                print("[AppDNA] \(line)")
            }
        }
    }

    // MARK: - Public API: Session Data (SPEC-088)

    /// Store a key-value pair in the cross-module session data store.
    /// Available to all modules via `{{session.key}}` template variables.
    public static func setSessionData(key: String, value: Any) {
        SessionDataStore.shared.setSessionData(key: key, value: value)
    }

    /// Retrieve a session data value by key.
    public static func getSessionData(key: String) -> Any? {
        SessionDataStore.shared.getSessionData(key: key)
    }

    /// Clear all app-defined session data.
    public static func clearSessionData() {
        SessionDataStore.shared.clearSessionData()
    }

    /// Get structured location data from an onboarding location field (SPEC-089).
    /// Returns nil if the field wasn't filled or wasn't a location type.
    public static func getLocationData(fieldId: String) -> LocationData? {
        let responses = SessionDataStore.shared.onboardingResponses
        for (_, stepData) in responses {
            if let locationDict = (stepData as? [String: Any])?[fieldId],
               let jsonData = try? JSONSerialization.data(withJSONObject: locationDict),
               let location = try? JSONDecoder().decode(LocationData.self, from: jsonData) {
                return location
            }
        }
        return nil
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

    // MARK: - Firebase Initialization (must run on main thread)

    /// Lock protecting `firebaseInitialized` and `isConfigured` flags against concurrent access.
    private let initLock = NSLock()

    /// Track whether Firebase has been initialized to avoid double-init.
    private var firebaseInitialized = false

    /// Initialize Firebase on the main thread.
    /// Priority:
    /// 1. GoogleService-Info-AppDNA.plist -> create named "appdna" instance
    /// 2. Default FirebaseApp already exists -> use it
    /// 3. Standard GoogleService-Info.plist (only if no existing Firebase app) -> auto-configure
    /// 4. None available -> log error, SDK works in degraded mode
    private func initializeFirebase() {
        initLock.lock()
        guard !firebaseInitialized else {
            initLock.unlock()
            return
        }
        firebaseInitialized = true
        initLock.unlock()

        // Option 1 (RECOMMENDED): Dedicated AppDNA plist → separate named Firebase app
        // This is the correct path when the host app has its own Firebase project.
        if let appdnaPlistPath = Bundle.main.path(forResource: "GoogleService-Info-AppDNA", ofType: "plist"),
           let appdnaOptions = FirebaseOptions(contentsOfFile: appdnaPlistPath) {
            if FirebaseApp.app(name: "appdna") == nil {
                FirebaseApp.configure(name: "appdna", options: appdnaOptions)
            }
            if let secondaryApp = FirebaseApp.app(name: "appdna") {
                AppDNA.firestoreDB = Firestore.firestore(app: secondaryApp)
                Log.info("✅ Firebase: Using secondary app 'appdna' (GoogleService-Info-AppDNA.plist)")
            } else {
                Log.error("❌ Firebase: GoogleService-Info-AppDNA.plist found but failed to create secondary app. Check the plist content is valid.")
            }
            return
        }

        // Option 2: No AppDNA plist, but standard plist exists and NO existing Firebase app
        // This only works if the standard plist points to the AppDNA Firebase project.
        if FirebaseApp.app() == nil {
            if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
                FirebaseApp.configure()
                AppDNA.firestoreDB = Firestore.firestore()
                Log.info("✅ Firebase: Auto-configured from GoogleService-Info.plist (make sure this is the AppDNA Firebase config)")
                return
            }
        }

        // Option 3: Host app already has Firebase, but no AppDNA plist
        // ⚠️ We CANNOT use the host's Firebase — it points to a different project
        // and Firestore reads will fail with "Missing or insufficient permissions".
        if FirebaseApp.app() != nil {
            Log.error("""
            ❌ Firebase: Your app already has Firebase configured (its own project), \
            but GoogleService-Info-AppDNA.plist was NOT found. \
            AppDNA needs its own Firebase config to access Firestore. \
            \n→ Download GoogleService-Info-AppDNA.plist from Console → Settings → SDK \
            \n→ Add it to your Xcode project (drag into navigator, check 'Copy items if needed', select your app target) \
            \n→ See: https://docs.appdna.ai/sdks/ios/installation#firebase-configuration \
            \nRemote config (paywalls, experiments, flags, onboarding) will NOT work without this file.
            """)
            return
        }

        // Option 4: No Firebase config at all
        Log.error("""
        ❌ Firebase: No Firebase configuration found. AppDNA requires Firebase Firestore for remote config. \
        \n→ Download GoogleService-Info-AppDNA.plist from Console → Settings → SDK \
        \n→ Add it to your Xcode project \
        \n→ See: https://docs.appdna.ai/sdks/ios/installation#firebase-configuration
        """)
    }

    // MARK: - Internal bootstrap

    private func performConfigure(apiKey: String, environment: Environment, options: AppDNAOptions) {
        self.apiKey = apiKey
        self.environment = environment
        self.options = options
        Log.level = options.logLevel

        Log.info("Configuring AppDNA SDK v\(AppDNA.sdkVersion) (\(environment.rawValue))")

        // Validate API key format
        if !apiKey.hasPrefix("adn_live_") && !apiKey.hasPrefix("adn_test_") {
            Log.error("❌ API key format invalid. Keys must start with 'adn_live_' (production) or 'adn_test_' (sandbox). Got: \(String(apiKey.prefix(10)))...")
        }
        if apiKey.count < 20 {
            Log.error("❌ API key too short (\(apiKey.count) chars). Check you're passing the full key from Console → Settings → SDK → API Keys.")
        }

        // Firebase already initialized on main thread in initializeFirebase()

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

        // SPEC-067: Initialize background uploader
        let bgUploader = BackgroundUploader(apiClient: client, eventStore: eventStore)
        bgUploader.registerBackgroundTask()
        BackgroundUploader.shared = bgUploader

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
            // Bootstrap with a 15-second timeout (allows 1 retry cycle: initial + 1s + retry = ~5-10s)
            let data: BootstrapData = try await withTimeout(seconds: 15) {
                try await client.request(.bootstrap)
            }
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
            let desc = error.localizedDescription
            if desc.contains("401") || desc.contains("UNAUTHORIZED") || desc.contains("Invalid API key") {
                Log.error("❌ Bootstrap failed: Invalid API key. Check your key in Console → Settings → SDK → API Keys. Make sure it starts with 'adn_live_' or 'adn_test_'.")
            } else if desc.contains("Network error") || desc.contains("not connected") || desc.contains("timed out") {
                Log.error("❌ Bootstrap failed: Network error (\(desc)). Check your device has internet access and can reach api.appdna.ai")
            } else {
                Log.error("❌ Bootstrap failed: \(desc) — SDK will operate in degraded mode with cached/bundled config")
            }
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

    /// Execute an async operation with a timeout. Throws CancellationError if the timeout is reached.
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            // Return whichever finishes first
            guard let result = try await group.next() else {
                throw CancellationError()
            }
            group.cancelAll()
            return result
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

        // Feed bundled config to RemoteConfigManager — only fills empty caches
        remoteConfigManager?.loadBundledConfig(json)
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

            // Remove web entitlement observer
            if let token = webEntitlementObserverToken {
                NotificationCenter.default.removeObserver(token)
                webEntitlementObserverToken = nil
            }
            webEntitlementChangeHandlers.removeAll()

            Log.info("AppDNA SDK shut down")
        }
    }

    internal static func topViewController() -> UIViewController? {
        // UIApplication.shared must be accessed on the main thread
        if Thread.isMainThread {
            return _findTopViewController()
        } else {
            var result: UIViewController?
            DispatchQueue.main.sync {
                result = _findTopViewController()
            }
            return result
        }
    }

    private static func _findTopViewController() -> UIViewController? {
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
