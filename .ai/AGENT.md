# AppDNA iOS SDK (v0.3.0)

Swift SDK for iOS. Native implementation using SwiftUI for UI rendering, Keychain for identity storage, and Firebase Firestore for remote config.

---

## Public API

### Initialization

- `AppDNA.configure(apiKey: String, environment: Environment = .production, options: AppDNAOptions = AppDNAOptions())` -- Configure the SDK. Call once at app launch (e.g., in `AppDelegate.didFinishLaunching`). Bootstraps via `/api/v1/sdk/bootstrap`, then fetches Firestore configs.
- `AppDNA.onReady(_ callback: @escaping () -> Void)` -- Register a callback that fires when the SDK is fully initialized (bootstrap + config fetch complete).

### Identity

- `AppDNA.identify(userId: String, traits: [String: Any]? = nil)` -- Link the anonymous device identity to a known user. Also starts web entitlement observer for this user.
- `AppDNA.reset()` -- Clear user identity (keeps anonymous ID). Resets experiment exposures, message/survey session state, and stops web entitlement observer.

### Events

- `AppDNA.track(event: String, properties: [String: Any]? = nil)` -- Track a custom event. Also triggers in-app message and survey evaluation.
- `AppDNA.flush()` -- Force flush all queued events immediately.

### Remote Config

- `AppDNA.getRemoteConfig(key: String) -> Any?` -- Get a remote config value by key (from flags document).
- `AppDNA.isFeatureEnabled(flag: String) -> Bool` -- Check if a feature flag is enabled.

### Experiments

- `AppDNA.getExperimentVariant(experimentId: String) -> String?` -- Get the variant assignment for an experiment. Exposure is auto-tracked on first call per session. Uses deterministic MurmurHash3 bucketing.
- `AppDNA.isInVariant(experimentId: String, variantId: String) -> Bool` -- Check if the user is in a specific variant.
- `AppDNA.getExperimentConfig(experimentId: String, key: String) -> Any?` -- Get a config value from the assigned variant's payload.

### Paywalls

- `AppDNA.presentPaywall(id: String, from viewController: UIViewController, context: PaywallContext? = nil, delegate: AppDNAPaywallDelegate? = nil)` -- Present a paywall modally. Fetches config from RemoteConfigManager, renders SwiftUI paywall, handles purchase via billing bridge.

### Onboarding (v0.2)

- `AppDNA.presentOnboarding(flowId: String? = nil, from viewController: UIViewController? = nil, delegate: AppDNAOnboardingDelegate? = nil) -> Bool` -- Present an onboarding flow. If flowId is nil, uses the active flow from remote config. Returns false if config is unavailable.

### Push Notifications (v0.2)

- `AppDNA.setPushToken(_ token: Data)` -- Set the APNS push token. Call from `didRegisterForRemoteNotificationsWithDeviceToken`. Hashed with SHA-256 before tracking.
- `AppDNA.setPushPermission(granted: Bool)` -- Report push permission status.

### Web Entitlements (v0.3)

- `AppDNA.webEntitlement: WebEntitlement?` -- Current web subscription entitlement (from Stripe web checkout). Read-only property.
- `AppDNA.onWebEntitlementChanged(_ handler: @escaping (WebEntitlement?) -> Void)` -- Register a callback for entitlement changes. Uses NotificationCenter internally.
- `AppDNA.checkDeferredDeepLink(completion: @escaping (DeferredDeepLink?) -> Void)` -- Check for a deferred deep link on first launch. Call after `configure()` and `onReady`.

### Privacy

- `AppDNA.setConsent(analytics: Bool)` -- Set analytics consent. When false, events are silently dropped.

### Configuration Options (`AppDNAOptions`)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `flushInterval` | `TimeInterval` | 30 | Auto flush interval in seconds |
| `batchSize` | `Int` | 20 | Events per flush batch |
| `configTTL` | `TimeInterval` | 300 | Remote config cache TTL in seconds |
| `logLevel` | `LogLevel` | `.warning` | Log verbosity (none/error/warning/info/debug) |
| `billingProvider` | `BillingProvider` | `.storeKit2` | Billing provider (storeKit2/revenueCat/adapty/none) |

