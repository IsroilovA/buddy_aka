import ApplicationServices
import Foundation
#if canImport(AppKit)
import AppKit
#endif

// Thin wrapper around NSAppleScript that compiles + executes an AppleScript
// source string and returns its string result. NSAppleScript is documented as
// main-thread-only, so the bridge is @MainActor.
@MainActor
public final class AppleScriptBridge {
    public enum BridgeError: Error, Sendable {
        // -1743 from macOS: the calling process lacks Automation TCC for the
        // target app. Surfaces explicitly so callers can prompt the user.
        case notAuthorized
        case compilationFailed(message: String)
        case executionFailed(code: Int, message: String)
        case emptyResult
    }

    public enum AutomationStatus: Equatable, Sendable {
        case authorized
        case denied
        case notRunning
        case unknown(OSStatus)
    }

    public init() {}

    /// Checks whether this app may send Apple events to `bundleID`, optionally
    /// prompting the user if no decision has been made yet. Uses the explicit
    /// `AEDeterminePermissionToAutomateTarget` API because the implicit
    /// prompt-on-first-send is unreliable for LSUIElement (menu-bar-only) apps
    /// - it can be silently suppressed, leaving no entry in System Settings ->
    /// Privacy & Security -> Automation until the user does *something* that
    /// forces the dialog.
    public func requestAutomation(bundleID: String, prompt: Bool) -> AutomationStatus {
        var addressDesc = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        let createStatus = bytes.withUnsafeBufferPointer { buf -> OSErr in
            AECreateDesc(
                DescType(typeApplicationBundleID),
                buf.baseAddress,
                buf.count,
                &addressDesc
            )
        }
        guard createStatus == noErr else { return .unknown(OSStatus(createStatus)) }
        defer { AEDisposeDesc(&addressDesc) }

        let status = AEDeterminePermissionToAutomateTarget(
            &addressDesc,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            prompt
        )
        switch Int(status) {
        case 0:        return .authorized
        case -1743:    return .denied
        case -600:     return .notRunning
        default:       return .unknown(status)
        }
    }

    /// Runs `js` in Safari's frontmost tab via `do JavaScript` and returns the
    /// JS expression's string value. Throws `.notAuthorized` if the user hasn't
    /// granted Automation control of Safari to the host app.
    public func evalSafariJS(_ js: String) throws -> String {
        let escaped = Self.escape(forAppleScriptString: js)
        let source = """
        tell application "Safari"
            do JavaScript "\(escaped)" in current tab of front window
        end tell
        """
        return try run(source: source)
    }

    private func run(source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw BridgeError.compilationFailed(message: "NSAppleScript init returned nil")
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo = errorInfo as? [String: Any] {
            let code = (errorInfo["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue ?? 0
            let message = (errorInfo["NSAppleScriptErrorMessage"] as? String) ?? "unknown AppleScript error"
            if code == -1743 {
                throw BridgeError.notAuthorized
            }
            throw BridgeError.executionFailed(code: code, message: message)
        }
        guard let value = descriptor.stringValue, !value.isEmpty else {
            throw BridgeError.emptyResult
        }
        return value
    }

    // AppleScript string literals: backslash escapes \" \\ \n \r \t. Anything
    // else passes through unchanged. We replace `\` first to avoid double-
    // escaping the backslashes we introduce for the other escapes.
    nonisolated static func escape(forAppleScriptString s: String) -> String {
        var out = String()
        out.reserveCapacity(s.count + 16)
        for ch in s {
            switch ch {
            case "\\": out.append("\\\\")
            case "\"": out.append("\\\"")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            default: out.append(ch)
            }
        }
        return out
    }
}
