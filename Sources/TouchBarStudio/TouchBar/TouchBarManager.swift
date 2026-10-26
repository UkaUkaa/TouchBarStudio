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
    private var sliders: [UUID: NSSliderTouchBarItem] = [:]
    /// When each slider was last moved by a finger: outside readings don't move it back meanwhile.
    private var lastSliderInput: [UUID: Date] = [:]
    /// Volume sliders currently showing the muted speaker icon.
    private var mutedVolumeSliders: Set<UUID> = []
    private var items: [UUID: TouchBarItemConfig] = [:]
    /// Latest battery reading, applied to battery widgets as they are created or updated.
    private var battery: BatteryStatus?
    /// Latest microphone state for microphone widgets.
    private var microphone: MicrophoneState?
    private var volume: VolumeState?
    private var brightness: Float?
    private var now = Date()
    /// Hidden by the user from the menu ("Hide Layout from Touch Bar").
    private var isSuspended = false
    /// Not wanted in the current app (the user closed it there with ✕).
    private var isSuppressed = false
    /// Whether our bar is actually on screen as far as we know.
    private var isPresented = false

    /// Icon size from Settings for items without their own. Set before `show(_:force:)`.
    var defaultIconSize = IconSize.standard
    /// Button width from Settings (nil: fit content). Set before `show(_:force:)`.
    var defaultWidth: Double?

    /// Called when a button on the physical Touch Bar is tapped.
    var onTap: ((TouchBarItemConfig) -> Void)?
    /// Called when the system hid our bar without us asking (the user tapped ✕).
    var onClosedBySystem: (() -> Void)?
    /// Called while the volume or brightness slider is dragged (0…1).
    var onSliderChange: ((ItemKind, Float) -> Void)?

    init(provider: TouchBarProvider) {
        self.provider = provider
        super.init()
        observeVisibility(of: provider)
    }

    func setProvider(_ newProvider: TouchBarProvider) {
        provider.onVisibilityChange = nil
        provider.dismiss()
        isPresented = false
        provider = newProvider
        observeVisibility(of: newProvider)
        if let profile = displayedProfile {
            displayedProfile = nil
            show(profile)
        }
    }

    private func observeVisibility(of provider: TouchBarProvider) {
        provider.onVisibilityChange = { [weak self] visible in
            guard let self, !visible, self.isPresented else { return }
            self.isPresented = false
            self.onClosedBySystem?()
        }
    }

    /// Shows `profile`; rebuilds the bar only when its content changed.
    func show(_ profile: Profile, force: Bool = false) {
        var rebuilt = false
        if force || profile != displayedProfile || touchBar == nil {
            displayedProfile = profile
            items = Dictionary(profile.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            buttons.removeAll()
            sliders.removeAll()
            lastSliderInput.removeAll()
            mutedVolumeSliders.removeAll()
            let bar = NSTouchBar()
            bar.delegate = self
            bar.defaultItemIdentifiers = profile.items.map { item in
                item.kind == .flexibleSpace ? .flexibleSpace : NSTouchBarItem.Identifier(Self.itemPrefix + item.id.uuidString)
            }
            touchBar = bar
            rebuilt = true
        }
        updatePresentation(forcePresent: rebuilt)
    }

    /// Whether our layout is wanted for the current app. Switching to an app where the
    /// user closed it takes it off; switching anywhere else brings it back.
    func setSuppressed(_ suppressed: Bool) {
        guard suppressed != isSuppressed else {
            updatePresentation(forcePresent: false)
            return
        }
        isSuppressed = suppressed
        updatePresentation(forcePresent: false)
    }

    private func updatePresentation(forcePresent: Bool) {
        let wanted = !isSuspended && !isSuppressed
        if !wanted {
            if isPresented { provider.dismiss() }
            isPresented = false
            return
        }
        guard let touchBar, forcePresent || !isPresented else { return }
        provider.present(touchBar)
        isPresented = true
    }

    /// Re-presents the current bar (menu "Show Layout on Touch Bar").
    func reshow() {
        isSuspended = false
        updatePresentation(forcePresent: true)
    }

    func hide() {
        isSuspended = true
        updatePresentation(forcePresent: false)
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
            case .clock: self.applyClock(to: button, config: item)
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

    /// Updates clock widgets in place.
    func updateClock(_ date: Date) {
        now = date
        for (id, config) in items where config.kind == .clock {
            if let button = buttons[id] { applyClock(to: button, config: config) }
        }
    }

    func updateVolume(_ state: VolumeState?) {
        volume = state
        for (id, config) in items where config.kind == .volume {
            if let slider = sliders[id] { applyVolume(to: slider, config: config) }
        }
    }

    func updateBrightness(_ value: Float?) {
        brightness = value
        for (id, config) in items where config.kind == .brightness {
            if let slider = sliders[id] { applyBrightness(to: slider, config: config) }
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
            applyFixedWidth(to: button, config: config)
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
            applyFixedWidth(to: button, config: config)
            buttons[id] = button
            item.view = button
            item.customizationLabel = L("Battery")
        case .microphone:
            let button = NSButton(title: "", target: self, action: #selector(buttonTapped(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(config.id.uuidString)
            button.imagePosition = .imageLeading
            applyMicrophone(to: button, config: config)
            applyFixedWidth(to: button, config: config)
            buttons[id] = button
            item.view = button
            item.customizationLabel = L("Microphone")
        case .clock:
            let button = NSButton(title: "", target: self, action: #selector(buttonTapped(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(config.id.uuidString)
            // Fixed-width digits, so the button doesn't change width every second.
            button.font = .monospacedDigitSystemFont(ofSize: button.font?.pointSize ?? NSFont.systemFontSize, weight: .regular)
            applyClock(to: button, config: config)
            applyFixedWidth(to: button, config: config)
            buttons[id] = button
            item.view = button
            item.customizationLabel = L("Clock")
        case .volume, .brightness:
            let slider = makeSlider(identifier: identifier, config: config)
            sliders[id] = slider
            return slider
        case .flexibleSpace:
            return nil
        }
        return item
    }

    private func makeSlider(identifier: NSTouchBarItem.Identifier, config: TouchBarItemConfig) -> NSSliderTouchBarItem {
        let item = NSSliderTouchBarItem(identifier: identifier)
        item.slider.minValue = 0
        item.slider.maxValue = 1
        item.slider.isContinuous = true
        // Room for bigger icons next to the track.
        if config.resolvedIconSize(default: defaultIconSize) > IconSize.standard + 2 { item.valueAccessoryWidth = .wide }
        let trackWidth = config.resolvedWidth(default: defaultWidth) ?? LayoutMetrics.sliderWidth
        item.minimumSliderWidth = trackWidth
        item.maximumSliderWidth = trackWidth
        if let color = config.color.nsColor { item.slider.trackFillColor = color }
        item.target = self
        item.action = #selector(sliderChanged(_:))
        item.customizationLabel = config.kind == .volume ? L("Volume") : L("Brightness")
        if config.kind == .volume {
            applyVolume(to: item, config: config)
        } else {
            item.minimumValueAccessory = NSSliderAccessory(image: sliderSymbol("sun.min.fill", config))
            item.maximumValueAccessory = NSSliderAccessory(image: sliderSymbol("sun.max.fill", config))
            applyBrightness(to: item, config: config)
        }
        return item
    }

    private func iconSize(_ config: TouchBarItemConfig) -> CGFloat {
        CGFloat(config.resolvedIconSize(default: defaultIconSize))
    }

    /// Slider icons are drawn slightly smaller than button icons, as in the Control Strip.
    private func sliderSymbol(_ name: String, _ config: TouchBarItemConfig) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: iconSize(config) - 2, weight: .regular)) ?? NSImage()
    }

    /// False while a finger is on the slider (or just lifted), so readings don't fight it.
    private func acceptsOutsideValue(_ id: UUID) -> Bool {
        guard let last = lastSliderInput[id] else { return true }
        return Date().timeIntervalSince(last) > 0.6
    }

    private func applyVolume(to item: NSSliderTouchBarItem, config: TouchBarItemConfig) {
        let muted = volume?.isMuted ?? false
        // Accessories can't change their image, so swap the accessory when the mute state flips.
        if item.minimumValueAccessory == nil || mutedVolumeSliders.contains(config.id) != muted {
            item.minimumValueAccessory = NSSliderAccessory(image: sliderSymbol(muted ? "speaker.slash.fill" : "speaker.fill", config))
            if muted { mutedVolumeSliders.insert(config.id) } else { mutedVolumeSliders.remove(config.id) }
        }
        if item.maximumValueAccessory == nil {
            item.maximumValueAccessory = NSSliderAccessory(image: sliderSymbol("speaker.wave.3.fill", config))
        }
        item.slider.isEnabled = volume?.canSetVolume ?? false
        if acceptsOutsideValue(config.id) { item.slider.doubleValue = Double(volume?.volume ?? 0) }
        let description = VolumeLabel.description(volume)
        item.slider.setAccessibilityLabel(description)
        item.slider.toolTip = description
    }

    private func applyBrightness(to item: NSSliderTouchBarItem, config: TouchBarItemConfig) {
        item.slider.isEnabled = brightness != nil
        if acceptsOutsideValue(config.id) { item.slider.doubleValue = Double(brightness ?? 0) }
        let description = BrightnessLabel.description(brightness)
        item.slider.setAccessibilityLabel(description)
        item.slider.toolTip = description
    }

    private func applyClock(to button: NSButton, config: TouchBarItemConfig) {
        button.title = config.clockText(at: now)
        button.bezelColor = config.color.nsColor
        let full = ClockFormat.dateAndTime.string(from: now)
        button.setAccessibilityLabel(full)
        button.toolTip = full
    }

    private func makeButton(for config: TouchBarItemConfig) -> NSButton {
        let title = config.showsTitle ? config.title : ""
        let image = IconProvider.image(for: config.icon, pointSize: iconSize(config))
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
    private static let fixedWidthID = "TouchBarStudio.fixedWidth"

    /// Width chosen by the user (Settings or the item itself); content is centred.
    private func applyFixedWidth(to button: NSButton, config: TouchBarItemConfig) {
        guard let width = config.resolvedWidth(default: defaultWidth) else { return }
        let constraint = button.widthAnchor.constraint(equalToConstant: width)
        constraint.identifier = Self.fixedWidthID
        constraint.isActive = true
    }

    /// Without a title, a widget is drawn as a centred icon in a button only slightly wider
    /// than the icon, instead of the standard 72 pt button with the icon on the left.
    private func fitWidget(_ button: NSButton, config: TouchBarItemConfig) {
        let iconOnly = !config.showsTitle
        button.imagePosition = iconOnly ? .imageOnly : .imageLeading
        button.constraints.filter { $0.identifier == Self.compactWidthID }.forEach { $0.isActive = false }
        // A fixed width set by the user wins over the compact one.
        guard iconOnly, config.resolvedWidth(default: defaultWidth) == nil, let image = button.image else { return }
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
            .withSymbolConfiguration(.init(pointSize: iconSize(config), weight: .regular))
        button.title = config.showsTitle ? (microphone.isMuted ? L("Muted") : L("Mic on")) : ""
        fitWidget(button, config: config)
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
            .withSymbolConfiguration(.init(pointSize: iconSize(config), weight: .regular))
        button.title = config.showsTitle ? battery.percentageText : ""
        fitWidget(button, config: config)
        switch battery.level {
        case .critical: button.bezelColor = .systemRed
        case .low: button.bezelColor = .systemOrange
        case .normal: button.bezelColor = config.color.nsColor
        }
        button.setAccessibilityLabel(battery.accessibilityDescription)
        button.toolTip = battery.accessibilityDescription
    }

    @objc private func sliderChanged(_ sender: NSSliderTouchBarItem) {
        let raw = String(sender.identifier.rawValue.dropFirst(Self.itemPrefix.count))
        guard let id = UUID(uuidString: raw), let config = items[id] else { return }
        lastSliderInput[id] = Date()
        onSliderChange?(config.kind, Float(sender.slider.doubleValue))
    }

    @objc private func buttonTapped(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw), let config = items[id] else { return }
        onTap?(config)
    }
}
