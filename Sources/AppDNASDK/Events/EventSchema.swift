import Foundation
import UIKit

/// Event envelope matching SPEC-003 schema.
struct SDKEvent: Codable {
    let schema_version: Int
    let event_id: String
    let event_name: String
    let ts_ms: Int64
    let user: EventUser
    let device: EventDevice
    let context: EventContext
    let properties: [String: AnyCodable]?
    let privacy: EventPrivacy
}

struct EventUser: Codable {
    let anon_id: String
    let user_id: String?
}

struct EventDevice: Codable {
    let platform: String
    let os: String
    let app_version: String
    let sdk_version: String
    let bundle_version: Int?
    let locale: String
    let country: String
}

struct EventContext: Codable {
    let session_id: String
    let screen: String?
    let experiment_exposures: [ExperimentExposure]?
}

struct ExperimentExposure: Codable {
    let exp: String
    let variant: String
}

struct EventPrivacy: Codable {
    let consent: Consent
}

struct Consent: Codable {
    let analytics: Bool
}

// MARK: - AnyCodable wrapper for properties dict

public struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - Event builder

enum EventEnvelopeBuilder {
    static func build(
        event: String,
        properties: [String: Any]?,
        identity: DeviceIdentity,
        sessionId: String,
        analyticsConsent: Bool,
        experimentExposures: [ExperimentExposure]? = nil
    ) -> SDKEvent {
        let bundleVer = AppDNA.currentBundleVersion > 0 ? AppDNA.currentBundleVersion : nil
        let device = EventDevice(
            platform: "ios",
            os: UIDevice.current.systemVersion,
            app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            sdk_version: AppDNA.sdkVersion,
            bundle_version: bundleVer,
            locale: Locale.current.identifier,
            country: (Locale.current as NSLocale).countryCode ?? ""
        )

        let props: [String: AnyCodable]? = properties?.mapValues { AnyCodable($0) }

        return SDKEvent(
            schema_version: 1,
            event_id: UUID().uuidString.lowercased(),
            event_name: event,
            ts_ms: Int64(Date().timeIntervalSince1970 * 1000),
            user: EventUser(anon_id: identity.anonId, user_id: identity.userId),
            device: device,
            context: EventContext(
                session_id: sessionId,
                screen: nil,
                experiment_exposures: experimentExposures
            ),
            properties: props,
            privacy: EventPrivacy(consent: Consent(analytics: analyticsConsent))
        )
    }
}
