import Foundation

public struct ExecutionPolicy: Sendable {
    public var allowShellCommands: Bool
    public var allowAppleScript: Bool
    public var shellTimeoutSeconds: Int

    public init(allowShellCommands: Bool = false, allowAppleScript: Bool = true, shellTimeoutSeconds: Int = 30) {
        self.allowShellCommands = allowShellCommands
        self.allowAppleScript = allowAppleScript
        self.shellTimeoutSeconds = shellTimeoutSeconds
    }

    public init(settings: AppSettings) {
        self.init(allowShellCommands: settings.allowShellCommands,
                  allowAppleScript: settings.allowAppleScript,
                  shellTimeoutSeconds: settings.shellTimeoutSeconds)
    }
}

public struct ExecutionContext: Sendable {
    /// The button's associated app; default target for keyboard shortcuts.
    public var associatedBundleIdentifier: String?
    /// Human-readable origin for the activity log ("Touch Bar: Build").
    public var source: String

    public init(associatedBundleIdentifier: String? = nil, source: String) {
        self.associatedBundleIdentifier = associatedBundleIdentifier
        self.source = source
    }
}

public struct ActivityEntry: Identifiable, Sendable, Hashable {
    public var id = UUID()
    public var date: Date
    public var source: String
    public var summary: String
    public var succeeded: Bool
    public var message: String?
}

extension Result where Failure == ActionError {
    /// `try? get() != nil` is wrong for `.success(nil)`, so check the case instead.
    public var succeeded: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Runs `ActionConfig`s against real system services.
@MainActor
public final class ActionExecutor {
    nonisolated public static let maxNestingDepth = 4
    nonisolated public static let maxActivityEntries = 200

    private let services: SystemServices
    private let trust: ScriptTrustStore
    private let catalog: AppCommandCatalog
    public var policy: ExecutionPolicy
    public private(set) var activity: [ActivityEntry] = []
    /// Called after every top-level run (for UI refresh / feedback).
    public var onActivity: ((ActivityEntry) -> Void)?

    public init(services: SystemServices, trust: ScriptTrustStore, policy: ExecutionPolicy = ExecutionPolicy(),
                catalog: AppCommandCatalog = .standard) {
        self.services = services
        self.trust = trust
        self.policy = policy
        self.catalog = catalog
    }

    /// Runs an action and records the outcome. Returns the error, if any.
    @discardableResult
    public func run(_ action: ActionConfig, context: ExecutionContext) async -> Result<String?, ActionError> {
        let result: Result<String?, ActionError>
        do {
            result = .success(try await execute(action, context: context, depth: 0))
        } catch let error as ActionError {
            result = .failure(error)
        } catch {
            result = .failure(.scriptFailed(error.localizedDescription))
        }
        let entry = ActivityEntry(
            date: Date(), source: context.source, summary: action.summary,
            succeeded: result.succeeded,
            message: { switch result {
                case .success(let m): m
                case .failure(let e): e.localizedDescription
            } }()
        )
        activity.insert(entry, at: 0)
        if activity.count > Self.maxActivityEntries { activity.removeLast(activity.count - Self.maxActivityEntries) }
        onActivity?(entry)
        return result
    }

    /// Checks an action for problems that would make it fail, without running it.
    public func preflight(_ action: ActionConfig, context: ExecutionContext) -> [ActionError] {
        var problems: [ActionError] = []
        collectProblems(action, context: context, depth: 0, into: &problems)
        return problems
    }

    private func collectProblems(_ action: ActionConfig, context: ExecutionContext, depth: Int, into problems: inout [ActionError]) {
        if depth > Self.maxNestingDepth { problems.append(.nestingTooDeep); return }
        do { try validate(action) } catch let e as ActionError { problems.append(e); return } catch {}
        switch action.kind {
        case .openApplication:
            if let id = action.bundleIdentifier, !services.isInstalled(bundleIdentifier: id) { problems.append(.applicationNotFound(id)) }
        case .keyboardShortcut, .mediaKey:
            if !services.isAccessibilityTrusted() { problems.append(.accessibilityPermissionRequired) }
            if let t = shortcutTarget(action, context), !services.isInstalled(bundleIdentifier: t) { problems.append(.applicationNotFound(t)) }
        case .appleScript:
            if !policy.allowAppleScript { problems.append(.appleScriptDisabled) }
            if !trust.isApproved(action) { problems.append(.notApproved(.appleScript)) }
        case .shellCommand:
            if !policy.allowShellCommands { problems.append(.shellCommandsDisabled) }
            if !trust.isApproved(action) { problems.append(.notApproved(.shellCommand)) }
        case .appCommand:
            if let cmd = catalog.command(id: action.appCommandID ?? "") {
                collectProblems(cmd.action, context: context, depth: depth + 1, into: &problems)
            }
        case .sequence:
            for step in action.steps ?? [] { collectProblems(step, context: context, depth: depth + 1, into: &problems) }
        case .none, .openURL, .openFile, .copyText:
            break
        }
    }

