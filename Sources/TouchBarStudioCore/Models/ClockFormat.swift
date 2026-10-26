import Foundation

/// What the clock widget shows. The named formats follow the interface language and the
/// region and 12/24-hour settings of macOS; `.custom` is built by the user from
/// `ClockCustomFormat`.
public enum ClockFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case time, timeWithSeconds, dateAndTime, date, custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .time: L("Time")
        case .timeWithSeconds: L("Time with seconds")
        case .dateAndTime: L("Date and time")
        case .date: L("Date")
        case .custom: L("Custom")
        }
    }

    var template: String {
        switch self {
        case .time: "jmm"
        case .timeWithSeconds: "jmmss"
        case .dateAndTime: "EEEdMMMjmm"
        case .date: "EEEdMMMM"
        case .custom: "jmm" // not used: custom formats have their own pattern
        }
    }

    /// Formats `date` in `language`, keeping the region and hour-cycle preferences of `base`.
    /// `custom` is used by `.custom` (defaults when nil).
    public func string(from date: Date, custom: ClockCustomFormat? = nil, language: AppLanguage = L10n.language,
                       base: Locale = .autoupdatingCurrent, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let locale = Self.locale(language: language, base: base)
        let pattern = self == .custom
            ? (custom ?? ClockCustomFormat()).dateFormat(base: base)
            : DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale) ?? "HH:mm"
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// The interface language with the region and hour-cycle preferences of `base`.
    static func locale(language: AppLanguage, base: Locale) -> Locale {
        var components = Locale.Components(locale: base)
        // Keep the region: it decides the order of date parts and the default hour cycle.
        components.languageComponents = Locale.Language.Components(
            languageCode: .init(language.resolved == .russian ? "ru" : "en"), script: nil, region: base.region)
        return Locale(components: components)
    }
}

/// A clock format put together from parts, e.g. `26.10 14:05:09`, `10/26/26 2:05 PM` or
/// `2026-10-26 14:05`.
public struct ClockCustomFormat: Codable, Hashable, Sendable {
    public enum DateOrder: String, Codable, CaseIterable, Sendable, Identifiable {
        /// DD.MM.YY
        case dayMonthYear
        /// MM.DD.YY
        case monthDayYear
        /// YY.MM.DD
        case yearMonthDay
        public var id: String { rawValue }
    }

    public enum YearStyle: String, Codable, CaseIterable, Sendable, Identifiable {
        case none, twoDigits, fourDigits
        public var id: String { rawValue }
    }

    public enum TimeStyle: String, Codable, CaseIterable, Sendable, Identifiable {
        case none, hoursMinutes, hoursMinutesSeconds
        public var id: String { rawValue }
    }

    public enum HourCycle: String, Codable, CaseIterable, Sendable, Identifiable {
        /// Whatever macOS is set to.
        case system, twentyFourHour, twelveHour
        public var id: String { rawValue }
    }

    public static let dateSeparators = [".", "/", "-", " "]
    public static let timeSeparators = [":", "."]

    public var showsDate: Bool
    public var dateOrder: DateOrder
    public var year: YearStyle
    public var dateSeparator: String
    /// Short weekday before the date ("Mon", "пн").
    public var showsWeekday: Bool
    public var time: TimeStyle
    public var timeSeparator: String
    public var hourCycle: HourCycle
    /// Time before the date instead of after it.
    public var timeFirst: Bool
    /// Advanced: a Unicode date pattern (e.g. `dd.MM HH:mm:ss`). When not empty it is used
    /// instead of all the options above.
    public var pattern: String

    public init(
        showsDate: Bool = true,
        dateOrder: DateOrder = .dayMonthYear,
        year: YearStyle = .none,
        dateSeparator: String = ".",
        showsWeekday: Bool = false,
        time: TimeStyle = .hoursMinutes,
        timeSeparator: String = ":",
        hourCycle: HourCycle = .system,
        timeFirst: Bool = false,
        pattern: String = ""
    ) {
        self.showsDate = showsDate
        self.dateOrder = dateOrder
        self.year = year
        self.dateSeparator = dateSeparator
        self.showsWeekday = showsWeekday
        self.time = time
        self.timeSeparator = timeSeparator
        self.hourCycle = hourCycle
        self.timeFirst = timeFirst
        self.pattern = pattern
    }

