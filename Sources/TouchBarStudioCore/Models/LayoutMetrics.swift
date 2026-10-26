import Foundation

/// Approximate widths of Touch Bar items, calibrated against captures of a real
/// 13" MacBook Pro Touch Bar (`screencapture -b`). Estimates only: macOS decides the
/// final layout and hides items that do not fit.
public enum LayoutMetrics {
    /// App area of the Touch Bar, excluding the esc key, in points.
    public static let fullWidth: Double = 1004
    /// Collapsed system Control Strip.
    public static let controlStripWidth: Double = 306
    /// Close button shown by the experimental system-modal mode when the Control Strip is kept.
    public static let closeButtonWidth: Double = 60
    public static let itemSpacing: Double = 8

    public static func availableWidth(showsControlStrip: Bool, showsCloseButton: Bool = false) -> Double {
        fullWidth - (showsControlStrip ? controlStripWidth : 0) - (showsCloseButton ? closeButtonWidth : 0) - 16
    }

    /// `defaultIconSize` is the Settings value; items may override it.
    public static func estimatedWidth(of item: TouchBarItemConfig, defaultIconSize: Double = IconSize.standard,
                                      defaultWidth: Double? = nil) -> Double {
        if let fixed = item.resolvedWidth(default: defaultWidth) {
            return item.isSlider ? fixed + 2 * sliderAccessoryWidth : fixed
        }
        // Icons were measured at the standard 16 pt; they grow in proportion.
        let iconScale = item.resolvedIconSize(default: defaultIconSize) / IconSize.standard
        switch item.kind {
        case .smallSpace: return 8
        case .largeSpace: return 32
        case .flexibleSpace: return 24
        // Battery icon plus "100%".
        case .battery: return item.showsTitle ? 92 + 27 * (iconScale - 1) : compactWidgetWidth(iconWidth: 27 * iconScale)
        // Mic icon plus "Muted" / "Mic on" (longest label in Russian: "Выключен").
        case .microphone: return item.showsTitle ? 112 + 14 * (iconScale - 1) : compactWidgetWidth(iconWidth: 14 * iconScale)
        // Text only, e.g. "14:05" (71 pt on hardware) or "Пн, 26 окт., 03:21" (124 pt).
        case .clock:
            return max(72, Double(item.clockText(at: widestSampleDate).count) * 6.3 + 14)
        // Slider plus the two accessory icons.
        case .volume, .brightness: return sliderWidth + 2 * sliderAccessoryWidth * max(1, iconScale)
        case .button:
            // Measured on hardware: icon-only 72 pt; "Mail" with icon 89 pt; "Notes" 90 pt; "Calendar" 107 pt.
            let title = item.showsTitle ? item.title : ""
            let iconWidth = item.icon.source == .none ? 0 : 16 * iconScale
            if title.isEmpty { return max(72, iconWidth + 40) }
            return max(72, Double(title.count) * 6.5 + (iconWidth > 0 ? iconWidth + 10 : 0) + 36)
        }
    }

    /// Icon-only widget button: the icon plus equal side padding.
    public static func compactWidgetWidth(iconWidth: Double) -> Double {
        (iconWidth + 2 * compactWidgetPadding).rounded(.up)
    }

    public static let compactWidgetPadding: Double = 13

    /// Width given to the track of volume and brightness sliders.
    public static let sliderWidth: Double = 150
    public static let sliderAccessoryWidth: Double = 36

    public static func estimatedWidth(of items: [TouchBarItemConfig], defaultIconSize: Double = IconSize.standard,
                                      defaultWidth: Double? = nil) -> Double {
        items.reduce(0) { $0 + estimatedWidth(of: $1, defaultIconSize: defaultIconSize, defaultWidth: defaultWidth) + itemSpacing }
    }

    /// Two-digit day, month, hour, minute and second, and a long month name: the widest a clock gets.
    static let widestSampleDate = Date(timeIntervalSince1970: 1_798_498_738) // 2026-12-28 22:58:58 UTC
}