    /// Structural validation shared by preflight and execution.
    public func validate(_ action: ActionConfig) throws {
        func nonEmpty(_ s: String?, _ what: String) throws -> String {
            let v = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty else { throw ActionError.invalidConfiguration(L("%@ is empty.", what)) }
            return v
        }
        switch action.kind {
        case .none: throw ActionError.noAction
        case .openApplication: _ = try nonEmpty(action.bundleIdentifier, L("Application"))
        case .openURL:
            let s = try nonEmpty(action.url, L("URL"))
            guard let url = URL(string: s), let scheme = url.scheme, !scheme.isEmpty else {
                throw ActionError.invalidConfiguration(L("“%@” is not a valid URL.", s))
            }
            if scheme.lowercased() == "javascript" { throw ActionError.invalidConfiguration(L("javascript: URLs are not allowed.")) }
            if ["http", "https"].contains(scheme.lowercased()), url.host == nil || url.host!.isEmpty {
                throw ActionError.invalidConfiguration(L("“%@” has no host.", s))
            }
        case .openFile: _ = try nonEmpty(action.path, L("Path"))
        case .keyboardShortcut:
            guard let combo = action.keyCombo, combo.isValid else { throw ActionError.invalidConfiguration(L("No valid key combination recorded.")) }
        case .copyText: _ = try nonEmpty(action.text, L("Text"))
        case .appleScript: _ = try nonEmpty(action.script, L("Script"))
        case .shellCommand: _ = try nonEmpty(action.script, L("Command"))
        case .appCommand:
            let id = try nonEmpty(action.appCommandID, L("Command"))
            guard catalog.command(id: id) != nil else { throw ActionError.unknownAppCommand(id) }
        case .mediaKey:
            guard action.mediaKey != nil else { throw ActionError.invalidConfiguration(L("No media key selected.")) }
        case .sequence:
            guard let steps = action.steps, !steps.isEmpty else { throw ActionError.invalidConfiguration(L("Sequence has no steps.")) }
        }
    }

    private func shortcutTarget(_ action: ActionConfig, _ context: ExecutionContext) -> String? {
        let t = action.targetBundleIdentifier ?? context.associatedBundleIdentifier
        return (t?.isEmpty ?? true) ? nil : t
    }

    private func execute(_ action: ActionConfig, context: ExecutionContext, depth: Int) async throws -> String? {
        guard depth <= Self.maxNestingDepth else { throw ActionError.nestingTooDeep }
        try validate(action)

        switch action.kind {
        case .none:
            throw ActionError.noAction

        case .openApplication:
            try await services.openApplication(bundleIdentifier: action.bundleIdentifier!)
            return nil

        case .openURL:
            try await services.open(url: URL(string: action.url!.trimmingCharacters(in: .whitespaces))!)
            return nil

        case .openFile:
            let path = (action.path! as NSString).expandingTildeInPath
            try await services.openFile(at: URL(fileURLWithPath: path))
            return nil

        case .keyboardShortcut:
            guard services.isAccessibilityTrusted() else { throw ActionError.accessibilityPermissionRequired }
            if let target = shortcutTarget(action, context) {
                try await services.activateApplication(bundleIdentifier: target)
            }
            try services.postKeyCombo(action.keyCombo!)
            return nil

        case .copyText:
            services.copyToPasteboard(action.text!)
            return L("Copied to clipboard")

        case .appleScript:
            guard policy.allowAppleScript else { throw ActionError.appleScriptDisabled }
            guard trust.isApproved(action) else { throw ActionError.notApproved(.appleScript) }
            return try services.runAppleScript(action.script!)

        case .shellCommand:
            guard policy.allowShellCommands else { throw ActionError.shellCommandsDisabled }
            guard trust.isApproved(action) else { throw ActionError.notApproved(.shellCommand) }
            let timeout = max(1, policy.shellTimeoutSeconds)
            let result = try await services.runShell(action.script!, timeout: TimeInterval(timeout))
            if result.timedOut { throw ActionError.timedOut(seconds: timeout) }
            guard result.exitCode == 0 else {
                throw ActionError.shellFailed(exitCode: result.exitCode,
                                              stderr: String(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)))
            }
            let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return out.isEmpty ? nil : String(out.prefix(300))

        case .appCommand:
            let command = catalog.command(id: action.appCommandID!)!
            // Catalog scripts are fixed, shipped code: run them without user approval,
            // but still honour the AppleScript switch.
            if command.action.kind == .appleScript {
                guard policy.allowAppleScript else { throw ActionError.appleScriptDisabled }
                return try services.runAppleScript(command.action.script!)
            }
            return try await execute(command.action, context: context, depth: depth + 1)

        case .mediaKey:
            try services.postMediaKey(action.mediaKey!)
            return nil

        case .sequence:
            let steps = action.steps!
            var last: String?
            for (index, step) in steps.enumerated() {
                if index > 0, let delay = action.delayMilliseconds, delay > 0 {
                    await services.sleep(milliseconds: min(delay, 10_000))
                }
                last = try await execute(step, context: context, depth: depth + 1) ?? last
            }
            return last
        }
    }
}
