import Foundation

/// Ordering for a `messages(matching:)` result. In the priority cases, a lower `priorityRank`
/// sorts first. Final ties break on `messageId`, so the order is stable.
public enum HightouchMessageSort: Equatable {
    case priorityThenNewest
    case priorityThenOldest
    case newestFirst
    case oldestFirst
}

/// Which cached messages to return and how to order them. `HightouchMessageQuery()` matches all.
public struct HightouchMessageQuery: Equatable {
    /// Restrict to messages with this `locationId`. `nil` matches any.
    public var locationId: String?

    /// Restrict to messages with this `variantSlug`. `nil` matches any.
    public var variantSlug: String?

    /// `nil`, `0`, or negative mean unlimited.
    public var limit: Int?

    /// Whether to include messages whose `expiresAt` has already passed. Default `false`.
    public var includeExpired: Bool = false

    public var sort: HightouchMessageSort = .priorityThenNewest

    /// Clock used for expiry; `nil` means `Date()` at query time.
    public var now: Date?

    public init(
        locationId: String? = nil,
        variantSlug: String? = nil,
        limit: Int? = nil,
        includeExpired: Bool = false,
        sort: HightouchMessageSort = .priorityThenNewest,
        now: Date? = nil
    ) {
        self.locationId = locationId
        self.variantSlug = variantSlug
        self.limit = limit
        self.includeExpired = includeExpired
        self.sort = sort
        self.now = now
    }
}
