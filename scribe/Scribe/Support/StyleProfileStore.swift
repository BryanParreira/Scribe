import Foundation

/// File overview:
/// Learns the user's writing style from accepted suggestions and generates a short natural-language
/// summary that rides in the prompt as a passive style guide. The model reads this description and
/// conditions its output to match the user's voice without the user having to write explicit rules.
///
/// The profile is derived entirely from acceptances — text the user chose to keep — so it reflects
/// real preferences rather than the user's beliefs about their preferences. It persists across sessions
/// via UserDefaults and updates incrementally on each acceptance.
final class StyleProfileStore {
    static let defaultsKey = "scribeStyleProfile"
    private static let maxSamples = 300
    private static let minWordsToRecord = 3

    private struct Profile: Codable {
        var totalSentenceLengths: Int = 0
        var sentenceCount: Int = 0
        var formalMarkerCount: Int = 0
        var informalMarkerCount: Int = 0
        var wordFrequency: [String: Int] = [:]
        var totalAcceptances: Int = 0
    }

    // Words that signal formal register.
    private static let formalMarkers: Set<String> = [
        "however", "therefore", "furthermore", "consequently", "regarding",
        "accordingly", "nevertheless", "notwithstanding", "henceforth",
        "pursuant", "aforementioned", "herein", "whereas", "thereof"
    ]
    // Words that signal informal/conversational register.
    private static let informalMarkers: Set<String> = [
        "hey", "yeah", "gonna", "wanna", "kinda", "sorta", "lol",
        "btw", "tbh", "ngl", "omg", "imo", "idk", "ok", "okay",
        "pretty", "super", "literally", "basically", "totally"
    ]

    private var profile: Profile
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(Profile.self, from: data) {
            profile = decoded
        } else {
            profile = Profile()
        }
    }

    func record(_ text: String) {
        let words = text.split(whereSeparator: \.isWhitespace).map { String($0).lowercased() }
        guard words.count >= Self.minWordsToRecord else { return }
        guard profile.totalAcceptances < Self.maxSamples else { return }

        profile.totalSentenceLengths += words.count
        profile.sentenceCount += 1
        profile.totalAcceptances += 1

        for word in words {
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            guard clean.count >= 3 else { continue }
            if Self.formalMarkers.contains(clean) { profile.formalMarkerCount += 1 }
            if Self.informalMarkers.contains(clean) { profile.informalMarkerCount += 1 }
            profile.wordFrequency[clean, default: 0] += 1
        }

        persist()
    }

    /// Returns a 1-sentence natural-language style description, or nil when there is not yet
    /// enough data to draw meaningful conclusions (fewer than 10 accepted phrases).
    func styleProfileSummary() -> String? {
        guard profile.sentenceCount >= 10 else { return nil }

        let avgLength = profile.totalSentenceLengths / max(profile.sentenceCount, 1)
        let lengthLabel: String
        switch avgLength {
        case ..<6:  lengthLabel = "very short, punchy"
        case 6..<10: lengthLabel = "concise"
        case 10..<16: lengthLabel = "moderate-length"
        default:    lengthLabel = "detailed, longer"
        }

        let total = profile.formalMarkerCount + profile.informalMarkerCount
        let registerLabel: String
        if total < 3 {
            registerLabel = "neutral"
        } else {
            let formalRatio = Double(profile.formalMarkerCount) / Double(total)
            switch formalRatio {
            case 0.7...: registerLabel = "formal"
            case 0.4..<0.7: registerLabel = "semi-formal"
            default:     registerLabel = "conversational"
            }
        }

        let topWords = profile.wordFrequency
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map(\.key)

        var summary = "The writer uses \(lengthLabel) sentences with a \(registerLabel) register."
        if !topWords.isEmpty {
            summary += " Frequently uses: \(topWords.joined(separator: ", "))."
        }
        return summary
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        userDefaults.set(data, forKey: Self.defaultsKey)
    }
}
