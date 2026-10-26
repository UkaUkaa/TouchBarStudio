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
    /// Latest battery reading, applied to battery widgets as they are created or updated.
    private var battery: BatteryStatus?
    /// Latest microphone state for microphone widgets.
    private var microphone: MicrophoneState?
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
            guard let button else { return }
            switch item.kind {
            case .battery: self.applyBattery(to: button, config: item)
            case .microphone: self.applyMicrophone(to: button, config: item)
            default: button.bezelColor = item.color.nsColor
            }
        }
    }

    /// Updates microphone widgets in place.
    func updateMicrophone(_ state: MicrophoneState?) {
        microphone = state
        for (id, config) in items where config.kind == .microphone {
            if let button = buttons[id] { applyMicrophone(to: button, config: config) }
        }
    }

    /// Updates battery widgets in place (no bar rebuild, so nothing flickers).
    func updateBattery(_ status: BatteryStatus?) {
        battery = status
        for (id, config) in items where config.kind == .battery {
            if let button = buttons[id] { applyBattery(to: button, config: config) }
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
        case .battery:
            let button = NSButton(title: "", target: self, action: #selector(buttonTapped(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(config.id.uuidString)
            button.imagePosition = .imageLeading
            applyBattery(to: button, config: config)
            buttons[id] = button
            item.view = button
            item.customizationLabel = L("Battery")
        case .microphone:
            let button = NSButton(title: "", target: self, action: #selector(buttonTapped(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(config.id.uuidString)
            button.imagePosition = .imageLeading
            applyMicrophone(to: button, config: config)
            buttons[id] = button
            item.view = button
            item.customizationLabel = L("Microphone")
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

    private static let compactWidthID = "TouchBarStudio.compactWidth"

    /// Without a title, a widget is drawn as a centred icon in a button only slightly wider
    /// than the icon, instead of the standard 72 pt button with the icon on the left.
    private func fitWidget(_ button: NSButton, iconOnly: Bool) {
        button.imagePosition = iconOnly ? .imageOnly : .imageLeading
        button.constraints.filter { $0.identifier == Self.compactWidthID }.forEach { $0.isActive = false }
        guard iconOnly, let image = button.image else { return }
        let width = button.widthAnchor.constraint(equalToConstant: LayoutMetrics.compactWidgetWidth(iconWidth: image.size.width))
        width.identifier = Self.compactWidthID
        width.isActive = true
    }

    private func applyMicrophone(to button: NSButton, config: TouchBarItemConfig) {
        guard let microphone else {
            button.image = NSImage(systemSymbolName: "mic.slash", accessibilityDescription: nil)
            button.title = config.showsTitle ? L("No microphone") : ""
            button.setAccessibilityLabel(L("No microphone"))
            button.bezelColor = config.color.nsColor
            return
        }
        button.image = NSImage(systemSymbolName: microphone.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        button.title = config.showsTitle ? (microphone.isMuted ? L("Muted") : L("Mic on")) : ""
        fitWidget(button, iconOnly: !config.showsTitle)
        // Red when muted, so the state is obvious at a glance.
        button.bezelColor = microphone.isMuted ? .systemRed : config.color.nsColor
        let description = microphone.isMuted ? L("Microphone muted: %@", microphone.deviceName) : L("Microphone on: %@", microphone.deviceName)
        button.setAccessibilityLabel(description)
        button.toolTip = description
    }

    private func applyBattery(to button: NSButton, config: TouchBarItemConfig) {
        guard let battery else {
            button.image = NSImage(systemSymbolName: "powerplug", accessibilityDescription: nil)
            button.title = config.showsTitle ? L("No battery") : ""
            button.setAccessibilityLabel(L("No battery"))
            button.bezelColor = config.color.nsColor
            return
        }
        button.image = NSImage(systemSymbolName: battery.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        button.title = config.showsTitle ? battery.percentageText : ""
        fitWidget(button, iconOnly: !config.showsTitle)
        switch battery.level {
        case .critical: button.bezelColor = .systemRed
        case .low: button.bezelColor = .systemOrange
        case .normal: button.bezelColor = config.color.nsColor
        }
        button.setAccessibilityLabel(battery.accessibilityDescription)
        button.toolTip = battery.accessibilityDescription
    }

    @objc private func buttonTapped(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw), let config = items[id] else { return }
        onTap?(config)
    }
}
