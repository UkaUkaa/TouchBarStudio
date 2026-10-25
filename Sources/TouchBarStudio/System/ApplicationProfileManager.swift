import AppKit
import Observation

/// Tracks the frontmost application via NSWorkspace notifications. Detection only:
/// whether the Touch Bar can follow it is the provider's business.
@MainActor
@Observable
final class ApplicationProfileManager {
    struct AppInfo: Equatable {
        var bundleIdentifier: String
        var name: String
    }

    /// Frontmost app other than TouchBar Studio itself.
    private(set) var lastExternalApp: AppInfo?
    private(set) var frontmostIsSelf = true

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var observer: NSObjectProtocol?

    func start() {
        update(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let info = app.map { (bundleID: $0.bundleIdentifier, name: $0.localizedName) }
            MainActor.assumeIsolated {
                self?.update(bundleID: info?.bundleID, name: info?.name)
            }
        }
    }

    private func update(_ app: NSRunningApplication?) {
        update(bundleID: app?.bundleIdentifier, name: app?.localizedName)
    }

    private func update(bundleID: String?, name: String?) {
        guard let bundleID else { return }
        if bundleID == Bundle.main.bundleIdentifier {
            frontmostIsSelf = true
        } else {
            frontmostIsSelf = false
            lastExternalApp = AppInfo(bundleIdentifier: bundleID, name: name ?? bundleID)
        }
        onChange?()
    }

    /// Regular (Dock) apps currently running, for the profile app picker.
    static func runningApps() -> [AppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in app.bundleIdentifier.map { AppInfo(bundleIdentifier: $0, name: app.localizedName ?? $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
