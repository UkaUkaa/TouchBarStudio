import Foundation
import Testing
@testable import TouchBarStudioCore

struct LocalizationTests {
    /// All `L("…")` and `Lp("…")` keys used in Sources/.
    static let usage: (keys: Set<String>, pluralKeys: Set<String>) = {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        var keys = Set<String>(), plurals = Set<String>()
        let literal = #""((?:[^"\\]|\\.)*)""#
        let single = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])L\("# + literal)
        let plural = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])Lp\("# + literal)
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try! String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for (regex, isPlural) in [(single, false), (plural, true)] {
                for match in regex.matches(in: text, range: range) {
                    let key = String(text[Range(match.range(at: 1), in: text)!])
                        .replacingOccurrences(of: #"\""#, with: "\"")
                        .replacingOccurrences(of: #"\\"#, with: "\\")
                    if isPlural { plurals.insert(key) } else { keys.insert(key) }
                }
            }
        }
        return (keys, plurals)
    }()

    static func placeholders(_ s: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"%(?:\d+\$)?[@dlu]+"#)
        return regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m in
            String(s[Range(m.range, in: s)!]).replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression)
        }
    }

    @Test func scannerFindsKeys() {
        #expect(Self.usage.keys.count > 300)
        #expect(Self.usage.keys.contains("Dashboard"))
        #expect(Self.usage.pluralKeys.contains("%d items"))
    }

    @Test func everyUsedKeyHasARussianTranslation() {
        let missing = Self.usage.keys.subtracting(RussianStrings.table.keys).sorted()
        #expect(missing.isEmpty, "Missing Russian translations: \(missing)")
        let missingPlurals = Self.usage.pluralKeys.subtracting(RussianStrings.plurals.keys).sorted()
        #expect(missingPlurals.isEmpty, "Missing Russian plurals: \(missingPlurals)")
    }

    @Test func everyUsedKeyHasAUkrainianTranslation() {
        let missing = Self.usage.keys.subtracting(UkrainianStrings.table.keys).sorted()
        #expect(missing.isEmpty, "Missing Ukrainian translations: \(missing)")
        let missingPlurals = Self.usage.pluralKeys.subtracting(UkrainianStrings.plurals.keys).sorted()
        #expect(missingPlurals.isEmpty, "Missing Ukrainian plurals: \(missingPlurals)")
    }

    @Test func noUnusedTranslations() {
        let unused = Set(RussianStrings.table.keys).subtracting(Self.usage.keys).sorted()
        #expect(unused.isEmpty, "Translations no longer used: \(unused)")
        let unusedUkrainian = Set(UkrainianStrings.table.keys).subtracting(Self.usage.keys).sorted()
        #expect(unusedUkrainian.isEmpty, "Ukrainian translations no longer used: \(unusedUkrainian)")
    }

    @Test func keysAreNotInterpolated() {
        let interpolated = Self.usage.keys.filter { $0.contains(#"\("#) }
        #expect(interpolated.isEmpty, "Use format placeholders instead of interpolation: \(interpolated)")
    }

    @Test func placeholdersMatch() {
        for table in [RussianStrings.table, UkrainianStrings.table] {
            for (key, value) in table {
                #expect(Self.placeholders(key) == Self.placeholders(value), "Placeholder mismatch for “\(key)”: \(value)")
            }
        }
        for plurals in [RussianStrings.plurals, UkrainianStrings.plurals] {
            for (key, forms) in plurals {
                for form in [forms.one, forms.few, forms.many] {
                    #expect(Self.placeholders(key) == Self.placeholders(form), "Plural placeholder mismatch for “\(key)”")
                }
            }
        }
    }

    @Test func translatesWithScopedOverride() {
        #expect(L("Dashboard") == "Dashboard")
        L10n.$override.withValue(.russian) {
            #expect(L("Dashboard") == "Обзор")
            #expect(L("Open %@", "Safari") == "Открыть Safari")
            #expect(ActionError.applicationNotFound("x.y").localizedDescription == "Не установлено приложение с идентификатором «x.y».")
        }
        #expect(L("Dashboard") == "Dashboard")
    }

    @Test func russianPluralRules() {
        L10n.$override.withValue(.russian) {
            let cases = [(1, "1 элемент"), (2, "2 элемента"), (4, "4 элемента"), (5, "5 элементов"),
                         (11, "11 элементов"), (12, "12 элементов"), (21, "21 элемент"), (22, "22 элемента"), (0, "0 элементов")]
            for (n, expected) in cases { #expect(Lp("%d items", n) == expected) }
        }
        L10n.$override.withValue(.ukrainian) {
            let cases = [(1, "1 елемент"), (3, "3 елементи"), (5, "5 елементів"), (11, "11 елементів"), (21, "21 елемент")]
            for (n, expected) in cases { #expect(Lp("%d items", n) == expected) }
        }
        #expect(Lp("%d items", 1) == "1 item")
        #expect(Lp("%d items", 3) == "3 items")
    }

    @Test func systemLanguageResolvesToConcreteLanguage() {
        #expect(AppLanguage.system.resolved != .system)
        #expect(AppLanguage.russian.resolved == .russian)
        #expect(AppLanguage.ukrainian.resolved == .ukrainian)
        #expect(AppLanguage.ukrainian.appleLanguageCode == "uk")
    }

    @Test func russianPresetsAreTranslatedAndFit() {
        L10n.$override.withValue(.russian) {
            let available = LayoutMetrics.availableWidth(showsControlStrip: true, showsCloseButton: true)
            for preset in BuiltInPresets.all {
                #expect(LayoutMetrics.estimatedWidth(of: preset.items) <= available,
                        "\(preset.name) is too wide in Russian: \(LayoutMetrics.estimatedWidth(of: preset.items))")
            }
            #expect(BuiltInPresets.productivity.name == "Продуктивность")
            #expect(AppConfiguration.makeDefault().defaultProfile.name == "По умолчанию")
        }
    }

    @Test func ukrainianPresetsAreTranslatedAndFit() {
        L10n.$override.withValue(.ukrainian) {
            let available = LayoutMetrics.availableWidth(showsControlStrip: true, showsCloseButton: true)
            for preset in BuiltInPresets.all {
                #expect(LayoutMetrics.estimatedWidth(of: preset.items) <= available,
                        "\(preset.name) is too wide in Ukrainian: \(LayoutMetrics.estimatedWidth(of: preset.items))")
            }
            #expect(L("Dashboard") != "Dashboard")
        }
    }

    @Test func languageSettingRoundTrips() throws {
        var settings = AppSettings()
        #expect(settings.language == .system)
        settings.language = .russian
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data).language == .russian)
        // Unknown values fall back to the default instead of failing the whole file.
        let json = #"{"language":"klingon"}"#
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)).language == .system)
    }
}
