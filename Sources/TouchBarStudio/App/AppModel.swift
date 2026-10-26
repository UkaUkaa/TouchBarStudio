import AppKit
import Observation
import ServiceManagement
import TouchBarStudioCore

enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard, editor, actions, profiles, presets, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: L("Dashboard")
        case .editor: L("Touch Bar Editor")
        case .actions: L("Actions")
        case .profiles: L("Application Profiles")
        case .presets: L("Presets")
        case .settings: L("Settings")
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.50percent"
        case .editor: "rectangle.and.pencil.and.ellipsis"
        case .actions: "bolt"
        case .profiles: "app.badge"
        case .presets: "square.stack"
        case .settings: "gearshape"
        }
    }
}

/// Central state: configuration, persistence and wiring between the UI-independent core
/// (actions, storage) and the AppKit integrations (Touch Bar, hotkeys, app detection).
@MainActor
@Observable
final class AppModel {
    var config: AppConfiguration {
        didSet { if config != oldValue { configurationChanged(from: oldValue) } }
    }
    var section: SidebarSection = .dashboard
    /// Profile currently on the physical Touch Bar.
    private(set) var displayedProfileID: UUID?
    private(set) var activity: [ActivityEntry] = []
    private(set) var hotKeyFailures: [UUID: String] = [:]
    private(set) var lastSaved: Date?
    var loadWarning: String?
    var saveError: String?
    /// Incremented when script approvals change so views re-evaluate.
    private(set) var trustRevision = 0
    private(set) var touchBarHidden = false

    @ObservationIgnored let store: ConfigurationStore
    @ObservationIgnored let trust: ScriptTrustStore
    @ObservationIgnored let executor: ActionExecutor
    @ObservationIgnored let touchBar: TouchBarManager
    let apps = ApplicationProfileManager()
    let permissions = PermissionManager()
    let battery = BatteryMonitor()
    let microphone = MicrophoneMonitor()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Opens the main window (provided by the SwiftUI scene).
    @ObservationIgnored var openMainWindow: (() -> Void)?
    @ObservationIgnored lazy var editor = LayoutEditorViewModel(model: self)

    init(store: ConfigurationStore = ConfigurationStore(directory: AppModel.configurationDirectory())) {
        self.store = store
        // Defaults created while loading (first launch, unreadable file) are named in the
        // system language; the saved preference is applied right after.
        L10n.language = .system
        let loaded = store.load()
        var config = loaded.configuration
        // Apply the interface language before any user-visible text is produced.
        Self.applyLanguage(config.settings.language)
        if config.settings.providerKind == .systemModalExperimental && !SystemModalTouchBarProvider.isAvailable {
            config.settings.providerKind = .application
            loadWarning = L("The experimental “over all apps” mode is not available on this macOS version. Switched back to the standard mode.")
        }
        self.config = config
        if let error = loaded.recoveredFromError {
            loadWarning = L("Your configuration could not be read (%@). A backup was saved to %@ and defaults were loaded.", error, loaded.backupURL?.lastPathComponent ?? L("the app folder"))
        }
        trust = ScriptTrustStore(fileURL: store.trustURL)
        executor = ActionExecutor(services: LiveSystemServices(), trust: trust, policy: ExecutionPolicy(settings: config.settings))
        touchBar = TouchBarManager(provider: Self.makeProvider(for: config.settings))
        if loaded.isFirstLaunch { scheduleSave() }
    }

    /// Called once the app has finished launching.
    func start() {
        touchBar.onTap = { [weak self] item in self?.perform(item, source: L("Touch Bar")) }
        HotKeyCenter.shared.onHotKey = { [weak self] id in
            guard let self, let item = self.findItem(id) else { return }
            self.perform(item, source: L("Hotkey"))
        }
        apps.onChange = { [weak self] in self?.refreshTouchBar() }
        battery.onChange = { [weak self] status in self?.touchBar.updateBattery(status) }
        touchBar.updateBattery(battery.status)
        battery.start()
        microphone.onChange = { [weak self] state in self?.touchBar.updateMicrophone(state) }
        touchBar.updateMicrophone(microphone.state)
        microphone.start()
        apps.start()
        refreshTouchBar()
        registerHotKeys()
    }

