import SwiftUI
import TouchBarStudioCore

/// A drawing of the proposed layout. Deliberately labelled as a preview: it is not the
/// physical Touch Bar, and widths are estimates.
struct TouchBarPreview: View {
    @Environment(AppModel.self) private var model
    var items: [TouchBarItemConfig]
    @Binding var selection: UUID?
    var compact = false
    var showsControlStrip = true
    var showsCloseButton = false
    /// Single-click action (Dashboard: run the action).
    var onActivate: ((TouchBarItemConfig) -> Void)?
    /// Drag-and-drop support (Editor). Payloads: "item:<uuid>" or "component:<id>".
    var onDrop: ((_ payload: String, _ before: UUID?) -> Void)?

    var availableWidth: CGFloat { LayoutMetrics.availableWidth(showsControlStrip: showsControlStrip, showsCloseButton: showsCloseButton) }
    var estimatedWidth: CGFloat {
        LayoutMetrics.estimatedWidth(of: items, defaultIconSize: model.config.settings.iconSize,
                                     defaultWidth: model.config.settings.buttonWidth)
    }

    /// Width chosen in Settings or on the item, nil when it fits its content.
    private func fixedWidth(_ item: TouchBarItemConfig) -> CGFloat? {
        item.resolvedWidth(default: model.config.settings.buttonWidth).map { CGFloat($0) }
    }