    enum CodingKeys: String, CodingKey {
        case showsDate, dateOrder, year, dateSeparator, showsWeekday, time, timeSeparator, hourCycle, timeFirst, pattern
    }

    // Lenient: missing or unknown values fall back to the defaults.
    public init(from decoder: Decoder) throws {
        let d = ClockCustomFormat()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showsDate = (try? c.decodeIfPresent(Bool.self, forKey: .showsDate)) ?? d.showsDate
        dateOrder = (try? c.decodeIfPresent(DateOrder.self, forKey: .dateOrder)) ?? d.dateOrder
        year = (try? c.decodeIfPresent(YearStyle.self, forKey: .year)) ?? d.year
        dateSeparator = (try? c.decodeIfPresent(String.self, forKey: .dateSeparator)) ?? d.dateSeparator
        showsWeekday = (try? c.decodeIfPresent(Bool.self, forKey: .showsWeekday)) ?? d.showsWeekday
        time = (try? c.decodeIfPresent(TimeStyle.self, forKey: .time)) ?? d.time
        timeSeparator = (try? c.decodeIfPresent(String.self, forKey: .timeSeparator)) ?? d.timeSeparator
        hourCycle = (try? c.decodeIfPresent(HourCycle.self, forKey: .hourCycle)) ?? d.hourCycle
        timeFirst = (try? c.decodeIfPresent(Bool.self, forKey: .timeFirst)) ?? d.timeFirst
        pattern = (try? c.decodeIfPresent(String.self, forKey: .pattern)) ?? d.pattern
    }

    /// `DateFormatter` pattern for these options. `base` resolves the system hour cycle.
    public func dateFormat(base: Locale = .autoupdatingCurrent) -> String {
        let custom = pattern.trimmingCharacters(in: .whitespaces)
        if !custom.isEmpty { return custom }

        var datePart = ""
        if showsDate {
            let separator = Self.literal(dateSeparator)
            var parts: [String]
            switch dateOrder {
            case .dayMonthYear: parts = ["dd", "MM"]
            case .monthDayYear: parts = ["MM", "dd"]
            case .yearMonthDay: parts = ["MM", "dd"]
            }
            let yearToken: String? = switch year {
            case .none: nil
            case .twoDigits: "yy"
            case .fourDigits: "yyyy"
            }
            if let yearToken {
                if dateOrder == .yearMonthDay { parts.insert(yearToken, at: 0) } else { parts.append(yearToken) }
            }
            datePart = parts.joined(separator: separator)
            if showsWeekday { datePart = "EEE " + datePart }
        }

        var timePart = ""
        if time != .none {
            let separator = Self.literal(timeSeparator)
            let twelveHour = switch hourCycle {
            case .system: Self.systemUsesTwelveHours(base)
            case .twentyFourHour: false
            case .twelveHour: true
            }
            var parts = [twelveHour ? "h" : "HH", "mm"]
            if time == .hoursMinutesSeconds { parts.append("ss") }
            timePart = parts.joined(separator: separator) + (twelveHour ? " a" : "")
        }

        let pieces = (timeFirst ? [timePart, datePart] : [datePart, timePart]).filter { !$0.isEmpty }
        return pieces.isEmpty ? "HH:mm" : pieces.joined(separator: " ")
    }

    /// Example of the result, e.g. "DD.MM.YY HH:MM:SS", for pickers.
    public var placeholderText: String {
        dateFormat(base: Locale(identifier: "en_GB"))
            .replacingOccurrences(of: "yyyy", with: "YYYY")
            .replacingOccurrences(of: "yy", with: "YY")
            .replacingOccurrences(of: "dd", with: "DD")
            .replacingOccurrences(of: "mm", with: "MM")
            .replacingOccurrences(of: "ss", with: "SS")
    }

    static func systemUsesTwelveHours(_ locale: Locale) -> Bool {
        switch locale.hourCycle {
        case .oneToTwelve, .zeroToEleven: true
        default: false
        }
    }

    /// Letters in a pattern are field codes, so anything else than the offered
    /// separators is quoted.
    static func literal(_ separator: String) -> String {
        separator.contains(where: \.isLetter) ? "'" + separator.replacingOccurrences(of: "'", with: "''") + "'" : separator
    }
}
