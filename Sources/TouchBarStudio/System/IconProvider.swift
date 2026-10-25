import AppKit
import TouchBarStudioCore

/// Resolves `ButtonIcon`s to images; shared by the physical Touch Bar and the preview.
@MainActor
enum IconProvider {
    private static var cache: [String: NSImage] = [:]

    static func image(for icon: ButtonIcon, pointSize: CGFloat = 16) -> NSImage? {
        let key = "\(icon.source.rawValue)|\(icon.value)|\(pointSize)"
        if let cached = cache[key] { return cached }
        let image: NSImage?
        switch icon.source {
        case .none:
            image = nil
        case .symbol:
            image = NSImage(systemSymbolName: icon.value, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
        case .appIcon:
            image = appIcon(bundleIdentifier: icon.value, size: pointSize + 6)
        case .imageFile:
            let path = (icon.value as NSString).expandingTildeInPath
            image = NSImage(contentsOfFile: path).map { resized($0, height: pointSize + 6) }
        }
        if let image { cache[key] = image }
        return image
    }

    static func appIcon(bundleIdentifier: String, size: CGFloat) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    static func appName(bundleIdentifier: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func isValidSymbol(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    static func invalidate() { cache.removeAll() }

    private static func resized(_ image: NSImage, height: CGFloat) -> NSImage {
        guard image.size.height > 0 else { return image }
        let width = image.size.width * height / image.size.height
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: width, height: height)
        return copy
    }
}

extension ButtonColor {
    var nsColor: NSColor? {
        switch self {
        case .standard: nil
        case .gray: .systemGray
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        }
    }
}
