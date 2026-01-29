import Foundation

/// Logs messages only in DEBUG builds to prevent sensitive data leakage in production
/// - Parameter message: The message to log
func debugLog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}