    private static func configurationDirectory() -> URL {
        #if DEBUG
        // Lets development runs (e.g. snapshot captures) use a scratch configuration.
        if let dir = ProcessInfo.processInfo.environment["TBS_CONFIG_DIR"] {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        #endif
        return ConfigurationStore.defaultDirectory()
    }

    // MARK: Touch Bar

    private static func makeProvider(for settings: AppSettings) -> TouchBarProvider {
        switch settings.providerKind {
        case .systemModalExperimental where SystemModalTouchBarProvider.isAvailable:
            SystemModalTouchBarProvider(keepControlStrip: settings.keepControlStrip)
        default:
            ApplicationTouchBarProvider()
        }
    }

    var providerShowsOverOtherApps: Bool { touchBar.provider.showsOverOtherApps }

    var activeProfile: Profile {
        ProfileResolver.activeProfile(
            frontmostBundleIdentifier: apps.lastExternalApp?.bundleIdentifier,
            config: config,
            canFollowFrontmostApp: providerShowsOverOtherApps
        )
    }

    func refreshTouchBar(force: Bool = false) {
        let profile = activeProfile
        displayedProfileID = profile.id
        touchBar.show(profile, force: force)
    }

    func showTouchBar() {
        touchBarHidden = false
        touchBar.reshow()
        refreshTouchBar(force: true)
    }

    func hideTouchBar() {
        touchBarHidden = true
        touchBar.hide()
    }

    // MARK: Actions

    func perform(_ item: TouchBarItemConfig, source: String) {
        // A widget without an action is just a display: tapping it does nothing.
        if item.kind != .button && item.action.kind == .none { return }
        Task {
            let context = ExecutionContext(associatedBundleIdentifier: item.associatedBundleIdentifier,
                                           source: "\(source) · \(item.title.isEmpty ? item.action.summary : item.title)")
            let result = await executor.run(item.action, context: context)
            // Core Audio notifies too, but refresh right away so the widget flips immediately.
            microphone.refresh()
            // The microphone widget's new colour is its own feedback; only flash on failure.
            if !(item.kind == .microphone && result.succeeded) {
                touchBar.flash(itemID: item.id, success: result.succeeded)
            }
            activity = executor.activity
        }
    }

    /// Runs an action from inside the app (the “Test” buttons).
    @discardableResult
    func test(_ action: ActionConfig, associatedBundleIdentifier: String?) async -> Result<String?, ActionError> {
        let result = await executor.run(action, context: ExecutionContext(associatedBundleIdentifier: associatedBundleIdentifier, source: L("Test")))
        microphone.refresh()
        activity = executor.activity
        return result
    }

    func preflight(_ action: ActionConfig, associatedBundleIdentifier: String?) -> [ActionError] {
        _ = trustRevision
        return executor.preflight(action, context: ExecutionContext(associatedBundleIdentifier: associatedBundleIdentifier, source: ""))
    }

    func isApproved(_ action: ActionConfig) -> Bool {
        _ = trustRevision
        return trust.isFullyApproved(action)
    }

    func approve(_ action: ActionConfig) {
        trust.approve(action)
        trustRevision += 1
    }

    func revokeAllApprovals() {
        trust.revokeAll()
        trustRevision += 1
    }

    func clearActivity() {
        activity = []
    }

    // MARK: Profiles

    func findItem(_ id: UUID) -> TouchBarItemConfig? {
        for profile in config.profiles { if let item = profile.items.first(where: { $0.id == id }) { return item } }
        return nil
    }

    func updateProfile(_ id: UUID, _ change: (inout Profile) -> Void) {
        guard let index = config.profiles.firstIndex(where: { $0.id == id }) else { return }
        change(&config.profiles[index])
    }

    @discardableResult
    func addProfile(_ profile: Profile) -> UUID {
        config.profiles.append(profile)
        return profile.id
    }

    func deleteProfile(_ id: UUID) {
        guard config.profiles.count > 1 else { return }
        config.profiles.removeAll { $0.id == id }
        config.normalize()
    }

    func duplicateProfile(_ id: UUID) -> UUID? {
        guard let p = config.profile(id: id) else { return nil }
        let copy = Profile(name: L("%@ Copy", p.name), bundleIdentifiers: [], items: p.items.map { $0.withNewID() })
        return addProfile(copy)
    }

    /// Bundle IDs may only belong to one profile; assigning moves them.
    func assign(bundleIdentifier: String, to profileID: UUID) {
        for i in config.profiles.indices {
            config.profiles[i].bundleIdentifiers.removeAll { $0 == bundleIdentifier }
        }
        updateProfile(profileID) { $0.bundleIdentifiers.append(bundleIdentifier) }
    }

    // MARK: Presets

    var allPresets: [Preset] { BuiltInPresets.all + config.customPresets }

    func isBuiltIn(_ preset: Preset) -> Bool { BuiltInPresets.all.contains { $0.id == preset.id } }

    func saveAsPreset(profileID: UUID, name: String, summary: String) {
        guard let profile = config.profile(id: profileID) else { return }
        config.customPresets.append(Preset(name: name, summary: summary, symbol: "star", items: profile.items.map { $0.withNewID() },
                                           suggestedBundleIdentifiers: profile.bundleIdentifiers))
    }

    // MARK: Persistence

    private func configurationChanged(from old: AppConfiguration) {
        if old.settings.language != config.settings.language {
            Self.applyLanguage(config.settings.language)
        }
        if old.settings.providerKind != config.settings.providerKind || old.settings.keepControlStrip != config.settings.keepControlStrip {
            touchBar.setProvider(Self.makeProvider(for: config.settings))
        }
        executor.policy = ExecutionPolicy(settings: config.settings)
        refreshTouchBar()
        if hotKeyEntries(old) != hotKeyEntries(config) || old.settings.enableGlobalHotKeys != config.settings.enableGlobalHotKeys {
            registerHotKeys()
        }
        scheduleSave()
    }

    private func hotKeyEntries(_ c: AppConfiguration) -> [UUID: KeyCombo] {
        var result: [UUID: KeyCombo] = [:]
        for p in c.profiles { for item in p.items where item.isTappable { if let hk = item.hotKey { result[item.id] = hk } } }
        return result
    }

    private func registerHotKeys() {
        guard config.settings.enableGlobalHotKeys else {
            HotKeyCenter.shared.unregisterAll()
            hotKeyFailures = [:]
            return
        }
        let entries = hotKeyEntries(config).map { (itemID: $0.key, combo: $0.value) }
        hotKeyFailures = HotKeyCenter.shared.register(entries)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        do {
            try store.save(config)
            lastSaved = Date()
            saveError = nil
        } catch {
            saveError = L("Could not save configuration: %@", error.localizedDescription)
        }
    }

    func resetToDefaults() {
        var fresh = AppConfiguration.makeDefault()
        fresh.settings = config.settings
        fresh.settings.manualProfileID = nil
        config = fresh
        editor.selectProfile(fresh.defaultProfileID)
    }

    // MARK: Language

    /// The resolved interface language; views use it as an identity so they rebuild on change.
    var language: AppLanguage { config.settings.language.resolved }

    /// Switches in-app texts immediately. Menus and panels provided by macOS (Edit, Window,
    /// open/save dialogs) follow `AppleLanguages`, which AppKit reads at launch.
    private static func applyLanguage(_ language: AppLanguage) {
        L10n.language = language
        if let code = language.appleLanguageCode {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    /// Whether system-provided menus still use another language until relaunch.
    private(set) var needsRelaunchForLanguage = false

    func setLanguage(_ language: AppLanguage) {
        guard language != config.settings.language else { return }
        config.settings.language = language
        needsRelaunchForLanguage = true
    }

    func relaunch() {
        saveNow()
        let url = Bundle.main.bundleURL
        // Start the new instance after this one has quit, so the single-window scene and
        // the Touch Bar are owned by exactly one process.
        let script = "sleep 1; /usr/bin/open -n \"$0\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, url.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                saveError = nil
            } catch {
                saveError = L("Launch at login could not be changed: %@", error.localizedDescription)
            }
        }
    }
}
