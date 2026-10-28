import Foundation

/// Whether TouchBar Studio's layout should be on the Touch Bar right now. Pure logic,
/// separate from how the frontmost app is detected or how the bar is drawn.
public enum TouchBarVisibility {
    /// - Parameters:
    ///   - frontmostBundleIdentifier: the app in front (other than TouchBar Studio).
    ///   - frontmostIsSelf: TouchBar Studio itself is in front; the layout is always shown
    ///     there so it can be edited and tried out.
    ///   - closedInApp: app in which the user tapped ✕ during the current visit. The close
    ///     only lasts until another app comes to the front (see `closedApp(after:…)`).
    ///   - ownTouchBarApps: apps the user chose to always keep their own Touch Bar in.
    ///   - providerShowsOverOtherApps: only the experimental provider covers other apps.
    public static func shouldShow(frontmostBundleIdentifier: String?, frontmostIsSelf: Bool,
                                  closedInApp: String?, ownTouchBarApps: [String] = [],
                                  providerShowsOverOtherApps: Bool) -> Bool {
        guard providerShowsOverOtherApps, !frontmostIsSelf, let app = frontmostBundleIdentifier else { return true }
        return app != closedInApp && !ownTouchBarApps.contains(app)
    }

    /// The closed-in app after the frontmost app changed: kept while the same app stays in
    /// front, forgotten as soon as any other app (including TouchBar Studio) is activated.
    public static func closedApp(after activatedBundleIdentifier: String?, closedInApp: String?) -> String? {
        guard let closedInApp, activatedBundleIdentifier == closedInApp else { return nil }
        return closedInApp
    }
}
