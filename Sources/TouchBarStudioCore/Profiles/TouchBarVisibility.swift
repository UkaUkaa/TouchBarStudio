import Foundation

/// Whether TouchBar Studio's layout should be on the Touch Bar right now. Pure logic,
/// separate from how the frontmost app is detected or how the bar is drawn.
public enum TouchBarVisibility {
    /// - Parameters:
    ///   - frontmostBundleIdentifier: the app in front (other than TouchBar Studio).
    ///   - frontmostIsSelf: TouchBar Studio itself is in front; the layout is always shown
    ///     there so it can be edited and tried out.
    ///   - providerShowsOverOtherApps: only the experimental provider covers other apps,
    ///     so per-app hiding only applies to it.
    public static func shouldShow(frontmostBundleIdentifier: String?, frontmostIsSelf: Bool,
                                  settings: AppSettings, providerShowsOverOtherApps: Bool) -> Bool {
        guard providerShowsOverOtherApps, !frontmostIsSelf, let app = frontmostBundleIdentifier else { return true }
        return !settings.hiddenInApps.contains(app)
    }

    /// Records that the user closed the layout in `bundleIdentifier`. Returns false if nothing changed.
    @discardableResult
    public static func hide(in bundleIdentifier: String, settings: inout AppSettings) -> Bool {
        guard !bundleIdentifier.isEmpty, !settings.hiddenInApps.contains(bundleIdentifier) else { return false }
        settings.hiddenInApps.append(bundleIdentifier)
        return true
    }

    @discardableResult
    public static func unhide(in bundleIdentifier: String, settings: inout AppSettings) -> Bool {
        let before = settings.hiddenInApps.count
        settings.hiddenInApps.removeAll { $0 == bundleIdentifier }
        return settings.hiddenInApps.count != before
    }
}
