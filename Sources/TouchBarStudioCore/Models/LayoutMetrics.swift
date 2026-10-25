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

    public static func estimatedWidth(of item: TouchBarItemConfig) -> Double {
        switch item.kind {
        case .smallSpace: return 8
        case .largeSpace: return 32
        case .flexibleSpace: return 24
        // Battery icon plus "100%".
        case .battery: return item.showsTitle ? 92 : 72
        case .button:
            // Measured on hardware: icon-only 72 pt; "Mail" with icon 89 pt; "Notes" 90 pt; "Calendar" 107 pt.
            let title = item.showsTitle ? item.title : ""
            if title.isEmpty { return 72 }
            return max(72, Double(title.count) * 6.5 + (item.icon.source == .none ? 0 : 26) + 36)
        }
    }

    public static func estimatedWidth(of items: [TouchBarItemConfig]) -> Double {
        items.reduce(0) { $0 + estimatedWidth(of: $1) + itemSpacing }
    }
}
