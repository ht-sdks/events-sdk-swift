import Foundation

/// Lets other Hightouch modules read the write key; `configuration` is internal.
public extension Analytics {
    var writeKey: String { configuration.values.writeKey }
}
