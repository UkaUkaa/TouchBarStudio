import Foundation
import Testing
@testable import TouchBarStudioCore

struct TouchBarVisibilityTests {
    let chrome = "com.google.Chrome"
    let terminal = "com.apple.Terminal"

    @Test func closedAppShowsItsOwnTouchBarWhileInFront() {
        #expect(!TouchBarVisibility.shouldShow(frontmostBundleIdentifier: chrome, frontmostIsSelf: false, closedInApp: chrome, providerShowsOverOtherApps: true))
        #expect(TouchBarVisibility.shouldShow(frontmostBundleIdentifier: terminal, frontmostIsSelf: false, closedInApp: chrome, providerShowsOverOtherApps: true))
        #expect(TouchBarVisibility.shouldShow(frontmostBundleIdentifier: chrome, frontmostIsSelf: false, closedInApp: nil, providerShowsOverOtherApps: true))
    }

    @Test func closeIsForgottenWhenAnotherAppComesForward() {
        // ✕ in Chrome, Chrome reactivated (e.g. another window): still closed.
        #expect(TouchBarVisibility.closedApp(after: chrome, closedInApp: chrome) == chrome)
        // Switch to Terminal: forgotten, so returning to Chrome shows the layout again.
        let afterTerminal = TouchBarVisibility.closedApp(after: terminal, closedInApp: chrome)
        #expect(afterTerminal == nil)
        #expect(TouchBarVisibility.shouldShow(frontmostBundleIdentifier: chrome, frontmostIsSelf: false, closedInApp: afterTerminal, providerShowsOverOtherApps: true))
        // TouchBar Studio itself counts as another app.
        #expect(TouchBarVisibility.closedApp(after: "dev.touchbarstudio.TouchBarStudio", closedInApp: chrome) == nil)
    }

    @Test func alwaysShownInsideTouchBarStudioAndInStandardMode() {
        #expect(TouchBarVisibility.shouldShow(frontmostBundleIdentifier: chrome, frontmostIsSelf: true, closedInApp: chrome, providerShowsOverOtherApps: true))
        #expect(TouchBarVisibility.shouldShow(frontmostBundleIdentifier: chrome, frontmostIsSelf: false, closedInApp: chrome, providerShowsOverOtherApps: false))
    }

    @Test func listedAppsAlwaysKeepTheirOwnTouchBar() {
        let own = [chrome]
        #expect(!TouchBarVisibility.shouldShow(frontmostBundleIdentifier: chrome, frontmostIsSelf: false, closedInApp: nil, ownTouchBarApps: own, providerShowsOverOtherApps: true))
        #expect(TouchBarVisibility.shouldShow(frontmostBundleIdentifier: terminal, frontmostIsSelf: false, closedInApp: nil, ownTouchBarApps: own, providerShowsOverOtherApps: true))
        // Still shown inside TouchBar Studio, and the list has no effect in standard mode.
        #expect(TouchBarVisibility.shouldShow(frontmostBundleIdentifier: chrome, frontmostIsSelf: true, closedInApp: nil, ownTouchBarApps: own, providerShowsOverOtherApps: true))
        #expect(TouchBarVisibility.shouldShow(frontmostBundleIdentifier: chrome, frontmostIsSelf: false, closedInApp: nil, ownTouchBarApps: own, providerShowsOverOtherApps: false))
    }

    @Test func ownTouchBarAppsRoundTrip() throws {
        var settings = AppSettings()
        #expect(settings.ownTouchBarApps.isEmpty)
        settings.ownTouchBarApps = [chrome, terminal]
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.ownTouchBarApps == [chrome, terminal])
    }

    @Test func oldHiddenAppsKeyIsIgnored() throws {
        // Configs saved by the previous version may contain "hiddenInApps"; it no longer has any effect.
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"hiddenInApps":["com.google.Chrome"]}"#.utf8))
        #expect(settings == AppSettings())
    }
}
