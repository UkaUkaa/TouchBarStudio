import Foundation
import IOKit.ps

/// Battery state read from IOKit's power-source API (public, no permission needed).
public struct BatteryStatus: Equatable, Sendable {
    /// 0…100.
    public var percentage: Int
    public var isCharging: Bool
    /// Connected to a power adapter (charging, fully charged or on hold).
    public var isOnACPower: Bool
    /// Minutes until empty (on battery) or full (charging), when macOS has an estimate.
    public var minutesRemaining: Int?

    public init(percentage: Int, isCharging: Bool, isOnACPower: Bool, minutesRemaining: Int? = nil) {
        self.percentage = percentage
        self.isCharging = isCharging
        self.isOnACPower = isOnACPower
        self.minutesRemaining = minutesRemaining
    }

    /// Parses one `IOPSGetPowerSourceDescription` dictionary. Returns nil for sources that
    /// aren't an internal battery (UPS, accessories) or that report no capacity.
    public init?(powerSourceDescription d: [String: Any]) {
        guard (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
              (d[kIOPSIsPresentKey] as? Bool) ?? true,
              let current = d[kIOPSCurrentCapacityKey] as? Int,
              let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { return nil }
        percentage = Swift.min(100, Swift.max(0, Int((Double(current) * 100 / Double(max)).rounded())))
        isCharging = (d[kIOPSIsChargingKey] as? Bool) ?? false
        isOnACPower = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let minutes = isCharging ? d[kIOPSTimeToFullChargeKey] as? Int : d[kIOPSTimeToEmptyKey] as? Int
        // IOKit reports -1 while it is still estimating and 0 when not applicable.
        minutesRemaining = (minutes ?? 0) > 0 ? minutes : nil
    }

    /// Internal battery of this Mac, or nil on Macs without one.
    public static func current() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            if let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
               let status = BatteryStatus(powerSourceDescription: description) {
                return status
            }
        }
        return nil
    }

    /// SF Symbol for the current level. macOS only ships a bolt variant for the full icon.
    public var symbolName: String {
        if isCharging { return "battery.100.bolt" }
        switch percentage {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }

    public var percentageText: String { "\(percentage)%" }

    public enum Level: Equatable, Sendable { case normal, low, critical }

    /// Low/critical only matter when running on battery.
    public var level: Level {
        guard !isOnACPower else { return .normal }
        if percentage <= 10 { return .critical }
        if percentage <= 20 { return .low }
        return .normal
    }

    /// Spoken/hover description, e.g. "Battery 87%, charging, 25 min to full".
    public var accessibilityDescription: String {
        var parts = [L("Battery %@", percentageText)]
        if isCharging {
            parts.append(L("charging"))
            if let m = minutesRemaining { parts.append(L("%@ to full", Self.formatMinutes(m))) }
        } else if isOnACPower {
            parts.append(L("on power adapter"))
        } else if let m = minutesRemaining {
            parts.append(L("%@ remaining", Self.formatMinutes(m)))
        }
        return parts.joined(separator: ", ")
    }

    static func formatMinutes(_ minutes: Int) -> String {
        minutes >= 60 ? L("%d h %d min", minutes / 60, minutes % 60) : L("%d min", minutes)
    }
}
