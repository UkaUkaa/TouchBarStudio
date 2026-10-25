import Foundation

/// Decides which profile should be on the Touch Bar. Pure logic: knows nothing about
/// how the frontmost app is detected or how the bar is drawn.
public enum ProfileResolver {
    /// Profile explicitly associated with `bundleIdentifier`, if any.
    public static func profile(for bundleIdentifier: String?, in config: AppConfiguration) -> Profile? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        return config.profiles.first { $0.bundleIdentifiers.contains(bundleIdentifier) }
    }

    /// The profile to show given the current frontmost app.
    /// - Parameter canFollowFrontmostApp: whether the active Touch Bar provider stays visible
    ///   while other apps are frontmost. If not, app matching is pointless and the manual
    ///   selection (or default) is used.
    public static func activeProfile(frontmostBundleIdentifier: String?, config: AppConfiguration, canFollowFrontmostApp: Bool) -> Profile {
        if canFollowFrontmostApp, config.settings.autoSwitchProfiles {
            return profile(for: frontmostBundleIdentifier, in: config) ?? config.defaultProfile
        }
        if let manual = config.settings.manualProfileID, let p = config.profile(id: manual) {
            return p
        }
        return config.defaultProfile
    }
}
