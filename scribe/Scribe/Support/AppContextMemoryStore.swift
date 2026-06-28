import Foundation

/// File overview:
/// Remembers accepted phrases per application so the model can condition on how the user typically
/// writes in each app. Slack messages tend to be casual; email tends to be formal; Xcode tends to
/// be code. This store captures that drift automatically — no user configuration needed.
///
/// Data is keyed by bundle identifier and persisted across sessions. Up to 10 accepted phrases are
/// kept per app; older ones are evicted when the cap is hit.
final class AppContextMemoryStore {
    static let defaultsKey = "scribeAppContextMemory"
    private static let maxPhrasesPerApp = 10
    private static let minWordCount = 3

    private var memory: [String: [String]]
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        memory = (userDefaults.dictionary(forKey: Self.defaultsKey) as? [String: [String]]) ?? [:]
    }

    func record(_ text: String, bundleIdentifier: String) {
        guard !bundleIdentifier.isEmpty else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        guard wordCount >= Self.minWordCount else { return }

        var phrases = memory[bundleIdentifier] ?? []
        phrases.removeAll { $0 == trimmed }
        phrases.insert(trimmed, at: 0)
        if phrases.count > Self.maxPhrasesPerApp {
            phrases = Array(phrases.prefix(Self.maxPhrasesPerApp))
        }
        memory[bundleIdentifier] = phrases
        userDefaults.set(memory, forKey: Self.defaultsKey)
    }

    /// Returns a short prompt fragment describing how the user typically writes in this app,
    /// or nil when there are fewer than 3 recorded phrases (not enough signal).
    func context(for bundleIdentifier: String, appName: String) -> String? {
        guard let phrases = memory[bundleIdentifier], phrases.count >= 3 else { return nil }
        let sample = phrases.prefix(4).map { "\"\($0)\"" }.joined(separator: ", ")
        return "In \(appName), this user's accepted writing: \(sample)."
    }
}
