import Foundation
import IOKit.ps
import Observation
import TouchBarStudioCore

/// Publishes the internal battery's state. Updates come from IOKit's power-source change
/// notification, with a slow timer as a safety net.
@MainActor
@Observable
final class BatteryMonitor {
    /// nil on Macs without an internal battery.
    private(set) var status: BatteryStatus? = BatteryStatus.current()

    @ObservationIgnored var onChange: ((BatteryStatus?) -> Void)?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var timer: Timer?

    func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            // Delivered on the main run loop, where the source is installed.
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        let new = BatteryStatus.current()
        guard new != status else { return }
        status = new
        onChange?(new)
    }
}
