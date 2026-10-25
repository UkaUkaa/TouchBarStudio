import AppKit
import ApplicationServices
import Observation

/// Reports and requests optional permissions. Nothing here is requested at launch:
/// the UI explains why first and only then calls `requestAccessibility()`.
@MainActor
@Observable
final class PermissionManager {
    private(set) var accessibilityGranted = AXIsProcessTrusted()

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    /// Shows the system prompt (once per app build) and opens the relevant Settings pane.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityGranted { openAccessibilitySettings() }
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openAutomationSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }

    static let accessibilityReason = """
        Keyboard-shortcut and media-key actions work by posting key events, which macOS only \
        allows for apps you approve under Privacy & Security › Accessibility. Everything else \
        (opening apps, URLs and files, copying text, scripts) works without it.
        """

    static let automationReason = """
        AppleScript actions and some built-in app commands control other apps. macOS asks \
        once per target app; you can change this later under Privacy & Security › Automation.
        """
}
