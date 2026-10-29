import Foundation
import Hightouch

/// A message's priority. A missing, empty, or unrecognized `priority` decodes to `.default`.
public enum HightouchMessagePriority: String, CaseIterable {
    case high
    case medium
    case low
    case `default`

    /// Sort order, lower first. `.default` sorts after every explicitly set priority.
    var rank: Int32 {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        case .default: return 3
        }
    }

    init(payloadValue: JSON?) {
        self = payloadValue?.stringValue.flatMap(HightouchMessagePriority.init(rawValue:)) ?? .default
    }
}
