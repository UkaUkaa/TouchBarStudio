import Foundation
import Testing
@testable import TouchBarStudioCore

@MainActor
final class MockServices: SystemServices {
    var calls: [String] = []
    var trusted = true
    var installed: Set<String> = ["com.apple.calculator", "com.apple.finder", "com.apple.Safari"]
    var shellResult = ShellResult(exitCode: 0, stdout: "ok\n", stderr: "", timedOut: false)
    var pasteboard: String?
    var microphone: MicrophoneState? = MicrophoneState(deviceName: "Mock Mic", isMuted: false)

    func openApplication(bundleIdentifier: String) async throws {
        guard installed.contains(bundleIdentifier) else { throw ActionError.applicationNotFound(bundleIdentifier) }
        calls.append("open-app:\(bundleIdentifier)")
    }
    func activateApplication(bundleIdentifier: String) async throws {
        guard installed.contains(bundleIdentifier) else { throw ActionError.applicationNotFound(bundleIdentifier) }
        calls.append("activate:\(bundleIdentifier)")
    }
    func open(url: URL) async throws { calls.append("open-url:\(url.absoluteString)") }
    func openFile(at url: URL) async throws { calls.append("open-file:\(url.path)") }
    func postKeyCombo(_ combo: KeyCombo) throws {
        guard trusted else { throw ActionError.accessibilityPermissionRequired }
        calls.append("keys:\(combo.displayString)")
    }
    func postMediaKey(_ key: MediaKey) throws { calls.append("media:\(key.rawValue)") }
    func copyToPasteboard(_ text: String) { pasteboard = text; calls.append("copy") }
    func runAppleScript(_ source: String) throws -> String? { calls.append("applescript"); return nil }
    func runShell(_ command: String, timeout: TimeInterval) async throws -> ShellResult {
        calls.append("shell:\(command)")
        return shellResult
    }
    func isAccessibilityTrusted() -> Bool { trusted }
    func isInstalled(bundleIdentifier: String) -> Bool { installed.contains(bundleIdentifier) }
    func sleep(milliseconds: Int) async { calls.append("sleep:\(milliseconds)") }
    func microphoneState() -> MicrophoneState? { microphone }
    func setMicrophoneMuted(_ muted: Bool) throws {
        guard microphone != nil else { throw ActionError.noInputDevice }
        microphone?.isMuted = muted
        calls.append("mic:\(muted)")
    }
}

@MainActor
struct ActionExecutorTests {
    let services = MockServices()
    let trust = ScriptTrustStore(fileURL: nil)
    var executor: ActionExecutor { ActionExecutor(services: services, trust: trust) }
    let ctx = ExecutionContext(source: "test")

    @Test func opensApplication() async throws {
        let result = await executor.run(.openApp("com.apple.calculator"), context: ctx)
        #expect(result.succeeded)
        #expect(services.calls == ["open-app:com.apple.calculator"])
    }

    @Test func missingApplicationFails() async {
        let result = await executor.run(.openApp("com.example.missing"), context: ctx)
        #expect(throws: ActionError.applicationNotFound("com.example.missing")) { try result.get() }
    }

    @Test func rejectsInvalidURLs() async {
        for bad in ["", "not a url", "javascript:alert(1)", "https://"] {
            let result = await executor.run(.openURL(bad), context: ctx)
            #expect(throws: ActionError.self) { try result.get() }
        }
        #expect(services.calls.isEmpty)
    }

    @Test func expandsTildeInFilePaths() async throws {
        _ = try await executor.run(.openFile("~/Downloads"), context: ctx).get()
        #expect(services.calls == ["open-file:\(NSHomeDirectory())/Downloads"])
    }

    @Test func shortcutActivatesAssociatedAppFirst() async throws {
        let context = ExecutionContext(associatedBundleIdentifier: "com.apple.Safari", source: "test")
        _ = try await executor.run(.shortcut(KeyCombo("T", .command)), context: context).get()
        #expect(services.calls == ["activate:com.apple.Safari", "keys:⌘T"])
    }