    /// The preview is drawn at 14/16 of the real size, like the rest of its contents.
    private func previewIconSize(_ item: TouchBarItemConfig) -> CGFloat {
        CGFloat(item.resolvedIconSize(default: model.config.settings.iconSize)) * 14 / 16
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "eye")
                Text(L("PREVIEW — not the physical Touch Bar")).font(.caption.weight(.semibold))
                Spacer()
                if estimatedWidth > availableWidth {
                    StatusBadge(text: L("May not fit: ~%d of %d pt", Int(estimatedWidth), Int(availableWidth)), style: .warning)
                        .help(L("Items that don't fit are hidden by macOS. Widths are estimated."))
                }
            }
            .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 8) {
                    if showsCloseButton {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.5))
                            .help(L("Close button added by macOS in experimental mode"))
                    }
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            itemView(item)
                        }
                        if onDrop != nil {
                            dropTail
                        }
                    }
                    .frame(minWidth: compact ? nil : availableWidth, alignment: .leading)
                    if showsControlStrip {
                        controlStrip
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.12)))
                .environment(\.colorScheme, .dark)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("Touch Bar layout preview"))
        }
    }

    @ViewBuilder
    private func itemView(_ item: TouchBarItemConfig) -> some View {
        let selected = selection == item.id
        Group {
            switch item.kind {
            case .button:
                HStack(spacing: 6) {
                    if let image = IconProvider.image(for: item.icon, pointSize: previewIconSize(item)) {
                        Image(nsImage: image).renderingMode(item.icon.source == .symbol ? .template : .original)
                    }
                    if item.showsTitle && !item.title.isEmpty {
                        Text(item.title).font(.system(size: 13)).lineLimit(1)
                    } else if item.icon.source == .none {
                        Text("•")
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(width: fixedWidth(item))
                .frame(minWidth: fixedWidth(item) == nil ? 64 : nil, minHeight: 30, maxHeight: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(item.color.swiftUIColor))
            case .battery:
                BatteryLabel(status: model.battery.status, showsPercentage: item.showsTitle, iconSize: previewIconSize(item))
                    .foregroundStyle(.white)
                    .padding(.horizontal, item.showsTitle ? 12 : LayoutMetrics.compactWidgetPadding)
                    .frame(width: fixedWidth(item))
                    .frame(minWidth: item.showsTitle && fixedWidth(item) == nil ? 64 : nil, minHeight: 30, maxHeight: 30)
                    .background(RoundedRectangle(cornerRadius: 6).fill(batteryBackground(item)))
            case .microphone:
                MicrophoneLabel(state: model.microphone.state, showsTitle: item.showsTitle, iconSize: previewIconSize(item))
                    .foregroundStyle(.white)
                    .padding(.horizontal, item.showsTitle ? 12 : LayoutMetrics.compactWidgetPadding)
                    .frame(width: fixedWidth(item))
                    .frame(minWidth: item.showsTitle && fixedWidth(item) == nil ? 64 : nil, minHeight: 30, maxHeight: 30)
                    .background(RoundedRectangle(cornerRadius: 6).fill(
                        model.microphone.state?.isMuted == true ? Color.red : item.color.swiftUIColor))
            case .clock:
                ClockLabel(item: item)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(width: fixedWidth(item))
                    .frame(minWidth: fixedWidth(item) == nil ? 64 : nil, minHeight: 30, maxHeight: 30)
                    .background(RoundedRectangle(cornerRadius: 6).fill(item.color.swiftUIColor))
            case .volume:
                SliderPreview(minimumSymbol: model.volume.state?.isMuted == true ? "speaker.slash.fill" : "speaker.fill",
                              maximumSymbol: "speaker.wave.3.fill",
                              value: model.volume.state?.volume, tint: item.color, iconSize: previewIconSize(item) - 2,
                              trackWidth: fixedWidth(item) ?? LayoutMetrics.sliderWidth)
            case .brightness:
                SliderPreview(minimumSymbol: "sun.min.fill", maximumSymbol: "sun.max.fill",
                              value: model.brightness.brightness, tint: item.color, iconSize: previewIconSize(item) - 2,
                              trackWidth: fixedWidth(item) ?? LayoutMetrics.sliderWidth)
            case .smallSpace, .largeSpace, .flexibleSpace:
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .foregroundStyle(.white.opacity(onDrop == nil ? 0 : 0.35))
                    .frame(width: LayoutMetrics.estimatedWidth(of: item, defaultIconSize: model.config.settings.iconSize,
                                                              defaultWidth: model.config.settings.buttonWidth), height: 30)
                    .frame(maxWidth: item.kind == .flexibleSpace ? .infinity : nil)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0).padding(-2))
        .contentShape(Rectangle())
        .onTapGesture {
            selection = item.id
            onActivate?(item)
        }
        .help(helpText(item))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(item))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .modifier(DragDropModifier(item: item, onDrop: onDrop))
    }

    private func accessibilityLabel(_ item: TouchBarItemConfig) -> String {
        switch item.kind {
        case .button: item.title.isEmpty ? item.action.summary : item.title
        case .smallSpace: L("Small Space")
        case .largeSpace: L("Large Space")
        case .flexibleSpace: L("Flexible Space")
        case .battery: model.battery.status?.accessibilityDescription ?? L("No battery")
        case .microphone: MicrophoneLabel.description(model.microphone.state)
        case .clock: L("Clock")
        case .volume: VolumeLabel.description(model.volume.state)
        case .brightness: BrightnessLabel.description(model.brightness.brightness)
        }
    }

    private func helpText(_ item: TouchBarItemConfig) -> String {
        switch item.kind {
        case .battery: model.battery.status?.accessibilityDescription ?? L("No battery")
        case .microphone: MicrophoneLabel.description(model.microphone.state)
        case .volume: VolumeLabel.description(model.volume.state)
        case .brightness: BrightnessLabel.description(model.brightness.brightness)
        default: item.action.summary
        }
    }

    private func batteryBackground(_ item: TouchBarItemConfig) -> Color {
        switch model.battery.status?.level {
        case .critical: .red
        case .low: .orange
        default: item.color.swiftUIColor
        }
    }

    private var dropTail: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
            .foregroundStyle(.white.opacity(0.25))
            .overlay(Image(systemName: "plus").foregroundStyle(.white.opacity(0.4)))
            .frame(width: 44, height: 30)
            .dropDestination(for: String.self) { payloads, _ in
                guard let payload = payloads.first else { return false }
                onDrop?(payload, nil)
                return true
            }
            .help(L("Drop here to add at the end"))
    }

    private var controlStrip: some View {
        HStack(spacing: 2) {
            Image(systemName: "chevron.compact.left")
            ForEach(["sun.max.fill", "speaker.wave.2.fill", "speaker.slash.fill", "mic.fill"], id: \.self) { symbol in
                Image(systemName: symbol)
                    .frame(width: 52, height: 30)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.14)))
            }
        }
        .foregroundStyle(.white.opacity(0.5))
        .accessibilityLabel(L("System Control Strip"))
        .help(L("System Control Strip (managed by macOS)"))
    }
}

