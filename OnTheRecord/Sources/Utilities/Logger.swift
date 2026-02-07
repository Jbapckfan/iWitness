import Foundation

/// Logs messages only in DEBUG builds to prevent sensitive data leakage in production
/// - Parameter message: The message to log
func debugLog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}

// MARK: - Nanosecond Helpers for Task.sleep

extension UInt64 {
    /// Converts seconds to nanoseconds for use with `Task.sleep(nanoseconds:)`
    static func seconds(_ value: Double) -> UInt64 { UInt64(value * 1_000_000_000) }
    /// Converts milliseconds to nanoseconds for use with `Task.sleep(nanoseconds:)`
    static func milliseconds(_ value: Double) -> UInt64 { UInt64(value * 1_000_000) }
}
