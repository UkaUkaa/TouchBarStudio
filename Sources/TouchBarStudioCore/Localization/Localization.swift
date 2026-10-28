import Foundation

/// Interface language chosen in Settings.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system
    case english
    case russian
    case ukrainian

    /// Concrete language after resolving `.system` against the user's preferred languages.
    public var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("ru") { return .russian }
        if preferred.hasPrefix("uk") { return .ukrainian }
        return .english
    }

    /// ISO 639 code of the resolved language.
    public var languageCode: String {
        switch resolved {
        case .russian: "ru"
        case .ukrainian: "uk"
        case .english, .system: "en"
        }
    }

    /// Locale for dates and numbers.
    public var locale: Locale {
        switch resolved {
        case .russian: Locale(identifier: "ru_RU")
        case .ukrainian: Locale(identifier: "uk_UA")
        case .english, .system: Locale(identifier: "en_US")
        }
    }

    /// Language code for `AppleLanguages` (system-provided menus and panels).
    public var appleLanguageCode: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .russian: "ru"
        case .ukrainian: "uk"
        }
    }

    /// Each language's name is written in that language so it can be recognised in any UI language.
    public var nativeName: String {
        switch self {
        case .system: L("System")
        case .english: "English"
        case .russian: "Русский"
        case .ukrainian: "Українська"
        }
    }
}

/// Runtime translation lookup.
///
/// Keys are the English texts. English needs no table; other languages are Swift
/// dictionaries compiled into the module (no resource bundles, so translations work the
/// same in the .app, under `swift run` and in Xcode). `LocalizationTests` scans the
/// sources and fails if a key used with `L(…)` has no translation.
public enum L10n {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _language: AppLanguage = .english

    /// Scoped override, mainly for tests: `L10n.$override.withValue(.russian) { … }`
    /// changes the language for that task only, without racing other tests.
    @TaskLocal public static var override: AppLanguage?

    /// Current resolved language. Defaults to English until the app applies the user's setting.
    public static var language: AppLanguage {
        get { override?.resolved ?? lock.withLock { _language } }
        set { lock.withLock { _language = newValue.resolved } }
    }

    public static func translate(_ key: String, language: AppLanguage) -> String {
        switch language.resolved {
        case .russian: RussianStrings.table[key] ?? key
        case .ukrainian: UkrainianStrings.table[key] ?? key
        case .english, .system: key
        }
    }

    /// Plural forms. English: one/other. Russian and Ukrainian: one/few/many (same rules).
    public static func plural(_ key: String, _ count: Int, language: AppLanguage) -> String {
        switch language.resolved {
        case .russian, .ukrainian:
            let table = language.resolved == .russian ? RussianStrings.plurals : UkrainianStrings.plurals
            guard let forms = table[key] else { return String(format: key, count) }
            let n10 = abs(count) % 10, n100 = abs(count) % 100
            let form: String
            if n10 == 1 && n100 != 11 { form = forms.one }
            else if (2...4).contains(n10) && !(12...14).contains(n100) { form = forms.few }
            else { form = forms.many }
            return String(format: form, count)
        case .english, .system:
            guard let one = EnglishPlurals.singular[key], count == 1 else { return String(format: key, count) }
            return String(format: one, count)
        }
    }
}

/// Translates `key` (its English text) into the current language.
public func L(_ key: String) -> String {
    L10n.translate(key, language: L10n.language)
}

/// Translates a format key and fills in `%@` / `%d` arguments.
public func L(_ key: String, _ arguments: any CVarArg...) -> String {
    String(format: L10n.translate(key, language: L10n.language), locale: L10n.language.locale, arguments: arguments)
}

/// Count-dependent text, e.g. `Lp("%d items", 3)` → "3 items" / "3 элемента".
public func Lp(_ key: String, _ count: Int) -> String {
    L10n.plural(key, count, language: L10n.language)
}

/// Singular forms for English plural keys (the key itself is the plural form).
enum EnglishPlurals {
    static let singular: [String: String] = [
        "%d items": "%d item",
        "%d actions": "%d action",
        "%d steps": "%d step",
    ]
}
