import AppKit
import TouchBarStudioCore

/// A mechanism that puts an `NSTouchBar` on the physical Touch Bar. Swappable so the
/// rest of the app does not care which integration is in use.
@MainActor
protocol TouchBarProvider: AnyObject {
    var kind: TouchBarProviderKind { get }
    /// Whether the bar remains visible while other applications are frontmost.
    /// Automatic per-app profiles only make sense when this is true.
    var showsOverOtherApps: Bool { get }
    func present(_ touchBar: NSTouchBar)
    func dismiss()
    /// Called when the presented bar's visibility changes for a reason other than
    /// `present`/`dismiss` (e.g. the user tapped the system close button).
    var onVisibilityChange: ((Bool) -> Void)? { get set }
}

extension TouchBarProviderKind {
    var title: String {
        switch self {
        case .application: L("Standard (public API)")
        case .systemModalExperimental: L("Over all apps (experimental)")
        }
    }

    var explanation: String {
        switch self {
        case .application:
            L("Uses AppKit's documented NSTouchBar API. Your layout appears on the Touch Bar while TouchBar Studio is the active app. macOS does not let a normal app change other apps' Touch Bars, so this mode cannot follow the frontmost app.")
        case .systemModalExperimental:
            L("Uses an undocumented macOS API (the same one used by Pock, MTMR and similar tools) to show your layout over every app, which also enables automatic per-app profiles. Apple does not support this API: it may stop working in a future macOS update. Verified on this Mac running macOS 27.0.1.")
        }
    }
}

/// Documented path: the bar is attached to `NSApplication`, the last stop of the
/// responder chain, so it shows whenever this app is active.
@MainActor
final class ApplicationTouchBarProvider: TouchBarProvider {
    let kind = TouchBarProviderKind.application
    let showsOverOtherApps = false
    var onVisibilityChange: ((Bool) -> Void)?

    func present(_ touchBar: NSTouchBar) {
        NSApp.touchBar = touchBar
    }

    func dismiss() {
        NSApp.touchBar = nil
    }
}

/// Experimental path using `+[NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:]`.
/// All calls are resolved at runtime and guarded, so a macOS update that removes the
/// selector makes `isAvailable` false instead of crashing.
@MainActor
final class SystemModalTouchBarProvider: TouchBarProvider {
    let kind = TouchBarProviderKind.systemModalExperimental
    let showsOverOtherApps = true

    /// 0 keeps the system Control Strip and shows a close button; 1 takes the whole bar.
    var keepControlStrip: Bool
    var onVisibilityChange: ((Bool) -> Void)?
    private var presented: NSTouchBar?
    private var visibilityObservation: NSKeyValueObservation?

    private static let presentSelector = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
    private static let dismissSelector = NSSelectorFromString("dismissSystemModalTouchBar:")

    static var isAvailable: Bool {
        class_getClassMethod(NSTouchBar.self, presentSelector) != nil
            && class_getClassMethod(NSTouchBar.self, dismissSelector) != nil
    }

    init(keepControlStrip: Bool) {
        self.keepControlStrip = keepControlStrip
    }

    func present(_ touchBar: NSTouchBar) {
        guard let method = class_getClassMethod(NSTouchBar.self, Self.presentSelector) else { return }
        typealias Present = @convention(c) (AnyClass, Selector, NSTouchBar, Int64, NSString?) -> Void
        let fn = unsafeBitCast(method_getImplementation(method), to: Present.self)
        let previous = presented
        visibilityObservation = nil
        fn(NSTouchBar.self, Self.presentSelector, touchBar, keepControlStrip ? 0 : 1, nil)
        presented = touchBar
        if let previous, previous !== touchBar { dismissBar(previous) }
        // NSTouchBar posts KVO for `visible` itself (+automaticallyNotifiesObserversOfVisible).
        let observed = ObjectIdentifier(touchBar)
        visibilityObservation = touchBar.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard let visible = change.newValue else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let presented = self.presented, ObjectIdentifier(presented) == observed else { return }
                    self.onVisibilityChange?(visible)
                }
            }
        }
    }

    /// Visibility of the presented bar as AppKit reports it; nil when nothing is presented.
    var presentedBarIsVisible: Bool? { presented?.isVisible }

    func dismiss() {
        visibilityObservation = nil
        if let presented { dismissBar(presented) }
        presented = nil
    }

    private func dismissBar(_ bar: NSTouchBar) {
        guard let method = class_getClassMethod(NSTouchBar.self, Self.dismissSelector) else { return }
        typealias Dismiss = @convention(c) (AnyClass, Selector, NSTouchBar) -> Void
        unsafeBitCast(method_getImplementation(method), to: Dismiss.self)(NSTouchBar.self, Self.dismissSelector, bar)
    }
}
