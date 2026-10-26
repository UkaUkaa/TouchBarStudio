import Foundation
import Observation

/// Ticks at the start of every second for clock widgets.
@MainActor
@Observable
final class ClockMonitor {
    private(set) var now = Date()

    @ObservationIgnored var onChange: ((Date) -> Void)?
    @ObservationIgnored private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        scheduleNextTick()
    }

    /// One-shot timers aligned to the next whole second, so the display never lags a
    /// second behind and drift doesn't accumulate.
    private func scheduleNextTick() {
        let date = Date()
        let next = date.timeIntervalSinceReferenceDate.rounded(.down) + 1
        let timer = Timer(fire: Date(timeIntervalSinceReferenceDate: next + 0.01), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = Date()
                self.onChange?(self.now)
                self.scheduleNextTick()
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