    @Test func shortcutWithoutAccessibilityFailsWithoutPosting() async {
        services.trusted = false
        let result = await executor.run(.shortcut(KeyCombo("T", .command), in: "com.apple.Safari"), context: ctx)
        #expect(throws: ActionError.accessibilityPermissionRequired) { try result.get() }
        #expect(services.calls.isEmpty)
    }

    @Test func copiesText() async throws {
        _ = try await executor.run(.copy("—"), context: ctx).get()
        #expect(services.pasteboard == "—")
    }

    @Test func shellIsDisabledByDefault() async {
        let action = ActionConfig.shell("echo hi")
        trust.approve(action)
        let result = await executor.run(action, context: ctx)
        #expect(throws: ActionError.shellCommandsDisabled) { try result.get() }
        #expect(services.calls.isEmpty)
    }

    @Test func shellRequiresApproval() async throws {
        let ex = executor
        ex.policy.allowShellCommands = true
        let action = ActionConfig.shell("echo hi")
        let denied = await ex.run(action, context: ctx)
        #expect(throws: ActionError.notApproved(.shellCommand)) { try denied.get() }
        #expect(services.calls.isEmpty)

        trust.approve(action)
        let output = try await ex.run(action, context: ctx).get()
        #expect(output == "ok")
        // Editing the command invalidates the approval.
        let edited = await ex.run(.shell("echo hi; rm -rf ~"), context: ctx)
        #expect(throws: ActionError.notApproved(.shellCommand)) { try edited.get() }
    }

    @Test func shellNonZeroExitIsReported() async {
        let ex = executor
        ex.policy.allowShellCommands = true
        services.shellResult = ShellResult(exitCode: 2, stdout: "", stderr: "boom\n", timedOut: false)
        let action = ActionConfig.shell("false")
        trust.approve(action)
        let result = await ex.run(action, context: ctx)
        #expect(throws: ActionError.shellFailed(exitCode: 2, stderr: "boom")) { try result.get() }
    }

    @Test func appleScriptRequiresApproval() async throws {
        let action = ActionConfig.appleScript("beep")
        await #expect(throws: ActionError.notApproved(.appleScript)) { try await executor.run(action, context: ctx).get() }
        trust.approve(action)
        _ = try await executor.run(action, context: ctx).get()
        #expect(services.calls == ["applescript"])
    }

    @Test func builtInAppCommandScriptsDoNotNeedApproval() async throws {
        _ = try await executor.run(.command("music.playPause"), context: ctx).get()
        #expect(services.calls == ["applescript"])
    }

    @Test func appCommandExpandsToTargetedShortcut() async throws {
        _ = try await executor.run(.command("safari.newTab"), context: ctx).get()
        #expect(services.calls == ["activate:com.apple.Safari", "keys:⌘T"])
    }

    @Test func unknownAppCommandFails() async {
        let result = await executor.run(.command("nope"), context: ctx)
        #expect(throws: ActionError.unknownAppCommand("nope")) { try result.get() }
    }

    @Test func sequenceRunsInOrderWithDelay() async throws {
        let seq = ActionConfig.sequence([.openApp("com.apple.finder"), .copy("x"), .media(.playPause)], delayMilliseconds: 100)
        _ = try await executor.run(seq, context: ctx).get()
        #expect(services.calls == ["open-app:com.apple.finder", "sleep:100", "copy", "sleep:100", "media:playPause"])
    }

    @Test func sequenceStopsAtFirstFailure() async {
        let seq = ActionConfig.sequence([.openApp("com.example.missing"), .copy("x")], delayMilliseconds: 0)
        let result = await executor.run(seq, context: ctx)
        #expect(throws: ActionError.applicationNotFound("com.example.missing")) { try result.get() }
        #expect(services.pasteboard == nil)
    }

    @Test func deeplyNestedSequenceIsRejected() async {
        var action = ActionConfig.copy("x")
        for _ in 0...ActionExecutor.maxNestingDepth + 1 { action = .sequence([action]) }
        let result = await executor.run(action, context: ctx)
        #expect(throws: ActionError.nestingTooDeep) { try result.get() }
    }

