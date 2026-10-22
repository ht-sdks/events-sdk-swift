import Foundation
import Hightouch

/// A formatter with `.withFractionalSeconds` rejects timestamps without them (and core's is
/// internal), so this tries fractional first, then plain.
enum MessagesISO8601 {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.update(with: .withFractionalSeconds)
        return formatter
    }()

    static let plain = ISO8601DateFormatter()

    /// Accepts an ISO8601 string or a numeric epoch in seconds.
    static func date(from json: JSON?) -> Date? {
        if let string = json?.stringValue, !string.isEmpty {
            return fractional.date(from: string) ?? plain.date(from: string)
        }
        if let decimal = json?.decimalValue {
            return Date(timeIntervalSince1970: (decimal as NSDecimalNumber).doubleValue)
        }
        return nil
    }
}
