import Foundation

/// Tracks which first-use hints have been shown so each fires exactly once across sessions.
/// Hints teach the user about features they may not know exist: Tab acceptance, typo correction,
/// and emoji shortcodes. Once shown, the flag is set permanently and the hint never reappears.
final class FeatureSpotlightStore {
    enum Hint: String, CaseIterable {
        case tabAcceptance = "scribeSpotlight_tabAcceptance"
        case typoCorrection = "scribeSpotlight_typoCorrection"
        case emojiShortcode = "scribeSpotlight_emojiShortcode"

        var message: String {
            switch self {
            case .tabAcceptance:
                return "Press Tab to accept the next word"
            case .typoCorrection:
                return "Scribe spotted a typo — Tab fixes it"
            case .emojiShortcode:
                return "Type :sun or :heart to pick an emoji"
            }
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Returns `true` and marks the hint as shown if it has never been shown before.
    /// Returns `false` if the hint was already shown in a previous session.
    func shouldShow(_ hint: Hint) -> Bool {
        let key = hint.rawValue
        guard !userDefaults.bool(forKey: key) else { return false }
        userDefaults.set(true, forKey: key)
        return true
    }

    func resetAll() {
        Hint.allCases.forEach { userDefaults.removeObject(forKey: $0.rawValue) }
    }
}
