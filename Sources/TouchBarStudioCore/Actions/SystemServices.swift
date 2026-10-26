import AppKit
import ApplicationServices
import Foundation

public struct ShellResult: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool
}

/// The side effects the action executor needs. Abstracted so the executor can be
/// unit-tested without launching apps or posting events.
@MainActor
public protocol SystemServices: AnyObject {
    func openApplication(bundleIdentifier: String) async throws
    /// Brings the app to the front, launching it if needed, and waits until it is active.
    func activateApplication(bundleIdentifier: String) async throws
    func open(url: URL) async throws
    func openFile(at url: URL) async throws
    func postKeyCombo(_ combo: KeyCombo) throws
    func postMediaKey(_ key: MediaKey) throws
    func copyToPasteboard(_ text: String)
    func runAppleScript(_ source: String) throws -> String?
    func runShell(_ command: String, timeout: TimeInterval) async throws -> ShellResult
    func isAccessibilityTrusted() -> Bool
    func isInstalled(bundleIdentifier: String) -> Bool
    /// nil when there is no input device.
    func microphoneState() -> MicrophoneState?
    func setMicrophoneMuted(_ muted: Bool) throws
    func sleep(milliseconds: Int) async
}

/// Real implementation backed by NSWorkspace, CGEvent, NSAppleScript and Process.
@MainActor
public final class LiveSystemServices: SystemServices {
    public init() {}

    public func isInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    public func openApplication(bundleIdentifier: String) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw ActionError.applicationNotFound(bundleIdentifier)
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        } catch {
            throw ActionError.couldNotOpen(url.lastPathComponent)
        }
    }

    public func activateApplication(bundleIdentifier: String) async throws {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            running.activate()
        } else {
            try await openApplication(bundleIdentifier: bundleIdentifier)
        }
        // Keystrokes go to whichever app is frontmost, so wait for the switch to finish.
        for _ in 0..<30 {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(80))
    }

    public func open(url: URL) async throws {
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            throw ActionError.couldNotOpen(L("“%@” (no app handles this URL)", url.absoluteString))
        }
        guard NSWorkspace.shared.open(url) else { throw ActionError.couldNotOpen(url.absoluteString) }
    }

    public func openFile(at url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ActionError.fileNotFound(url.path) }
        guard NSWorkspace.shared.open(url) else { throw ActionError.couldNotOpen(url.path) }
    }

    public func postKeyCombo(_ combo: KeyCombo) throws {
        guard isAccessibilityTrusted() else { throw ActionError.accessibilityPermissionRequired }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: false) else {
            throw ActionError.eventPostingFailed
        }
        var flags = CGEventFlags()
        if combo.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if combo.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if combo.modifiers.contains(.control) { flags.insert(.maskControl) }
        if combo.modifiers.contains(.shift) { flags.insert(.maskShift) }
        if combo.modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    public func postMediaKey(_ key: MediaKey) throws {
        switch key {
        case .brightnessUp where DisplayBrightness.isAvailable: try DisplayBrightness.step(up: true); return
        case .brightnessDown where DisplayBrightness.isAvailable: try DisplayBrightness.step(up: false); return
        default: break
        }
        guard isAccessibilityTrusted() else { throw ActionError.accessibilityPermissionRequired }
        // NX_SYSDEFINED event, subtype 8 (aux control button), as sent by the hardware keys.
        for (state, flags) in [(0xA, 0xA00), (0xB, 0xB00)] {
            let data1 = (Int(key.systemKeyType) << 16) | (state << 8)
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1
            )?.cgEvent else { throw ActionError.eventPostingFailed }
            event.post(tap: .cghidEventTap)
        }
    }

    public func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    public func runAppleScript(_ source: String) throws -> String? {
        guard let script = NSAppleScript(source: source) else {
            throw ActionError.scriptFailed(L("The script could not be created."))
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? L("Unknown error")
            let number = errorInfo[NSAppleScript.errorNumber] as? Int
            if number == -1743 {
                throw ActionError.scriptFailed(L("Not authorized to send Apple Events. Allow TouchBar Studio in System Settings › Privacy & Security › Automation."))
            }
            throw ActionError.scriptFailed(message)
        }
        return result.stringValue
    }

    public func runShell(_ command: String, timeout: TimeInterval) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try Self.runProcess(command: command, timeout: timeout) })
            }
        }
    }

    nonisolated private static func runProcess(command: String, timeout: TimeInterval) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        let buffers = OutputBuffers()
        let group = DispatchGroup()
        for (pipe, isOut) in [(out, true), (err, false)] {
            group.enter()
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                buffers.set(data, stdout: isOut)
                group.leave()
            }
        }
        do { try process.run() } catch {
            throw ActionError.shellFailed(exitCode: -1, stderr: error.localizedDescription)
        }
        let timer = DispatchWorkItem {
            if process.isRunning {
                buffers.markTimedOut()
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        process.waitUntilExit()
        timer.cancel()
        // Background children can keep the pipes open; don't wait on them forever.
        _ = group.wait(timeout: .now() + 1)
        let snapshot = buffers.snapshot()
        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: snapshot.out, as: UTF8.self),
            stderr: String(decoding: snapshot.err, as: UTF8.self),
            timedOut: snapshot.timedOut
        )
    }

    public func isAccessibilityTrusted() -> Bool { AXIsProcessTrusted() }

    public func microphoneState() -> MicrophoneState? { MicrophoneControl.currentState() }

    public func setMicrophoneMuted(_ muted: Bool) throws { try MicrophoneControl.setMuted(muted) }

    public func sleep(milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}

private final class OutputBuffers: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data(), err = Data(), timedOut = false

    func set(_ data: Data, stdout: Bool) {
        lock.withLock { if stdout { out = data } else { err = data } }
    }

    func markTimedOut() { lock.withLock { timedOut = true } }

    func snapshot() -> (out: Data, err: Data, timedOut: Bool) {
        lock.withLock { (out, err, timedOut) }
    }
}
