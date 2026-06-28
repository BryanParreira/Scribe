import Foundation

/// File overview:
/// Retrieves past accepted phrases that are semantically related to what the user is currently
/// typing. "Semantically related" is approximated via normalized word-overlap (TF-cosine): phrases
/// that share significant vocabulary with the current prefix score higher than purely recent ones.
///
/// Why not NLEmbedding: sentence-level embeddings require a model download and add latency on the
/// per-keystroke path. Word-overlap scores well for the short-text domain (1–20 word phrases) and
/// runs in microseconds with zero I/O. The result is injected into the prompt alongside the
/// recency-based phrases from `RecentPhraseSampler` so the model sees both "what you last wrote"
/// and "what you wrote when writing about similar topics."
final class SemanticPhraseStore {
    static let defaultsKey = "scribeSemanticPhrases"
    private static let maxStoredPhrases = 150
    private static let minWordCount = 3
    private static let topK = 4
    // Common English stop words excluded from overlap scoring so "the", "a", "is" don't dominate.
    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "is", "are", "was", "were", "be", "been",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "it", "its", "this", "that", "these", "those",
        "i", "you", "he", "she", "we", "they", "my", "your", "his", "her", "our"
    ]

    private var phrases: [String]
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        phrases = (userDefaults.array(forKey: Self.defaultsKey) as? [String]) ?? []
    }

    func record(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        guard wordCount >= Self.minWordCount else { return }

        phrases.removeAll { $0 == trimmed }
        phrases.insert(trimmed, at: 0)
        if phrases.count > Self.maxStoredPhrases {
            phrases = Array(phrases.prefix(Self.maxStoredPhrases))
        }
        userDefaults.set(phrases, forKey: Self.defaultsKey)
    }

    /// Returns up to `topK` stored phrases most similar to `query`, ordered by descending score.
    /// Falls back to the most recent phrases when the query contains no meaningful tokens.
    func retrieve(similarTo query: String, topK: Int = SemanticPhraseStore.topK) -> [String] {
        guard !phrases.isEmpty else { return [] }

        let queryTokens = meaningfulTokens(from: query)
        guard !queryTokens.isEmpty else {
            return Array(phrases.prefix(topK))
        }

        let scored: [(phrase: String, score: Double)] = phrases.map { phrase in
            let phraseTokens = meaningfulTokens(from: phrase)
            let score = cosineSimilarity(queryTokens, phraseTokens)
            return (phrase, score)
        }

        return scored
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map(\.phrase)
    }

    // MARK: - Scoring

    private func meaningfulTokens(from text: String) -> Set<String> {
        let words = text
            .lowercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count >= 3 && !Self.stopWords.contains($0) }
        return Set(words)
    }

    /// Normalized overlap: |A ∩ B| / sqrt(|A| * |B|). Equals cosine of binary TF vectors.
    private func cosineSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        let intersection = Double(a.intersection(b).count)
        let denominator = sqrt(Double(a.count) * Double(b.count))
        guard denominator > 0 else { return 0 }
        return intersection / denominator
    }
}
