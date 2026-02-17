import Foundation

/// SDK environment targeting.
public enum Environment: String, Sendable {
    case production
    case sandbox
}

/// Log verbosity levels.
public enum LogLevel: Int, Comparable, Sendable {
    case none = 0
    case error = 1
    case warning = 2
    case info = 3
    case debug = 4

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Billing provider for paywall purchase flows.
public enum BillingProvider: Sendable {
    case revenueCat
    case storeKit2
    case adapty(apiKey: String)
    case none
}

/// Configuration options for the AppDNA SDK.
public struct AppDNAOptions: Sendable {
    /// Automatic flush interval in seconds. Default: 30.
    public let flushInterval: TimeInterval
    /// Number of events per flush batch. Default: 20.
    public let batchSize: Int
    /// Remote config cache TTL in seconds. Default: 300 (5 min).
    public let configTTL: TimeInterval
    /// Log verbosity. Default: .warning.
    public let logLevel: LogLevel
    /// Billing provider for paywall purchases. Default: .storeKit2.
    public let billingProvider: BillingProvider

    public init(
        flushInterval: TimeInterval = 30,
        batchSize: Int = 20,
        configTTL: TimeInterval = 300,
        logLevel: LogLevel = .warning,
        billingProvider: BillingProvider = .storeKit2
    ) {
        self.flushInterval = flushInterval
        self.batchSize = batchSize
        self.configTTL = configTTL
        self.logLevel = logLevel
        self.billingProvider = billingProvider
    }
}

// MARK: - Internal Logger

enum Log {
    static var level: LogLevel = .warning

    static func error(_ message: @autoclosure () -> String) {
        guard level >= .error else { return }
        print("[AppDNA][ERROR] \(message())")
    }

    static func warning(_ message: @autoclosure () -> String) {
        guard level >= .warning else { return }
        print("[AppDNA][WARN] \(message())")
    }

    static func info(_ message: @autoclosure () -> String) {
        guard level >= .info else { return }
        print("[AppDNA][INFO] \(message())")
    }

    static func debug(_ message: @autoclosure () -> String) {
        guard level >= .debug else { return }
        print("[AppDNA][DEBUG] \(message())")
    }
}
