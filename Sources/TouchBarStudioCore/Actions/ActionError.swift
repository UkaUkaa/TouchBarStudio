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

    public var errorDescription: String? {
        switch self {
        case .noAction: "This button has no action assigned."
        case .invalidConfiguration(let why): "Invalid action: \(why)"
        case .applicationNotFound(let id): "No installed application with bundle ID “\(id)”."
        case .fileNotFound(let path): "File or folder not found: \(path)"
        case .couldNotOpen(let what): "macOS could not open \(what)."
        case .accessibilityPermissionRequired:
            "Keyboard shortcuts and media keys need Accessibility permission. Open TouchBar Studio › Settings › Permissions."
        case .appleScriptDisabled: "AppleScript actions are turned off in Settings."
        case .shellCommandsDisabled: "Shell commands are turned off. Enable them in Settings › Security first."
        case .notApproved(let kind):
            "This \(kind == .shellCommand ? "shell command" : "AppleScript") has not been approved yet. Review and approve it in the editor."
        case .scriptFailed(let message): "AppleScript error: \(message)"
        case .shellFailed(let code, let stderr):
            stderr.isEmpty ? "Command exited with status \(code)." : "Command exited with status \(code): \(stderr)"
        case .timedOut(let s): "Command did not finish within \(s) s and was stopped."
        case .unknownAppCommand(let id): "Unknown app command “\(id)”."
        case .nestingTooDeep: "Sequences can be nested at most \(ActionExecutor.maxNestingDepth) levels deep."
        case .eventPostingFailed: "Could not create the keyboard event."
        }
    }
}
