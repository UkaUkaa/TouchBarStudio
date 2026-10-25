import CryptoKit
import Foundation

/// Remembers which exact script/command texts the user has approved. Approval is keyed
/// by a SHA-256 of kind + text, so any edit (or an imported variant) needs re-approval.
/// Stored separately from the configuration and never exported.
@MainActor
public final class ScriptTrustStore {
    private(set) public var approvedHashes: Set<String>
    private let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let hashes = try? JSONDecoder().decode([String].self, from: data) {
            approvedHashes = Set(hashes)
        } else {
            approvedHashes = []
        }
    }

    public static func fingerprint(of action: ActionConfig) -> String? {
        guard action.kind == .appleScript || action.kind == .shellCommand else { return nil }
        let material = action.kind.rawValue + "\n" + (action.script ?? "")
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func isApproved(_ action: ActionConfig) -> Bool {
        guard let fp = Self.fingerprint(of: action) else { return true }
        return approvedHashes.contains(fp)
    }

    /// True when every script inside the action (including sequence steps) is approved.
    public func isFullyApproved(_ action: ActionConfig) -> Bool {
        action.scriptActions.allSatisfy(isApproved)
    }

    public func approve(_ action: ActionConfig) {
        let fps = action.scriptActions.compactMap(Self.fingerprint)
        guard !fps.isEmpty else { return }
        approvedHashes.formUnion(fps)
        persist()
    }

    public func revokeAll() {
        approvedHashes.removeAll()
        persist()
    }

    private func persist() {
        guard let fileURL else { return }
        if let data = try? JSONEncoder().encode(approvedHashes.sorted()) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
}
