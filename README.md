# TouchBar Studio

A native macOS app for customizing the physical Touch Bar of a MacBook Pro: build your
own buttons, assign real actions, organize them into per-app profiles, and share layouts
as versioned JSON presets.

Swift 6 · AppKit (`NSTouchBar`) for the Touch Bar · SwiftUI for the interface · no
third-party dependencies.

## How it reaches the Touch Bar

macOS gives a normal app control of the Touch Bar **only while that app is active**.
There is no public API for changing other apps' Touch Bars. TouchBar Studio therefore
has two interchangeable integrations behind the `TouchBarProvider` protocol:

| Mode | API | When your layout is visible | Per-app profiles |
|---|---|---|---|
| **Standard** (default) | Public `NSTouchBar`, attached to `NSApplication` | While TouchBar Studio is the active app | Detected, but can't be applied (the bar isn't shown in other apps) |
| **Over all apps (experimental)**, opt-in | Undocumented `+[NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:]`, the API used by Pock and MTMR | Over every app | Applied automatically when the frontmost app changes |

The experimental mode is off by default and asks for confirmation before it turns on.

**Closing the layout in one app (✕).** In experimental mode, tapping the system ✕ button
while an app is in front hides the layout *in that app only*: its own Touch Bar stays
there, also after switching away and back, and the layout keeps appearing in every other
app. The list is saved (`settings.hiddenInApps`) and can be undone in Settings › Hidden in
Apps, on the Dashboard, via the menu bar item "Show Layout in <App>", or with Touch Bar ›
Show Layout on Touch Bar while that app is in front. The close is detected through KVO on
`NSTouchBar.visible`; on the test Mac holding fn did not change it, and events while the
display sleeps, the screen is locked or the login window is in front are ignored.
It is resolved at runtime with `class_getClassMethod`: if a future macOS release removes
the selector, the option is disabled instead of crashing. With "Keep the system Control
Strip" on (the default), macOS adds a close (✕) button and keeps brightness/volume.

## Verified on real hardware

