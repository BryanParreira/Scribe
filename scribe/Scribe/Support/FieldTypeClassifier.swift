import CoreGraphics
import Foundation

/// Classifies a focused text field as single-line or multi-line so the pipeline can
/// scale its context window and token budget appropriately.
///
/// Single-line fields (search boxes, URL bars, form inputs) need short, crisp completions
/// — a 20-word suggestion in a search box is noise. Multi-line fields (documents, emails,
/// chat composers) benefit from the full configured budget.
enum FieldType: Equatable, Sendable {
    case singleLine
    case multiLine
}

enum FieldTypeClassifier {
    /// Height threshold below which a field is treated as single-line even when its AX role
    /// is generic (e.g., "AXStaticText" in some web editors that wrap a true text field).
    private static let singleLineHeightThreshold: CGFloat = 50

    static func classify(role: String, subrole: String?, inputFrameRect: CGRect?) -> FieldType {
        switch role {
        case "AXTextField", "AXSearchField", "AXComboBox":
            return .singleLine
        default:
            break
        }
        if let frame = inputFrameRect, frame.height < singleLineHeightThreshold {
            return .singleLine
        }
        return .multiLine
    }

    /// Caps the prefix character window for single-line fields.
    /// Sending 2500 chars of preceding text into a search-box completion is wasteful and
    /// can mislead the model about the writing context.
    static func cappedMaxPrefixCharacters(_ configured: Int, for type: FieldType) -> Int {
        type == .singleLine ? min(configured, 500) : configured
    }

    static func cappedMaxPrefixWords(_ configured: Int, for type: FieldType) -> Int {
        type == .singleLine ? min(configured, 60) : configured
    }

    /// Caps the output token budget for single-line fields.
    /// A search box needs 2–4 words; the configured 12–20 word budget wastes decode time
    /// and produces suggestions too long for the field.
    static func cappedMaxPredictionTokens(_ computed: Int, for type: FieldType) -> Int {
        type == .singleLine ? min(computed, 8) : computed
    }
}
