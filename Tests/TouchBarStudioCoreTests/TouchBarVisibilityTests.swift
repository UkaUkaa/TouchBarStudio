import Foundation
import Testing
@testable import TouchBarStudioCore

struct TouchBarVisibilityTests {
    let chrome = "com.google.Chrome"

    func settings(hidden: [String] = []) -> AppSettings {
        var s = AppSettings()
        s.hiddenInApps = hidden
        return s
    }

    @Test func hiddenAppGetsItsOwnTouchBar() {
        let s = settings(hidden: [chrome])
        #expect(!TouchBarVisibility.shouldShow(frontmostBundleIdentifier: chrome, frontmostIsSelf: false, settings: s, providerShowsOverOtherApps: true))
        #expect(TouchBarVisibility.shouldShow(frontmostBundleIdentifier: "com.apple.Terminal", frontmostIsSelf: false, settings: s, providerShowsOverOtherApps: true))
    }

    @Test func alwaysShownInsideTouchBarStudio() {
        let s = settings(hidden: [chrome])
        #expect(TouchBarVisibility.shouldShow(frontmostBundleIdentifier: chrome, frontmostIsSelf: true, settings: s, providerShowsOverOtherApps: true))
    }

    @Test func standardModeIgnoresHiddenApps() {
        let s = settings(hidden: [chrome])
        #expect(TouchBarVisibility.shouldShow(frontmostBundleIdentifier: chrome, frontmostIsSelf: false, settings: s, providerShowsOverOtherApps: false))
    }

    @Test func hideAndUnhide() {
        var s = settings()
        #expect(TouchBarVisibility.hide(in: chrome, settings: &s))
        #expect(!TouchBarVisibility.hide(in: chrome, settings: &s))
        #expect(s.hiddenInApps == [chrome])
        #expect(!TouchBarVisibility.hide(in: "", settings: &s))
        #expect(TouchBarVisibility.unhide(in: chrome, settings: &s))
        #expect(!TouchBarVisibility.unhide(in: chrome, settings: &s))
        #expect(s.hiddenInApps.isEmpty)
    }

    @Test func hiddenAppsPersist() throws {
        let s = settings(hidden: [chrome])
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(decoded.hiddenInApps == [chrome])
        // Older files without the key load with an empty list.
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).hiddenInApps.isEmpty)
    }
}
