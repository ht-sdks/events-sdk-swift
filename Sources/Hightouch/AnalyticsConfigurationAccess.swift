import Foundation

/// Lets other Hightouch modules read the write key; `configuration` is internal.
public extension Analytics {
    var writeKey: String { configuration.values.writeKey }

    #if DEBUG
    /// Lets other Hightouch modules skip live network calls under unit tests; `isUnitTesting` is
    /// internal.
    static var isRunningUnitTests: Bool { isUnitTesting }
    #endif
}
