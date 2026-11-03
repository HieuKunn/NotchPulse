import Foundation

class AppleScriptHelper {
    @discardableResult
    class func execute(_ scriptText: String) async throws -> NSAppleEventDescriptor? {
        // Fast abort if screen is actually locked to prevent 120-second AESendMessage hangs
        guard !NotchPulseLockMonitor.isScreenActuallyLocked() else {
            throw NSError(domain: "AppleScriptError", code: -1743, userInfo: [NSLocalizedDescriptionKey: "Screen is locked; AppleEvents are blocked"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let script = NSAppleScript(source: scriptText)
                var error: NSDictionary?
                if let descriptor = script?.executeAndReturnError(&error) {
                    continuation.resume(returning: descriptor)
                } else if let error = error {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: error as? [String: Any]))
                } else {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
                }
            }
        }
    }
    
    class func executeVoid(_ scriptText: String) async throws {
        _ = try await execute(scriptText)
    }
}