    @Test func activityLogRecordsOutcomes() async {
        let ex = executor
        await ex.run(.copy("a"), context: ctx)
        await ex.run(.none, context: ctx)
        #expect(ex.activity.count == 2)
        #expect(ex.activity[0].succeeded == false)
        #expect(ex.activity[1].succeeded == true)
    }

    @Test func preflightReportsProblems() {
        services.trusted = false
        let ex = executor
        let problems = ex.preflight(.sequence([.openApp("com.example.missing"), .shortcut(KeyCombo("A", .command)), .shell("ls")]), context: ctx)
        #expect(problems.contains(.applicationNotFound("com.example.missing")))
        #expect(problems.contains(.accessibilityPermissionRequired))
        #expect(problems.contains(.shellCommandsDisabled))
        #expect(problems.contains(.notApproved(.shellCommand)))
    }

    @Test func everyRegistryKindHasATemplateThatValidates() throws {
        let ex = executor
        for descriptor in ActionRegistry.descriptors {
            try ex.validate(ActionRegistry.template(for: descriptor.kind))
        }
    }
}

/// Exercises the real `/bin/zsh` runner (no UI, no permissions needed).
@MainActor
struct LiveShellTests {
    @Test func runsRealShellCommand() async throws {
        let result = try await LiveSystemServices().runShell("echo hello; echo err >&2", timeout: 10)
        #expect(result.exitCode == 0)
        #expect(result.stdout == "hello\n")
        #expect(result.stderr == "err\n")
    }

    @Test func enforcesTimeout() async throws {
        let start = Date()
        let result = try await LiveSystemServices().runShell("sleep 5", timeout: 1)
        #expect(result.timedOut)
        #expect(Date().timeIntervalSince(start) < 4)
    }
}

@MainActor
struct MicrophoneActionTests {
    let services = MockServices()
    var executor: ActionExecutor { ActionExecutor(services: services, trust: ScriptTrustStore(fileURL: nil)) }
    let ctx = ExecutionContext(source: "test")

    @Test func toggleFlipsState() async throws {
        services.microphone = MicrophoneState(deviceName: "Mic", isMuted: false)
        #expect(try await executor.run(.microphone(.toggle), context: ctx).get() == "Microphone muted")
        #expect(services.microphone?.isMuted == true)
        #expect(try await executor.run(.microphone(.toggle), context: ctx).get() == "Microphone on")
        #expect(services.microphone?.isMuted == false)
    }

    @Test func explicitMuteAndUnmuteAreIdempotent() async throws {
        services.microphone = MicrophoneState(deviceName: "Mic", isMuted: true)
        _ = try await executor.run(.microphone(.mute), context: ctx).get()
        #expect(services.microphone?.isMuted == true)
        _ = try await executor.run(.microphone(.unmute), context: ctx).get()
        _ = try await executor.run(.microphone(.unmute), context: ctx).get()
        #expect(services.microphone?.isMuted == false)
    }

    @Test func noInputDeviceIsAnError() async {
        services.microphone = nil
        let result = await executor.run(.microphone(.toggle), context: ctx)
        #expect(throws: ActionError.noInputDevice) { try result.get() }
        #expect(executor.preflight(.microphone(.toggle), context: ctx).contains(.noInputDevice))
    }

    @Test func missingOperationIsInvalid() async {
        let result = await executor.run(ActionConfig(kind: .microphone), context: ctx)
        #expect(throws: ActionError.self) { try result.get() }
    }

    @Test func microphoneWidgetRoundTripsInPresets() throws {
        let preset = Preset(name: "Mic", items: [.microphone()])
        let imported = try PresetCodec.importPreset(from: PresetCodec.export(preset))
        #expect(imported.preset.items[0].kind == .microphone)
        #expect(imported.preset.items[0].action == .microphone(.toggle))
        #expect(imported.preset.items[0].isTappable)
    }

    @Test func readsThisMacsMicrophoneWithoutChangingIt() {
        // Read-only: must never mute the real microphone during tests.
        if let state = MicrophoneControl.currentState() { #expect(!state.deviceName.isEmpty) }
    }
}
