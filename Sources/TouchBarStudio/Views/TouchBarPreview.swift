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
    var estimatedWidth: CGFloat { LayoutMetrics.estimatedWidth(of: items) }

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
                    if let image = IconProvider.image(for: item.icon, pointSize: 14) {
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
                .frame(minWidth: 64, minHeight: 30, maxHeight: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(item.color.swiftUIColor))
            case .battery:
                BatteryLabel(status: model.battery.status, showsPercentage: item.showsTitle)
                    .foregroundStyle(.white)
                    .padding(.horizontal, item.showsTitle ? 12 : LayoutMetrics.compactWidgetPadding)
                    .frame(minWidth: item.showsTitle ? 64 : nil, minHeight: 30, maxHeight: 30)
                    .background(RoundedRectangle(cornerRadius: 6).fill(batteryBackground(item)))
            case .microphone:
                MicrophoneLabel(state: model.microphone.state, showsTitle: item.showsTitle)
                    .foregroundStyle(.white)
                    .padding(.horizontal, item.showsTitle ? 12 : LayoutMetrics.compactWidgetPadding)
                    .frame(minWidth: item.showsTitle ? 64 : nil, minHeight: 30, maxHeight: 30)
                    .background(RoundedRectangle(cornerRadius: 6).fill(
                        model.microphone.state?.isMuted == true ? Color.red : item.color.swiftUIColor))
            case .smallSpace, .largeSpace, .flexibleSpace:
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .foregroundStyle(.white.opacity(onDrop == nil ? 0 : 0.35))
                    .frame(width: LayoutMetrics.estimatedWidth(of: item), height: 30)
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
        }
    }

    private func helpText(_ item: TouchBarItemConfig) -> String {
        switch item.kind {
        case .battery: model.battery.status?.accessibilityDescription ?? L("No battery")
        case .microphone: MicrophoneLabel.description(model.microphone.state)
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

    var body: some View {
        HStack(spacing: 6) {
            if let status {
                Image(systemName: status.symbolName)
                if showsPercentage {
                    Text(status.percentageText).font(.system(size: 13).monospacedDigit()).lineLimit(1)
                }
            } else {
                Image(systemName: "powerplug")
                if showsPercentage { Text(L("No battery")).font(.system(size: 13)).lineLimit(1) }
            }
        }
    }
}

/// Microphone icon plus state, as drawn on the Touch Bar.
struct MicrophoneLabel: View {
    var state: MicrophoneState?
    var showsTitle = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state?.symbolName ?? "mic.slash")
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