---

## Firestore Paths (Read)

All paths are relative to the `firestorePath` returned by bootstrap (format: `orgs/{orgId}/apps/{appId}`).

| Path | What It Reads |
|------|---------------|
| `{firestorePath}/config/paywalls` | Paywall configurations (layout, plans, pricing) |
| `{firestorePath}/config/experiments` | Experiment definitions (variants, weights, salt, platforms) |
| `{firestorePath}/config/flags` | Feature flags (key-value pairs) |
| `{firestorePath}/config/flows` | Generic flow configs |
| `{firestorePath}/config/onboarding` | Onboarding flow definitions (steps, active_flow_id) |
| `{firestorePath}/config/messages` | In-app message configs (trigger rules, content, display type) |
| `{firestorePath}/config/surveys` | Survey definitions (questions, trigger rules, follow-up actions) |
| `orgs/{orgId}/apps/{appId}/users/{userId}/web_entitlements` | Web subscription entitlement document (real-time listener) |
| `orgs/{orgId}/apps/{appId}/config/deferred_deep_links/{visitorId}` | Deferred deep link context (one-time read, deleted after resolve) |

---

## API Endpoints (HTTP)

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/sdk/bootstrap` | GET | Fetch orgId, appId, firestorePath, settings |
| `/api/v1/ingest/events` | POST | Batch event ingestion |
| `/api/v1/ingest/identify` | POST | Identity linkage |
| `/api/v1/feedback/responses` | POST | Submit survey responses |

---

## Events Emitted

| Event Name | Properties | When |
|------------|------------|------|
| `sdk_initialized` | (none) | SDK is fully configured and ready |
| `config_fetched` | (none) | Remote config fetched from Firestore |
| `session_start` | (none) | New session started (cold launch or >30 min gap) |
| `session_end` | (none) | Session ended (before new session on foreground resume) |
| `app_open` | (none) | App entered foreground |
| `app_close` | (none) | App entered background |
| `experiment_exposure` | `experiment_id`, `variant`, `source` | First variant access per session per experiment |
| `paywall_view` | `paywall_id`, `placement` | Paywall presented |
| `paywall_close` | `paywall_id`, `dismiss_reason` | Paywall dismissed |
| `purchase_started` | `paywall_id`, `product_id` | Purchase flow initiated |
| `purchase_completed` | `paywall_id`, `product_id`, `price`, `currency`, `provider` | Purchase successful |
| `purchase_failed` | `paywall_id`, `product_id`, `error` | Purchase failed |
| `purchase_restored` | `paywall_id`, `restored_count` | Purchases restored |
| `onboarding_flow_started` | `flow_id`, `flow_version` | Onboarding flow presented |
| `onboarding_step_viewed` | `flow_id`, `step_id`, `step_index`, `step_type` | Onboarding step became visible |
| `onboarding_step_completed` | `flow_id`, `step_id`, `step_index`, `selection_data` | User completed an onboarding step |
| `onboarding_step_skipped` | `flow_id`, `step_id`, `step_index` | User skipped an onboarding step |
| `onboarding_flow_completed` | `flow_id`, `total_steps`, `total_duration_ms`, `responses` | Entire onboarding flow completed |
| `onboarding_flow_dismissed` | `flow_id`, `last_step_id`, `last_step_index` | Onboarding flow dismissed early |
| `in_app_message_shown` | `message_id`, `message_type`, `trigger_event` | In-app message presented |
| `in_app_message_clicked` | `message_id`, `cta_action` | In-app message CTA tapped |
| `in_app_message_dismissed` | `message_id` | In-app message dismissed |
| `survey_shown` | `survey_id`, `survey_type`, `trigger_event` | Survey presented |
| `survey_question_answered` | `survey_id`, `question_id`, `question_type`, `answer` | Individual survey question answered |
| `survey_completed` | `survey_id`, `survey_type`, `answers` | All survey questions completed |
| `survey_dismissed` | `survey_id`, `questions_answered` | Survey dismissed before completion |
| `feedback_form_submitted` | `feedback` | Free-text feedback submitted (negative follow-up) |
| `feedback_form_dismissed` | (none) | Feedback form canceled |
| `review_prompt_shown` | `prompt_type` ("direct" or "two_step") | Review prompt displayed |
| `review_prompt_accepted` | (none) | User accepted two-step review prompt |
| `review_prompt_declined` | (none) | User declined two-step review prompt |
| `push_token_registered` | `token_hash`, `platform` | Push token registered or changed |
| `push_permission_granted` | (none) | User granted push permission |
| `push_permission_denied` | (none) | User denied push permission |
| `web_entitlement_activated` | `plan_name`, `status` | Web entitlement became active |
| `web_entitlement_expired` | `plan_name`, `reason` | Web entitlement expired/canceled |
| `deferred_deep_link_resolved` | `path`, `params`, `visitor_id` | Deferred deep link found and resolved |

---

## File Structure

### Core

- `Sources/AppDNASDK/AppDNA.swift` -- Main singleton entry point; public API surface
- `Sources/AppDNASDK/Configuration.swift` -- Environment, LogLevel, BillingProvider, AppDNAOptions, internal Log

### Identity & Sessions

- `Sources/AppDNASDK/Core/Identity/IdentityManager.swift` -- Anonymous + identified user identity, Keychain persistence
- `Sources/AppDNASDK/Core/Identity/SessionManager.swift` -- Session tracking based on app lifecycle (30 min timeout)

### Networking

- `Sources/AppDNASDK/Core/Network/APIClient.swift` -- HTTP client for bootstrap, event ingestion, identify
- `Sources/AppDNASDK/Core/Network/Endpoints.swift` -- API endpoint definitions (bootstrap, ingestEvents, ingestIdentify)

### Storage

- `Sources/AppDNASDK/Core/Storage/KeychainStore.swift` -- Keychain wrapper for anon_id, user_id, push token
- `Sources/AppDNASDK/Core/Storage/ConfigCache.swift` -- Disk cache for remote config (paywalls, experiments, flags, flows, onboarding, messages, surveys)
- `Sources/AppDNASDK/Core/Storage/EventStore.swift` -- Disk persistence for queued events

### Events

- `Sources/AppDNASDK/Events/EventTracker.swift` -- Builds event envelopes, respects consent, queues events
- `Sources/AppDNASDK/Events/EventQueue.swift` -- In-memory + disk event queue, auto-flush on interval/threshold/background, retry with exponential backoff
- `Sources/AppDNASDK/Events/EventSchema.swift` -- SDKEvent envelope model (SPEC-003), AnyCodable wrapper

### Config

- `Sources/AppDNASDK/Config/RemoteConfigManager.swift` -- Fetches all 7 config documents from Firestore, parses and caches
- `Sources/AppDNASDK/Config/FeatureFlagManager.swift` -- Feature flag lookups from remote config
- `Sources/AppDNASDK/Config/ExperimentManager.swift` -- Experiment variant assignment via MurmurHash3, exposure tracking
- `Sources/AppDNASDK/Config/ExperimentBucketer.swift` -- Deterministic MurmurHash3 bucketing algorithm

### Paywalls

- `Sources/AppDNASDK/Paywalls/PaywallManager.swift` -- Paywall presentation, purchase flow, event tracking
- `Sources/AppDNASDK/Paywalls/PaywallRenderer.swift` -- SwiftUI paywall view
- `Sources/AppDNASDK/Paywalls/PaywallConfig.swift` -- Paywall config model (plans, pricing, layout)
- `Sources/AppDNASDK/Paywalls/Components/` -- HeaderSection, PlanCard, SocialProof, CTAButton, FeatureList

### Onboarding

- `Sources/AppDNASDK/Onboarding/OnboardingFlowManager.swift` -- Onboarding flow orchestration and event tracking
- `Sources/AppDNASDK/Onboarding/OnboardingRenderer.swift` -- SwiftUI onboarding flow host view
- `Sources/AppDNASDK/Onboarding/OnboardingConfig.swift` -- Onboarding flow/step config models
- `Sources/AppDNASDK/Onboarding/OnboardingStepViews/` -- WelcomeStepView, ValuePropStepView, QuestionStepView, CustomStepView

### In-App Messaging

- `Sources/AppDNASDK/InAppMessaging/MessageManager.swift` -- Message trigger evaluation, frequency tracking, presentation
- `Sources/AppDNASDK/InAppMessaging/MessageConfig.swift` -- Message config model (trigger rules, content, display type)
- `Sources/AppDNASDK/InAppMessaging/MessageFrequencyTracker.swift` -- Session/lifetime frequency tracking
- `Sources/AppDNASDK/InAppMessaging/MessageRenderer.swift` -- SwiftUI message renderer
- `Sources/AppDNASDK/InAppMessaging/MessageViews/` -- BannerView, ModalView, TooltipView, FullscreenView

### Feedback & Surveys

- `Sources/AppDNASDK/Feedback/SurveyManager.swift` -- Survey trigger evaluation, presentation, response submission, follow-up actions
- `Sources/AppDNASDK/Feedback/SurveyConfig.swift` -- Survey config model (questions, trigger rules, follow-up actions)
- `Sources/AppDNASDK/Feedback/SurveyRenderer.swift` -- SwiftUI survey renderer
- `Sources/AppDNASDK/Feedback/SurveyFrequencyTracker.swift` -- Session/lifetime frequency tracking for surveys
- `Sources/AppDNASDK/Feedback/ReviewPromptManager.swift` -- Two-step and direct SKStoreReviewController prompts, rate limiting (3/year, 90 days apart)
- `Sources/AppDNASDK/Feedback/SurveyViews/` -- NPSQuestionView, CSATQuestionView, RatingQuestionView, EmojiScaleView, YesNoView, SingleChoiceView, MultiChoiceView, FreeTextView

### Integrations

- `Sources/AppDNASDK/Integrations/StoreKit2Bridge.swift` -- StoreKit 2 purchase/restore integration
- `Sources/AppDNASDK/Integrations/RevenueCatBridge.swift` -- RevenueCat billing bridge
- `Sources/AppDNASDK/Integrations/AdaptyBridge.swift` -- Adapty billing bridge
- `Sources/AppDNASDK/Integrations/BillingBridge.swift` -- BillingBridgeProtocol definition
- `Sources/AppDNASDK/Integrations/PushTokenManager.swift` -- Push token capture, Keychain storage, SHA-256 hashing

### Web Entitlements & Deep Links

- `Sources/AppDNASDK/WebEntitlements/WebEntitlementManager.swift` -- Real-time Firestore listener for web entitlements
- `Sources/AppDNASDK/WebEntitlements/WebEntitlement.swift` -- WebEntitlement model, EntitlementStatus enum
- `Sources/AppDNASDK/DeepLinks/DeferredDeepLinkManager.swift` -- First-launch deferred deep link resolution (pasteboard, URL scheme, IDFV)

---

## Backend Module Dependencies

- **monetization**: reads paywall configs from `{firestorePath}/config/paywalls`; writes purchase events
- **onboarding**: reads onboarding flow configs from `{firestorePath}/config/onboarding`
- **experiments**: reads experiment configs from `{firestorePath}/config/experiments`
- **feature-flags**: reads flags from `{firestorePath}/config/flags`
- **in-app-messaging**: reads message configs from `{firestorePath}/config/messages`
- **feedback**: reads survey configs from `{firestorePath}/config/surveys`; posts responses to `/api/v1/feedback/responses`
- **web-entitlements**: observes user entitlements at `orgs/{orgId}/apps/{appId}/users/{userId}/web_entitlements`
- **deep-links**: reads deferred deep link context from `orgs/{orgId}/apps/{appId}/config/deferred_deep_links/{visitorId}`
- **ingest**: sends batched events to `/api/v1/ingest/events` and `/api/v1/ingest/identify`
- **sdk-bootstrap**: fetches org/app context from `/api/v1/sdk/bootstrap`

---

## Rule

Any new module feature that writes config to Firestore or adds new events MUST update this SDK. When adding a new Firestore config document, update `RemoteConfigManager.fetchConfigs()` to fetch it and add a corresponding parse method.
