import Foundation

/// Tracks which suggestion prefixes the user consistently ignores so future prompts can avoid
/// re-proposing the same continuations. Designed to be zero-cost on every keystroke:
/// dismissals are accumulated in an in-memory buffer and written to disk at most once per minute,
/// never on the critical input path.
final class RejectionPatternStore {
    private static let defaultsKey = "scribeRejectedPrefixes"
    private static let maxStored = 80
    private static let flushInterval: TimeInterval = 60

    private var buffer: [(prefix: String, at: Date)] = []
    private var lastFlush = Date.distantPast
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Records that the user dismissed a suggestion whose visible text began with `suggestionStart`.
    /// Call from the idle/teardown path — not the critical keystroke path. O(1), no disk I/O.
    func recordDismissal(of suggestionStart: String) {
        let trimmed = String(suggestionStart.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        buffer.append((prefix: trimmed, at: Date()))
        maybeFlush()
    }

    /// Returns true when this prefix has been repeatedly dismissed (≥3 times).
    /// Used by the prompt renderer to add a soft hint to vary the suggestion.
    func isFrequentlyRejected(_ prefix: String) -> Bool {
        let stored = userDefaults.stringArray(forKey: Self.defaultsKey) ?? []
        let trimmed = String(prefix.prefix(40))
        return stored.filter { $0 == trimmed }.count >= 3
    }

    private func maybeFlush() {
        let now = Date()
        guard now.timeIntervalSince(lastFlush) >= Self.flushInterval else { return }
        lastFlush = now
        var stored = userDefaults.stringArray(forKey: Self.defaultsKey) ?? []
        stored.append(contentsOf: buffer.map(\.prefix))
        buffer.removeAll()
        if stored.count > Self.maxStored {
            stored = Array(stored.suffix(Self.maxStored))
        }
        userDefaults.set(stored, forKey: Self.defaultsKey)
    }
}
