import Foundation
import IOKit.ps
import Testing
@testable import TouchBarStudioCore

struct BatteryStatusTests {
    func description(current: Int = 87, max: Int = 100, charging: Bool = false, ac: Bool = false,
                     toEmpty: Int = 240, toFull: Int = 0, type: String = kIOPSInternalBatteryType) -> [String: Any] {
        [
            kIOPSTypeKey: type,
            kIOPSIsPresentKey: true,
            kIOPSCurrentCapacityKey: current,
            kIOPSMaxCapacityKey: max,
            kIOPSIsChargingKey: charging,
            kIOPSPowerSourceStateKey: ac ? kIOPSACPowerValue : kIOPSBatteryPowerValue,
            kIOPSTimeToEmptyKey: toEmpty,
            kIOPSTimeToFullChargeKey: toFull,
        ]
    }

    @Test func parsesDischargingBattery() throws {
        let s = try #require(BatteryStatus(powerSourceDescription: description()))
        #expect(s.percentage == 87)
        #expect(!s.isCharging && !s.isOnACPower)
        #expect(s.minutesRemaining == 240)
        #expect(s.percentageText == "87%")
        #expect(s.symbolName == "battery.75")
        #expect(s.accessibilityDescription == "Battery 87%, 4 h 0 min remaining")
    }

    @Test func parsesChargingBattery() throws {
        let s = try #require(BatteryStatus(powerSourceDescription: description(current: 98, charging: true, ac: true, toEmpty: 0, toFull: 27)))
        #expect(s.isCharging && s.isOnACPower)
        #expect(s.minutesRemaining == 27)
        #expect(s.symbolName == "battery.100.bolt")
        #expect(s.accessibilityDescription == "Battery 98%, charging, 27 min to full")
        #expect(s.level == .normal)
    }

    @Test func scalesNonPercentCapacity() throws {
        // Some batteries report capacity in mAh rather than percent.
        let s = try #require(BatteryStatus(powerSourceDescription: description(current: 2500, max: 5000)))
        #expect(s.percentage == 50)
    }

    @Test func ignoresNonBatterySources() {
        #expect(BatteryStatus(powerSourceDescription: description(type: "UPS")) == nil)
        #expect(BatteryStatus(powerSourceDescription: description(max: 0)) == nil)
    }

    @Test func estimatingTimeIsNotShown() throws {
        let s = try #require(BatteryStatus(powerSourceDescription: description(toEmpty: -1)))
        #expect(s.minutesRemaining == nil)
        #expect(s.accessibilityDescription == "Battery 87%")
    }

    @Test func levelsOnlyWarnOnBatteryPower() {
        #expect(BatteryStatus(percentage: 20, isCharging: false, isOnACPower: false).level == .low)
        #expect(BatteryStatus(percentage: 10, isCharging: false, isOnACPower: false).level == .critical)
        #expect(BatteryStatus(percentage: 5, isCharging: true, isOnACPower: true).level == .normal)
        #expect(BatteryStatus(percentage: 21, isCharging: false, isOnACPower: false).level == .normal)
    }

    @Test func symbolThresholds() {
        let symbols = [100, 88, 87, 63, 62, 38, 37, 13, 12, 0].map {
            BatteryStatus(percentage: $0, isCharging: false, isOnACPower: false).symbolName
        }
        #expect(symbols == ["battery.100", "battery.100", "battery.75", "battery.75", "battery.50",
                            "battery.50", "battery.25", "battery.25", "battery.0", "battery.0"])
    }

    @Test func russianDescription() {
        L10n.$override.withValue(.russian) {
            let s = BatteryStatus(percentage: 45, isCharging: false, isOnACPower: false, minutesRemaining: 95)
            #expect(s.accessibilityDescription == "Батарея 45%, осталось 1 ч 35 мин")
        }
    }

    @Test func batteryWidgetRoundTripsInPresets() throws {
        let preset = Preset(name: "With battery", items: [.battery(), .button("A", action: .copy("a"))])
        let imported = try PresetCodec.importPreset(from: PresetCodec.export(preset))
        #expect(imported.preset.items[0].kind == .battery)
        #expect(imported.preset.items[0].action == .openURL(TouchBarItemConfig.batterySettingsURL))
        #expect(!imported.warnings.contains { $0.message.contains("no action") })
    }

    @Test func readsThisMacsBattery() {
        // On a MacBook this returns a real reading; on desktops it is nil. Either way it must not crash.
        if let s = BatteryStatus.current() {
            #expect((0...100).contains(s.percentage))
        }
    }
}
