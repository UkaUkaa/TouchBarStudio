#if DEBUG
import AppKit

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
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(section.rawValue).png"))
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
