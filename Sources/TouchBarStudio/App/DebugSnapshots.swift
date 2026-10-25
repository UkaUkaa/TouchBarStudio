#if DEBUG
import AppKit
import TouchBarStudioCore

/// Development aid: with `TBS_SNAPSHOT_DIR` set, a debug build renders its own main
/// window to PNG for every sidebar section and quits. Uses `cacheDisplay`, so it needs
/// no Screen Recording permission. Not compiled into release builds.
@MainActor
enum DebugSnapshots {
    static func runIfRequested(model: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["TBS_SNAPSHOT_DIR"] else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            for section in SidebarSection.allCases {
                model.section = section
                try? await Task.sleep(for: .milliseconds(900))
                let candidates = NSApp.windows.filter { ($0.contentView?.bounds.width ?? 0) > 400 }
                if section == .dashboard {
                    let info = NSApp.windows.map { "\(type(of: $0)) '\($0.title)' visible=\($0.isVisible) \($0.frame)" }.joined(separator: "\n")
                    try? info.write(toFile: dir + "/windows.txt", atomically: true, encoding: .utf8)
                }
                guard let window = candidates.first,
                      let view = window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                // Transparent regions would show as white in viewers; composite onto the window background.
                guard let output = rep.copy() as? NSBitmapImageRep else { continue }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
                window.effectiveAppearance.performAsCurrentDrawingAppearance {
                    NSColor.windowBackgroundColor.setFill()
                }
                NSRect(origin: .zero, size: rep.size).fill()
                rep.draw(in: NSRect(origin: .zero, size: rep.size), from: .zero, operation: .sourceOver, fraction: 1,
                         respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
                try? output.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(section.rawValue).png"))
            }
            // Optionally switch the language at runtime and capture Settings again, to
            // check that the interface updates without a restart.
            if let code = ProcessInfo.processInfo.environment["TBS_SNAPSHOT_SWITCH_LANGUAGE"],
               let language = AppLanguage(rawValue: code) {
                model.setLanguage(language)
                model.section = .settings
                try? await Task.sleep(for: .milliseconds(900))
                if let window = NSApp.windows.first(where: { ($0.contentView?.bounds.width ?? 0) > 400 }),
                   let view = window.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings-after-switch.png"))
                }
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