Test machine: MacBookPro17,1 (13" M1, 2020), macOS 27.0.1 (26A434), Swift 6.4 /
Command Line Tools. Touch Bar contents were captured from the hardware with
`screencapture -b`.

| Check | Result |
|---|---|
| Minimal proof app: custom button with icon and label appears on the physical Touch Bar | ✅ captured |
| Physical finger tap triggers the action (opened Calculator) | ✅ confirmed by the user and by Calculator's process start time |
| TouchBar Studio, standard mode: profile appears while the app is active | ✅ captured |
| Standard mode after the window is closed: reactivating the app reopens the window and the layout (without a key window macOS shows an empty bar) | ✅ captured |
| Experimental mode: layout shown while Finder / Safari / Terminal are frontmost | ✅ captured |
| Experimental mode: automatic switching (Finder → Finder profile, Safari → Safari profile, Terminal → default) | ✅ captured |
| Normal Touch Bar comes back when the app quits | ✅ captured |
| Full app, standard mode: physical tap on the Calculator button opens Calculator and is logged | ✅ confirmed by the user |
| Full app, experimental mode: in Finder, tapping "Downloads" opens the folder | ✅ confirmed by the user |
| Editor: drag-and-drop reorder, title edit, ⌘Z | ✅ confirmed by the user |
| Layout and mode persist after restarting the app (config unchanged, layout shown over Terminal) | ✅ captured |
| Battery widget shows the charging icon and the real percentage (98%) on the Touch Bar | ✅ captured |
| Microphone widget toggle (performed in-app exactly as a tap): Core Audio mute read back as 1 by a separate process, widget turns red; second toggle unmutes | ✅ captured + verified |
| Microphone widget follows a mute set by another process | ✅ captured |
| Physical finger tap on the microphone widget | Not separately tested (tap delivery itself is verified for buttons) |
| ✕ in Chrome keeps Chrome's own Touch Bar; layout returns in Terminal and Finder; back in Chrome (twice) Chrome's bar stays | ✅ user tapped ✕, rest captured |
| Holding fn does not count as closing (bar visibility unchanged, layout returns on release) | ✅ user test + trace |
| Keyboard-shortcut and media-key actions with Accessibility granted to the bundled app | ⚠️ Not verified on hardware (permission not granted during testing). Covered by unit tests with mocked services only. |
| AppleScript and shell actions from a Touch Bar tap | ⚠️ Shell runner verified by unit tests against real `/bin/zsh`; not tapped on hardware |

## Features

- **Custom buttons**: title (shown or hidden), SF Symbol / app icon / image file, color,
  action, optional global hotkey (Carbon `RegisterEventHotKey`, no permission needed),
  optional associated app. Add, edit, duplicate, delete and reorder.
- **Actions** (`ActionRegistry` + `ActionExecutor`, all with real handlers):
  open app · open URL · open file/folder · keyboard shortcut (optionally sent to a
  specific app, which is brought to the front first) · copy text · AppleScript · shell
  command · built-in app commands (Finder, Safari, Terminal, Xcode, Music, system) ·
  media keys · sequences (stop at the first failure). Failures are reported in the
  activity log and the Touch Bar button flashes red.
- **Application profiles**: create, rename, duplicate, delete, set default, associate apps,
  toggle automatic switching. Frontmost-app detection uses
  `NSWorkspace.didActivateApplicationNotification`.
- **Layout editor**: a preview labelled "PREVIEW — not the physical Touch Bar" with a width
  estimate and overflow warning, a component library, a properties panel, drag and drop
  (library → bar, reordering within the bar and the list), undo/redo (⌘Z / ⇧⌘Z), revert,
  save and Save as Preset.
- **Presets**: Developer, Browser, Writer, Productivity, Creative Work (plus Finder).
  Custom presets can be imported and exported as versioned JSON.
- **Battery widget**: live battery icon and percentage on the Touch Bar (IOKit power-source
  API, no permission needed). Updates on every power-source change, turns orange at 20% and
  red at 10% on battery power; tapping opens Battery settings (configurable or none).
- **Microphone widget and action**: mute/unmute the microphone for every app by setting
  the Core Audio mute property of the default input device (no permission needed; devices
  without a settable mute fall back to input volume 0 and back). The widget turns red while
  muted, follows changes made elsewhere and switches with the default input device. The
  "Microphone" action (toggle / mute / unmute) can also go on any button, a global hotkey or
  a sequence.
- **Dashboard, Actions, Application Profiles, Presets, Settings** sections; menu bar extra;
  native menus (Layout, Touch Bar, ⌘1–⌘6 navigation); light and dark mode.

## Interface language

English and Russian, switchable in **Settings › Language** (System / English / Русский)
without restarting. "System" follows the first preferred language in macOS. Standard
menus and panels supplied by macOS (Edit, Window, open/save dialogs) follow
`AppleLanguages` and switch after a restart; Settings offers a **Restart Now** button.

Translations are Swift dictionaries in `Sources/TouchBarStudioCore/Localization/`, keyed
by the English text and accessed with `L("…")` / `Lp("%d items", n)` (Russian plural
rules). There are no resource bundles, so the app behaves the same as a `.app`, under
`swift run` and in Xcode. `LocalizationTests` scans the sources and fails on a missing,
unused or placeholder-mismatched translation, and checks that the built-in presets fit
in Russian too. Built-in preset names and button titles are localized when a profile is
created from them; buttons you've already created keep the titles you gave them.

## Security and permissions

- **Accessibility** is only needed for keyboard-shortcut and media-key actions. It is never
  requested at launch: Settings explains why, then the user clicks **Grant Access…**.
  Without it, every other action still works and those actions report a clear error.
- **Automation** prompts come from macOS, once per target app, the first time an AppleScript
  touches that app.
- **Shell commands** are disabled until enabled in Settings (with a warning). They run
  via `/bin/zsh -lc` with a timeout (default 30 s).
- **Script approval**: every AppleScript and shell command must be approved before its
  first run. Approval is keyed to a SHA-256 of the exact text and stored in
  `approved-scripts.json`, which is never exported. Editing a script revokes its
  approval. Imported presets never carry approvals, and the import sheet shows every
  script verbatim.
- **Import validation**: 512 KB size limit; `format` and `formatVersion` are checked;
  structure is decoded strictly; limits on item count, title and script length, and
  sequence depth/steps; `javascript:` URLs and unknown app commands are rejected.
  Imported items get new IDs.
- A configuration file that can't be read is moved aside (`config.unreadable-<date>.json`)
  instead of being overwritten.

## Requirements

- macOS 14 Sonoma or later (developed and tested on macOS 27.0.1).
- A MacBook Pro with a Touch Bar to see results. On other Macs the app runs, but has
  no Touch Bar to drive.
- Swift 6 toolchain: the Xcode Command Line Tools are enough; full Xcode is optional.

## Build, test, install

```sh
scripts/build-app.sh            # release build → build/TouchBar Studio.app
scripts/build-app.sh debug      # debug build
scripts/test.sh                 # unit tests (Swift Testing, 72 tests)
open "build/TouchBar Studio.app"
cp -R "build/TouchBar Studio.app" /Applications/   # optional install
```

**Xcode:** open `Package.swift` (File › Open…) and run the `TouchBarStudio` scheme. No
`.xcodeproj` is included: this machine has only the Command Line Tools, so a generated
project file couldn't be built or verified. SwiftPM packages open natively in Xcode.
Note that running from Xcode or `swift run` launches a bare executable rather than the
`.app` bundle; Accessibility/Automation grants belong to the bundle, so test those with
`scripts/build-app.sh` and `open`.

Builds are **ad-hoc signed**. macOS ties Accessibility approval to the code signature,
so after rebuilding you may have to turn the permission off and on again for
TouchBar Studio. To sign with your own identity:
`SIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh`.

Configuration lives in `~/Library/Application Support/TouchBarStudio/`.

## Architecture

```
Sources/TouchBarStudioCore/   UI-independent, unit-tested
  Models/        ActionConfig, KeyCombo, TouchBarItemConfig, Profile, AppConfiguration, LayoutMetrics
  Actions/       ActionRegistry, ActionExecutor, SystemServices (protocol + live impl), ScriptTrustStore, AppCommandCatalog
  Storage/       ConfigurationStore (atomic JSON, corrupt-file backup, schema version)
  Presets/       Preset, PresetCodec (import/export/validation), BuiltInPresets
  Profiles/      ProfileResolver (which profile should be shown)
Sources/TouchBarStudio/       AppKit + SwiftUI app
  TouchBar/      TouchBarProvider (Application / SystemModal), TouchBarManager (NSTouchBar builder + tap routing)
  System/        ApplicationProfileManager (frontmost app), PermissionManager, HotKeyCenter, IconProvider
  Editor/        LayoutEditorViewModel (selection, mutations, undo/redo, component library)
  App/           AppModel (wiring + persistence), app/menus/menu bar extra
  Views/         Dashboard, Editor, Actions, Profiles, Presets, Settings, shared components
Tests/TouchBarStudioCoreTests/
```

Toolchain notes (Command Line Tools only):
- In the macOS 27 SDK, SwiftUI's `@State` is a macro whose plugin ships only with Xcode.
  The views use `@ViewState` (`Views/ViewState.swift`), a thin wrapper around the public
  `State<Value>` struct that compiles with either toolchain.
- `scripts/test.sh` passes the Swift Testing macro plugin path explicitly. Without it,
  SwiftBuild sometimes loses the plugin on incremental builds.

## Limitations

- Standard mode can't show your layout in other apps. That's a macOS restriction, not
  something this app can work around with public API.
- If TouchBar Studio quits while in experimental mode and is reopened in standard mode
  within a few seconds, macOS showed an empty Touch Bar for that whole session on the test
  Mac (reproduced 2/2; the next launch is fine). Switching modes inside a running app is
  not affected.
- Experimental mode depends on an undocumented API and may break in any macOS update.
- In standard mode, a keyboard-shortcut button without a target app sends its keys to
  TouchBar Studio itself (the editor warns about this).
- Item widths in the preview are estimates calibrated against hardware captures of a 13"
  Touch Bar (icon-only button 72 pt, close button 60 pt, collapsed Control Strip 306 pt);
  macOS hides items that don't fit. A unit test checks that every built-in preset fits in
  the tightest layout (experimental mode with the Control Strip and close button).
- The brightness and keyboard-backlight media keys aren't offered: they can't be posted
  reliably on Apple-silicon Macs.
- App commands for apps that aren't installed (e.g. Xcode on the test machine) report
  "No installed application…" instead of pretending to succeed.
