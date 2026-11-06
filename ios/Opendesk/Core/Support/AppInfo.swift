import UIKit

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    /// What the app calls the device it runs on: "iPhone" (iPhone Duo included) or "iPad".
    @MainActor static var device: String { UIDevice.current.model }

    /// `OD-Client: ios/<version>` marks a native request (contracts/native.md):
    /// sessions answer with the refresh token in the body, never a cookie.
    static var clientHeader: String { "ios/\(version)" }

    /// The APNs environment this build's entitlement points at.
    static var pushEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    /// Debug-only switches read from the scheme's environment (see DEVELOPMENT.md).
    /// Release builds compile these out and always answer nil.
    static func debugValue(_ name: String) -> String? {
        #if DEBUG
        let value = ProcessInfo.processInfo.environment[name]
        return (value?.isEmpty ?? true) ? nil : value
        #else
        return nil
        #endif
    }
}
