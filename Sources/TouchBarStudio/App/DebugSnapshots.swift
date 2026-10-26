#if DEBUG
import AppKit
import TouchBarStudioCore

/// Development aid: with `TBS_SNAPSHOT_DIR` set, a debug build renders its own main
/// window to PNG for every sidebar section and quits. Uses `cacheDisplay`, so it needs
/// no Screen Recording permission. Not compiled into release builds.
@MainActor
enum DebugSnapshots {
    private static func describe(_ bar: NSTouchBar?) -> String {
        guard let bar else { return "nil" }
        return "\(bar.defaultItemIdentifiers.count) ids, visible=\(bar.isVisible), delegate=\(bar.delegate.map { "\(type(of: $0))" } ?? "nil")"
    }

    nonisolated private static func append(_ text: String, to path: String) {
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile(); handle.write(Data(text.utf8)); handle.closeFile()
        } else {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// With `TBS_DEBUG_TOUCHBAR` set, writes the responder chain and each responder's touch
    /// bar to that file every 2 s, to diagnose an empty Touch Bar.
    static func traceTouchBarIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["TBS_DEBUG_TOUCHBAR"] else { return }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                var lines = ["\(Date()) active=\(NSApp.isActive) key=\(NSApp.keyWindow.map { "\(type(of: $0)) '\($0.title)'" } ?? "nil")"]
                var responder: NSResponder? = NSApp.keyWindow?.firstResponder
                while let current = responder {
                    lines.append("  \(type(of: current)): \(describe(current.touchBar))")
                    responder = current.nextResponder
                }
                lines.append("  NSApp.touchBar: \(describe(NSApp.touchBar))")
                append(lines.joined(separator: "\n") + "\n", to: path)
            }
        }
    }

    /// With `TBS_DEBUG_SWITCH_PROVIDER=<kind>[:seconds]`, switches the Touch Bar provider
    /// at runtime, to test mode changes without clicking through Settings.
    static func switchProviderIfRequested(model: AppModel) {
        guard let spec = ProcessInfo.processInfo.environment["TBS_DEBUG_SWITCH_PROVIDER"] else { return }
        let parts = spec.split(separator: ":")
        guard let kind = TouchBarProviderKind(rawValue: String(parts[0])) else { return }
        let delay = parts.count > 1 ? Double(parts[1]) ?? 6 : 6
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            model.config.settings.providerKind = kind
        }
    }

    /// With `TBS_DEBUG_TAP=<itemKind>:<seconds>[,<seconds>…]`, performs the first item of that
    /// kind in the displayed profile at each time, exactly as a Touch Bar tap would.
    static func tapIfRequested(model: AppModel) {
        guard let spec = ProcessInfo.processInfo.environment["TBS_DEBUG_TAP"] else { return }
        let parts = spec.split(separator: ":")
        guard parts.count == 2, let kind = ItemKind(rawValue: String(parts[0])) else { return }
        for delay in parts[1].split(separator: ",").compactMap({ Double($0) }) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                if let item = model.activeProfile.items.first(where: { $0.kind == kind }) {
                    model.perform(item, source: "Debug tap")
                }
            }
        }
    }

    /// With `TBS_DEBUG_VISIBILITY=<file>`, appends every visibility change of the presented
    /// bar plus app switches, to learn how the system close button, fn and locking behave.
    static func traceVisibilityIfRequested(model: AppModel) {
        guard let path = ProcessInfo.processInfo.environment["TBS_DEBUG_VISIBILITY"] else { return }
        let log: @Sendable (String) -> Void = { text in append("\(Date().timeIntervalSince1970) \(text)\n", to: path) }
        let previous = model.touchBar.provider.onVisibilityChange
        model.touchBar.provider.onVisibilityChange = { visible in
            log("visible=\(visible) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
            previous?(visible)
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier ?? "?"
            log("activate \(id)")
        }
        log("trace started, provider=\(model.touchBar.provider.kind.rawValue)")
        var lastPolled: Bool??
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            MainActor.assumeIsolated {
                let polled = (model.touchBar.provider as? SystemModalTouchBarProvider)?.presentedBarIsVisible
                if lastPolled == nil || lastPolled! != polled {
                    log("poll isVisible=\(polled.map { "\($0)" } ?? "none") front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")")
                    lastPolled = polled
                }
            }
        }
    }

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
