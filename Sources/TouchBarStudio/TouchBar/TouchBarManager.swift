import AppKit
import TouchBarStudioCore

/// Turns a `Profile` into a real `NSTouchBar`, hands it to the active provider and
/// routes physical taps back to the app.
@MainActor
final class TouchBarManager: NSObject, NSTouchBarDelegate {
    private static let itemPrefix = "com.touchbarstudio.item."

    private(set) var provider: TouchBarProvider
    private(set) var displayedProfile: Profile?
    private var touchBar: NSTouchBar?
    private var buttons: [UUID: NSButton] = [:]
    private var items: [UUID: TouchBarItemConfig] = [:]
    private var isSuspended = false

    /// Called when a button on the physical Touch Bar is tapped.
    var onTap: ((TouchBarItemConfig) -> Void)?

    init(provider: TouchBarProvider) {
        self.provider = provider
    }

    func setProvider(_ newProvider: TouchBarProvider) {
        provider.dismiss()
        provider = newProvider
        if let profile = displayedProfile {
            displayedProfile = nil
            show(profile)
        }
    }

    /// Shows `profile`; rebuilds the bar only when its content changed.
    func show(_ profile: Profile, force: Bool = false) {
        guard force || profile != displayedProfile || touchBar == nil else { return }
        displayedProfile = profile
        items = Dictionary(profile.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        buttons.removeAll()

        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = profile.items.map { item in
            item.kind == .flexibleSpace ? .flexibleSpace : NSTouchBarItem.Identifier(Self.itemPrefix + item.id.uuidString)
        }
        touchBar = bar
        if !isSuspended { provider.present(bar) }
    }

    /// Re-presents the current bar (e.g. after the user closed the system-modal bar).
    func reshow() {
        isSuspended = false
        if let touchBar { provider.present(touchBar) }
    }

    func hide() {
        isSuspended = true
        provider.dismiss()
    }

    var isHidden: Bool { isSuspended }

    /// Briefly tints a button to report the outcome of its action.
    func flash(itemID: UUID, success: Bool) {
        guard let button = buttons[itemID], let item = items[itemID] else { return }
        button.bezelColor = success ? .systemGreen : .systemRed
        Task { @MainActor [weak button] in
            try? await Task.sleep(for: .milliseconds(success ? 250 : 900))
            button?.bezelColor = item.color.nsColor
        }
    }

    // MARK: NSTouchBarDelegate

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier.rawValue.hasPrefix(Self.itemPrefix),
              let id = UUID(uuidString: String(identifier.rawValue.dropFirst(Self.itemPrefix.count))),
              let config = items[id] else { return nil }

        let item = NSCustomTouchBarItem(identifier: identifier)
        switch config.kind {
        case .button:
            let button = makeButton(for: config)
            buttons[id] = button
            item.view = button
            item.customizationLabel = config.title.isEmpty ? config.action.summary : config.title
        case .smallSpace, .largeSpace:
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.widthAnchor.constraint(equalToConstant: config.kind == .smallSpace ? 8 : 32).isActive = true
            item.view = spacer
        case .flexibleSpace:
            return nil
        }
        return item
    }

    private func makeButton(for config: TouchBarItemConfig) -> NSButton {
        let title = config.showsTitle ? config.title : ""
        let image = IconProvider.image(for: config.icon)
        let button: NSButton
        if let image, !title.isEmpty {
            button = NSButton(title: title, image: image, target: self, action: #selector(buttonTapped(_:)))
            button.imagePosition = .imageLeading
        } else if let image {
            button = NSButton(image: image, target: self, action: #selector(buttonTapped(_:)))
        } else {
            button = NSButton(title: title.isEmpty ? "•" : title, target: self, action: #selector(buttonTapped(_:)))
        }
        button.identifier = NSUserInterfaceItemIdentifier(config.id.uuidString)
        button.bezelColor = config.color.nsColor
        button.setAccessibilityLabel(config.title.isEmpty ? config.action.summary : config.title)
        return button
    }

    @objc private func buttonTapped(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw), let config = items[id] else { return }
        onTap?(config)
    }
}
