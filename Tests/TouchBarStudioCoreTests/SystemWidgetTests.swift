import Foundation
import Testing
@testable import TouchBarStudioCore

struct SystemWidgetTests {
    // 2026-10-26 14:05:09 UTC, a Monday.
    let date = Date(timeIntervalSince1970: 1_793_023_509)
    let utc24 = Locale(identifier: "en_GB")
    let utc12 = Locale(identifier: "en_US")

    func string(_ format: ClockFormat, _ language: AppLanguage, base: Locale) -> String {
        format.string(from: date, language: language, base: base, timeZone: TimeZone(identifier: "UTC")!)
    }

    @Test func clockFollowsHourCycleOfTheRegion() {
        #expect(string(.time, .english, base: utc24) == "14:05")
        #expect(string(.timeWithSeconds, .english, base: utc24) == "14:05:09")
        #expect(string(.time, .english, base: utc12).hasPrefix("2:05"))
    }

    @Test func clockUsesTheInterfaceLanguageForNames() {
        #expect(string(.dateAndTime, .english, base: utc24).contains("Mon"))
        #expect(string(.date, .russian, base: utc24).contains("октября"))
    }

    @Test func newWidgetsRoundTripInPresets() throws {
        let preset = Preset(name: "System", items: [.clock(.dateAndTime), .volume(), .brightness()])
        let imported = try PresetCodec.importPreset(from: PresetCodec.export(preset))
        #expect(imported.preset.items.map(\.kind) == [.clock, .volume, .brightness])
        #expect(imported.preset.items[0].clockFormat == .dateAndTime)
        #expect(imported.preset.items[0].action == .openApp("com.apple.iCal"))
        #expect(imported.preset.items[1].isSlider && !imported.preset.items[1].isTappable)
        #expect(imported.preset.items[0].isTappable)
    }

    @Test func itemsWithoutClockFormatStillDecode() throws {
        let json = #"{"kind":"clock","title":"Clock"}"#
        let item = try JSONDecoder().decode(TouchBarItemConfig.self, from: Data(json.utf8))
        #expect(item.kind == .clock && item.clockFormat == nil)
    }

    @Test func brightnessStepsLikeTheHardwareKeys() {
        #expect(DisplayBrightness.stepped(0.5, up: true) == Float(9) / 16)
        #expect(DisplayBrightness.stepped(0.51, up: false) == Float(7) / 16)
        #expect(DisplayBrightness.stepped(1, up: true) == 1)
        #expect(DisplayBrightness.stepped(0, up: false) == 0)
    }