private struct DragDropModifier: ViewModifier {
    var item: TouchBarItemConfig
    var onDrop: ((String, UUID?) -> Void)?

    func body(content: Content) -> some View {
        if let onDrop {
            content
                .draggable("item:\(item.id.uuidString)")
                .dropDestination(for: String.self) { payloads, _ in
                    guard let payload = payloads.first else { return false }
                    onDrop(payload, item.id)
                    return true
                }
        } else {
            content
        }
    }
}

/// Battery icon plus percentage, as drawn on the Touch Bar.
struct BatteryLabel: View {
    var status: BatteryStatus?
    var showsPercentage = true
    /// nil: the surrounding font size.
    var iconSize: CGFloat?

    var body: some View {
        HStack(spacing: 6) {
            if let status {
                Image(systemName: status.symbolName).font(iconSize.map { .system(size: $0) })
                if showsPercentage {
                    Text(status.percentageText).font(.system(size: 13).monospacedDigit()).lineLimit(1)
                }
            } else {
                Image(systemName: "powerplug").font(iconSize.map { .system(size: $0) })
                if showsPercentage { Text(L("No battery")).font(.system(size: 13)).lineLimit(1) }
            }
        }
    }
}

/// Microphone icon plus state, as drawn on the Touch Bar.
struct MicrophoneLabel: View {
    var state: MicrophoneState?
    var showsTitle = true
    /// nil: the surrounding font size.
    var iconSize: CGFloat?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state?.symbolName ?? "mic.slash").font(iconSize.map { .system(size: $0) })
            if showsTitle {
                Text(state == nil ? L("No microphone") : (state!.isMuted ? L("Muted") : L("Mic on")))
                    .font(.system(size: 13)).lineLimit(1)
            }
        }
    }

    static func description(_ state: MicrophoneState?) -> String {
        guard let state else { return L("No microphone") }
        return state.isMuted ? L("Microphone muted: %@", state.deviceName) : L("Microphone on: %@", state.deviceName)
    }
}

/// Current time in the widget's format; redraws every second.
struct ClockLabel: View {
    @Environment(AppModel.self) private var model
    var item: TouchBarItemConfig

    var body: some View {
        Text(item.clockText(at: model.clock.now)).font(.system(size: 13).monospacedDigit()).lineLimit(1)
    }
}

/// Static drawing of a Touch Bar slider at the current level.
private struct SliderPreview: View {
    var minimumSymbol: String
    var maximumSymbol: String
    var value: Float?
    var tint: ButtonColor
    var iconSize: CGFloat
    var trackWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: minimumSymbol).font(.system(size: iconSize)).frame(width: LayoutMetrics.sliderAccessoryWidth)
            GeometryReader { geometry in
                let fraction = CGFloat(value ?? 0)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25)).frame(height: 4)
                    Capsule().fill(tint == .standard ? Color.white : tint.swiftUIColor)
                        .frame(width: geometry.size.width * fraction, height: 4)
                    Circle().fill(Color.white).frame(width: 18, height: 18)
                        .offset(x: (geometry.size.width - 18) * fraction)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(width: trackWidth)
            Image(systemName: maximumSymbol).font(.system(size: iconSize)).frame(width: LayoutMetrics.sliderAccessoryWidth)
        }
        .foregroundStyle(.white)
        .opacity(value == nil ? 0.4 : 1)
        .frame(height: 30)
    }
}

enum VolumeLabel {
    static func description(_ state: VolumeState?) -> String {
        guard let state else { return L("No sound output") }
        return L("Volume %@: %@", state.percentageText, state.deviceName) + (state.isMuted ? " (" + L("Muted") + ")" : "")
    }
}

enum BrightnessLabel {
    static func description(_ value: Float?) -> String {
        guard let value else { return L("Brightness can't be changed") }
        return L("Brightness %d%%", Int((value * 100).rounded()))
    }
}
