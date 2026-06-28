import Foundation

/// Maintains a bounded ring buffer of recently accepted text phrases, persisted in UserDefaults.
///
/// Accepted phrases are injected into the prompt as few-shot style examples so the model
/// generates text that sounds like the specific user rather than generic prose. The buffer is
/// small (5 entries) and only records phrases long enough to carry voice signal (≥3 words).
final class RecentPhraseSampler {
    static let defaultsKey = "scribeRecentAcceptedPhrases"
    private static let maxCount = 5
    private static let minWordCount = 3
    private static let maxPhraseCharacters = 120

    private var phrases: [String]
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        phrases = (userDefaults.array(forKey: Self.defaultsKey) as? [String]) ?? []
    }

    /// Records an accepted chunk as a recent phrase sample.
    /// Skips chunks too short to carry style signal. Deduplicates and trims to the cap.
    func record(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        guard wordCount >= Self.minWordCount else { return }
        let capped = String(trimmed.prefix(Self.maxPhraseCharacters))
        // Deduplicate: move an identical entry to front rather than duplicating.
        phrases.removeAll { $0 == capped }
        phrases.insert(capped, at: 0)
        if phrases.count > Self.maxCount {
            phrases = Array(phrases.prefix(Self.maxCount))
        }
        userDefaults.set(phrases, forKey: Self.defaultsKey)
    }

    var recentPhrases: [String] { phrases }
}