    @Test func readsThisMacsVolumeAndBrightnessWithoutChangingThem() {
        if let state = VolumeControl.currentState() { #expect((0...1).contains(state.volume)) }
        if let value = DisplayBrightness.current() { #expect((0...1).contains(value)) }
    }

    @Test func newMediaKeysHaveHardwareCodes() {
        #expect(MediaKey.brightnessUp.systemKeyType == 2)
        #expect(MediaKey.brightnessDown.systemKeyType == 3)
        #expect(MediaKey.keyboardBrightnessUp.systemKeyType == 21)
        #expect(MediaKey.keyboardBrightnessDown.systemKeyType == 22)
        #expect(MediaKey.keyboardBrightnessUp.requiresAccessibility)
    }

    func custom(_ format: ClockCustomFormat, base: Locale? = nil, _ language: AppLanguage = .english) -> String {
        ClockFormat.custom.string(from: date, custom: format, language: language, base: base ?? utc24,
                                  timeZone: TimeZone(identifier: "UTC")!)
    }

    @Test func customClockFormatsCoverCommonNotations() {
        #expect(custom(.init(time: .hoursMinutesSeconds)) == "26.10 14:05:09")
        #expect(custom(.init(year: .twoDigits, time: .hoursMinutesSeconds)) == "26.10.26 14:05:09")
        #expect(custom(.init(time: .hoursMinutes)) == "26.10 14:05")
        #expect(custom(.init(year: .twoDigits, time: .hoursMinutes)) == "26.10.26 14:05")
        #expect(custom(.init(dateOrder: .monthDayYear, year: .twoDigits, dateSeparator: "/", time: .hoursMinutes)) == "10/26/26 14:05")
        #expect(custom(.init(dateOrder: .yearMonthDay, year: .fourDigits, dateSeparator: "-", time: .hoursMinutes)) == "2026-10-26 14:05")
        #expect(custom(.init(time: .hoursMinutesSeconds, timeSeparator: ".")) == "26.10 14.05.09")
        #expect(custom(.init(showsDate: false, time: .hoursMinutes, timeFirst: true)) == "14:05")
        #expect(custom(.init(time: .hoursMinutes, timeFirst: true)) == "14:05 26.10")
        #expect(custom(.init(showsWeekday: true, time: .none), .russian).hasSuffix("26.10"))
    }

    @Test func customClockHourCycle() {
        #expect(custom(.init(showsDate: false, time: .hoursMinutes, hourCycle: .twelveHour)).uppercased() == "2:05 PM")
        #expect(custom(.init(showsDate: false, time: .hoursMinutes, hourCycle: .twentyFourHour), base: utc12) == "14:05")
        #expect(custom(.init(showsDate: false, time: .hoursMinutes), base: utc12) == "2:05 PM")
    }

    @Test func customPatternOverridesOptions() {
        #expect(custom(.init(year: .fourDigits, pattern: "dd.MM HH:mm:ss")) == "26.10 14:05:09")
        #expect(ClockCustomFormat(year: .twoDigits, time: .hoursMinutesSeconds).placeholderText == "DD.MM.YY HH:MM:SS")
    }

    @Test func customClockRoundTripsAndDecodesLeniently() throws {
        let item = TouchBarItemConfig(kind: .clock, clockFormat: .custom,
                                      clockCustom: .init(dateOrder: .monthDayYear, year: .fourDigits, time: .hoursMinutesSeconds))
        let imported = try PresetCodec.importPreset(from: PresetCodec.export(Preset(name: "C", items: [item])))
        #expect(imported.preset.items[0].clockCustom == item.clockCustom)
        let partial = try JSONDecoder().decode(ClockCustomFormat.self, from: Data(#"{"year":"twoDigits","hourCycle":"bogus"}"#.utf8))
        #expect(partial.year == .twoDigits && partial.hourCycle == .system && partial.showsDate)
    }

    @Test func iconSizeFallsBackToSettingsAndIsClamped() throws {
        var item = TouchBarItemConfig.button("A", symbol: "star", action: .none, showsTitle: false)
        #expect(item.resolvedIconSize(default: 20) == 20)
        item.iconSize = 40
        #expect(item.resolvedIconSize(default: 20) == IconSize.range.upperBound)
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"iconSize":3}"#.utf8))
        #expect(settings.iconSize == IconSize.range.lowerBound)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).iconSize == IconSize.standard)
        // Bigger icons make icon-only widgets wider in the estimate.
        let mic = TouchBarItemConfig(kind: .microphone, showsTitle: false)
        #expect(LayoutMetrics.estimatedWidth(of: mic, defaultIconSize: 24) > LayoutMetrics.estimatedWidth(of: mic))
    }

    @Test func buttonWidthComesFromSettingsUnlessTheItemOverridesIt() throws {
        var button = TouchBarItemConfig.button("A", symbol: "star", action: .none)
        #expect(button.resolvedWidth(default: nil) == nil)
        #expect(button.resolvedWidth(default: 90) == 90)
        button.width = 120
        #expect(button.resolvedWidth(default: 90) == 120)
        button.width = ButtonWidth.fitContent
        #expect(button.resolvedWidth(default: 90) == nil)
        button.width = 5
        #expect(button.resolvedWidth(default: nil) == ButtonWidth.range.lowerBound)
        // Spaces never take the width; sliders only take their own.
        #expect(TouchBarItemConfig.space(.largeSpace).resolvedWidth(default: 90) == nil)
        var slider = TouchBarItemConfig.volume()
        #expect(slider.resolvedWidth(default: 90) == nil)
        slider.width = 250
        #expect(slider.resolvedWidth(default: 90) == 250)
        #expect(LayoutMetrics.estimatedWidth(of: [button, slider], defaultWidth: 90)
                == ButtonWidth.range.lowerBound + 250 + 2 * LayoutMetrics.sliderAccessoryWidth + 2 * LayoutMetrics.itemSpacing)

        #expect(try JSONDecoder().decode(AppSettings.self, from: Data(#"{"buttonWidth":1000}"#.utf8)).buttonWidth == ButtonWidth.range.upperBound)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).buttonWidth == nil)
        let imported = try PresetCodec.importPreset(from: PresetCodec.export(Preset(name: "W", items: [slider])))
        #expect(imported.preset.items[0].width == 250)
    }
}
