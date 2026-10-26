import Foundation
import Observation
import TouchBarStudioCore

/// Publishes the built-in display's brightness. macOS has no public change notification,
/// so it is read twice a second (a cheap call), which also catches the brightness keys,
/// Control Center and auto-brightness.
@MainActor
@Observable
final class BrightnessMonitor {
    /// 0…1, nil when the brightness can't be read.
    private(set) var brightness: Float? = DisplayBrightness.current()

    @ObservationIgnored var onChange: ((Float?) -> Void)?
    @ObservationIgnored private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        let new = DisplayBrightness.current()
        // Ignore float noise so the slider doesn't jitter.
        if let new, let old = brightness, abs(new - old) < 0.002 { return }
        guard new != brightness else { return }
        brightness = new
        onChange?(new)
    }
}
