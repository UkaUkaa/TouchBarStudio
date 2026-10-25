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
    public static let closeButtonWidth: Double = 64
    public static let itemSpacing: Double = 8

    public static func availableWidth(showsControlStrip: Bool, showsCloseButton: Bool = false) -> Double {
        fullWidth - (showsControlStrip ? controlStripWidth : 0) - (showsCloseButton ? closeButtonWidth : 0) - 16
    }

    public static func estimatedWidth(of item: TouchBarItemConfig) -> Double {
        switch item.kind {
        case .smallSpace: return 8
        case .largeSpace: return 32
        case .flexibleSpace: return 24
        case .button:
            let title = item.showsTitle ? item.title : ""
            if title.isEmpty { return 64 }
            return max(64, Double(title.count) * 7.6 + (item.icon.source == .none ? 0 : 26) + 26)
        }
    }

    public static func estimatedWidth(of items: [TouchBarItemConfig]) -> Double {
        items.reduce(0) { $0 + estimatedWidth(of: $1) + itemSpacing }
    }
}
