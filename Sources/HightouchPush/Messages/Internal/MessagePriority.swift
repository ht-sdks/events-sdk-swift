import Foundation
import Hightouch

/// Maps the raw `priority` string to a sortable rank (lower first); unrecognized values sort last.
enum MessagePriority {
    /// `piority` is a misspelling from the message spec, accepted in case the server emits it.
    static let payloadKeys = ["priority", "piority"]

    static func rawValue(from json: JSON?) -> String? {
        if let string = json?.stringValue { return string }
        guard var number = json?.decimalValue else { return nil }
        // A fractional priority has no defined meaning; treat it as unrecognized.
        var truncated = Decimal()
        NSDecimalRound(&truncated, &number, 0, .plain)
        guard truncated == number else { return nil }
        return "\(truncated)"
    }

    static func rank(for priority: String?) -> Int32 {
        guard let trimmed = priority?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return Int32.max
        }

        if let numeric = Int32(trimmed) {
            return numeric
        }

        switch trimmed.lowercased() {
        case "urgent", "critical":
            return 0
        case "high":
            return 100
        case "normal", "medium", "default":
            return 200
        case "low":
            return 300
        default:
            return Int32.max
        }
    }
}
