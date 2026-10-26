import Foundation

public enum ActionError: Error, LocalizedError, Equatable, Sendable {
    case noAction
    case invalidConfiguration(String)
    case applicationNotFound(String)
    case fileNotFound(String)
    case couldNotOpen(String)
    case accessibilityPermissionRequired
    case appleScriptDisabled
    case shellCommandsDisabled
    case notApproved(ActionKind)
    case scriptFailed(String)
    case shellFailed(exitCode: Int32, stderr: String)
    case timedOut(seconds: Int)
    case unknownAppCommand(String)
    case nestingTooDeep
    case eventPostingFailed
    case noInputDevice
    case microphoneNotControllable(String)
    case microphoneControlFailed(Int)
    case brightnessNotAvailable
    case noOutputDevice
    case volumeControlFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .noAction: L("This button has no action assigned.")
        case .invalidConfiguration(let why): L("Invalid action: %@", why)
        case .applicationNotFound(let id): L("No installed application with bundle ID “%@”.", id)
        case .fileNotFound(let path): L("File or folder not found: %@", path)
        case .couldNotOpen(let what): L("macOS could not open %@.", what)
        case .accessibilityPermissionRequired:
            L("Keyboard shortcuts and media keys need Accessibility permission. Open TouchBar Studio › Settings › Permissions.")
        case .appleScriptDisabled: L("AppleScript actions are turned off in Settings.")
        case .shellCommandsDisabled: L("Shell commands are turned off. Enable them in Settings › Security first.")
        case .notApproved(let kind):
            kind == .shellCommand
                ? L("This shell command has not been approved yet. Review and approve it in the editor.")
                : L("This AppleScript has not been approved yet. Review and approve it in the editor.")
        case .scriptFailed(let message): L("AppleScript error: %@", message)
        case .shellFailed(let code, let stderr):
            stderr.isEmpty ? L("Command exited with status %d.", Int(code)) : L("Command exited with status %d: %@", Int(code), stderr)
        case .timedOut(let s): L("Command did not finish within %d s and was stopped.", s)
        case .unknownAppCommand(let id): L("Unknown app command “%@”.", id)
        case .nestingTooDeep: L("Sequences can be nested at most %d levels deep.", ActionExecutor.maxNestingDepth)
        case .eventPostingFailed: L("Could not create the keyboard event.")
        case .noInputDevice: L("No microphone (audio input device) is available.")
        case .microphoneNotControllable(let name): L("“%@” does not let apps mute it or change its input volume.", name)
        case .microphoneControlFailed(let status): L("macOS refused to change the microphone (Core Audio error %d).", status)
        case .brightnessNotAvailable: L("The brightness of this display can't be changed by apps.")
        case .noOutputDevice: L("No sound output device is available.")
        case .volumeControlFailed(let status): L("macOS refused to change the volume (Core Audio error %d).", status)
        }
    }
}
