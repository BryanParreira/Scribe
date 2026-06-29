import Foundation

/// Maps the current wall-clock hour to a human-readable label that the prompt renderers inject as a
/// lightweight personalization hint. The model uses this to lean toward the register typical for that
/// time — casual/quick in the morning, detailed/formal in the afternoon, winding-down in the evening.
enum TimeOfDayContext {
    static func current(calendar: Calendar = .current, date: Date = Date()) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12: return "morning"
        case 12..<17: return "afternoon"
        case 17..<21: return "evening"
        default: return "night"
        }
    }
}
