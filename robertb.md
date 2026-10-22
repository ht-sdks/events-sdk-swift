# Embedded Messages

Fetch campaign content from Hightouch, cache it locally in Core Data, and render it yourself. The SDK stores and returns an opaque JSON payload; it never interprets your content.

Ships inside the existing `HightouchPush` module — there is no new package, product, or import.

---

# ⚠️ Follow ups — unresolved, read before shipping

**This section is not documentation.** Everything below the divider describes how the feature works as built. This part describes five decisions that are still open, one of which can cause data loss if it's wrong and one of which will break the feature outright if it ships as-is. They are ordered by cost of getting them wrong, not by effort.

## 1. Confirm a `200` is the authoritative full set for the requested identity — **blocking**

Settle this before the feature is enabled against a real endpoint.

Reconciliation is replace-from-server, so a sync **deletes every cached message the response omits** ([`MessageStore+Upsert.swift`](Sources/HightouchPush/Messages/Store/MessageStore+Upsert.swift)). That is correct if and only if a `200` is always the complete set for that identity. If the endpoint ever pages, truncates, or returns a partial result on degraded service, it will silently wipe good cached messages — and the failure presents as "messages randomly disappear," which is expensive to diagnose because nothing errors.

- **Decide with:** whoever owns the messages API.
- **If paging or partial responses are possible:** the response needs either an explicit completeness marker or a `revokedMessageIds` list, and `replaceAll` becomes an additive upsert plus explicit revocation. That is a contained change to one file plus its tests, but it must land *before* the first real sync, not after.
- **Cheap interim hardening if the answer is slow to arrive:** treat an empty `messages` array as suspicious rather than authoritative and skip the delete pass for it, so a degraded response can't clear the whole cache.

## 2. Pin down `priority` semantics — **decide before the sort order is public**

Two unknowns: is `priority` numeric-as-string or a vocabulary, and does a *lower* number mean more important?

The current mapping in [`MessagePriority.swift`](Sources/HightouchPush/Messages/Internal/MessagePriority.swift) assumes numeric ascending (lower sorts first) and recognizes `urgent`/`critical`/`high`/`normal`/`medium`/`default`/`low`. Anything unrecognized sorts last.

Getting it wrong is cheap to fix *mechanically* — the raw server string is preserved on both `HightouchMessage.priority` and the stored `payload`, so correcting the mapping is a local recompute with no server round trip and no schema migration. What isn't cheap is that the **default sort order is public behavior** hosts will have already built layouts against, so changing it later changes what their users see. That asymmetry is the reason to confirm it now rather than ship and adjust.

Also worth confirming: whether a *fractional* priority is ever emitted. It currently takes the unrecognized path and sorts last rather than being truncated.

## 3. Decide whether read/dismissed state must survive a store rebuild — **one-way door**

`readAt` / `dismissedAt` are deliberately **not** in the schema.

They are nearly free to add now and materially more expensive later, and they are the one category of data that could be lost for good: the store's recovery strategy is destroy-and-refetch (see Implementation notes), so anything the server cannot reconstruct is gone on the next corruption or incompatible-model event. Every other field in the store is server-derived and therefore safe to discard.

- **If they can live in memory or be re-derived**, do nothing.
- **If they must persist**, they belong **outside** this store — a separate small store, or the existing `com.hightouch.storage.<writeKey>` UserDefaults suite keyed by `messageId` — precisely so a message-cache rebuild can't take them with it. Adding them as columns on `HTMessageEntity` is the option that looks easiest and is wrong.

Decide deliberately; the failure mode is that this drifts in as a column during a later change and quietly becomes losable.

## 4. Replace the default host before release — **must not ship as-is**

The default messages host is currently a development tunnel:

```
https://uninjured-thread-childcare.ngrok-free.dev/messages
```

Set in `MessagesHTTPClient.defaultHost`, overridable per-host via `HightouchMessagesConfig.messagesHost`. Two properties make it unsuitable for a release build:

- **It isn't durable.** An ngrok URL changes when the tunnel restarts, so a shipped binary would point at an address that no longer resolves — and because sync failures are silent by design (`.failed` outcomes don't surface to the user), the symptom is simply that no messages ever appear.
- **It isn't region-aware.** Unlike `Configuration.apiHost`, one fixed host does not follow a workspace's data residency. A workspace pinned to a non-US region would have its message fetches leave that region.

Note the default is deliberately **not** the events `apiHost`, even though that would be durable and regional — messages are a separate service and the events host has no `/messages` route. So the fix is a real messages host, not a fallback to `apiHost`.

`testDefaultHostIsTheMessagesServiceNotTheEventsAPIHost` in `MessagesSync_Tests.swift` pins the current value, so changing it is a deliberate edit rather than something that can drift.

## 5. Move consumption from a client-side log to a server-side receipt — **the client version has a hard ceiling**

Consume-on-read fights replace-from-server. The server keeps returning a message it has no idea was read, and each sync response is treated as authoritative, so the SDK has to remember locally which ids to withhold — that's `MessageConsumptionLog`, capped at 500 ids per identity in `UserDefaults`.

This works, and `MessagesConsumeOnRead_Tests` pins it, including a test that shows the same resync *does* resurrect a message when suppression is absent. But the cap is a real limit, not a formality:

- Past 500 reads for one identity, the oldest entries are evicted and those messages come back on the next sync. A high-volume user hits this.
- The log is `UserDefaults`, so it survives a store rebuild by design, but not an app reinstall.
- Two devices for the same user don't share it — a message read on a phone still appears on an iPad.

The durable fix is a **consumption receipt**: the SDK tells the server a message was consumed, and the server stops returning it. Then there is no client-side memory, no cap, no per-device divergence, and the "server is source of truth" invariant stops being contradicted by a local exception list. It also restores something consume-on-read currently breaks: the ability to reason about what a device should be showing purely from the server's state.

Until then, be aware the current behavior is best-effort suppression, not a guarantee. If your product genuinely needs show-exactly-once, this needs the server side.

---

# Documentation

Everything below describes the feature as built. Section numbering restarts here and is independent of the follow-ups above.

---

## 1. What a message is

A message is a JSON object. The SDK models a handful of fields for indexing and sorting, keeps the entire payload verbatim, and hands the rest back untouched.

```json
{
  "messageId": "msg_abc",
  "messageType": "embedded",
  "campaignId": "camp_1",
  "createdAt": "2026-08-01T12:00:00.000Z",
  "expiresAt": "2026-09-01T12:00:00.000Z",
  "priority": "1",
  "locationId": "home_banner",
  "variantSlug": "two-button",
  "triggerType": "immediate",
  "version": "1",
  "customValues": {},
  "messageContext": { "executionId": "...", "sendId": "...", "campaignId": "...", "campaignRunId": "..." },
  "content": {
    "html": "",
    "elements": [
      { "id": "1", "tag": "background",   "elementType": "image",  "order": null, "mediaUrl": "https://…/beans.jpg", "mediaCaption": "HQ beans", "text": null, "action": null },
      { "id": "2", "tag": "title",        "elementType": "text",   "order": null, "mediaUrl": null, "mediaCaption": null, "text": "Grown in Brazil, roasted stateside.", "action": null },
      { "id": "3", "tag": "left-button",  "elementType": "button", "text": "Order now",  "action": { "type": "openUrl",   "data": "https://hqcoffe.com/order" } },
      { "id": "4", "tag": "right-button", "elementType": "button", "text": "Learn more", "action": { "type": "addToCart", "data": "sku_1" } }
    ]
  }
}
```

| Field | Required | Notes |
|---|---|---|
| `messageId` | **yes** | The only field whose absence rejects the message. A row with no primary key can't be stored or queried. Empty string is also rejected. |
| `messageType` | no | Defaults to `""`, never null — absence and empty are one value so callers don't juggle both. |
| `createdAt` | no | ISO 8601. Both `…T00:00:00Z` and `…T00:00:00.123Z` parse. |
| `expiresAt` | no | **`null` or absent means never expires.** Expired messages are hidden from every query the instant they expire. |
| `priority` | no | See sorting below. String or bare number both work. The spec's `piority` misspelling is also accepted; `priority` wins if both appear. |
| `locationId`, `variantSlug` | no | The two query keys. |
| `customValues`, `content` | no | Fully opaque. The SDK never reads into them. |
| `messageContext` | no | **Required for attribution.** Without it, engagement events can't be tied to a campaign run — `messageId` alone doesn't carry `executionId`/`sendId`/`campaignId`/`campaignRunId`. Mirrors the push payload's `hightouch.messageContext`. |

**Unknown fields are preserved.** The whole payload is retained on `HightouchMessage.raw` and re-encoded on write, so a field the server adds tomorrow survives a round trip and costs zero SDK changes to keep working. Only a missing `messageId` throws; every other malformed or unexpected field degrades to `nil` rather than failing the message. One bad message in a response never fails the rest of the sync.

**Actions use the object form** — `{"type": …, "data": …}` — the same shape push notifications already use. See §7 (Actions); this matters, and the naive spelling has a trap.

---

## 2. Host integration

```swift
import Hightouch
import HightouchPush

final class MessagesHandler: HightouchMessagesDelegate {
    func hightouchMessagesDidChange(_ change: HightouchMessagesChange) {
        // change.insertedIds / .updatedIds / .removedIds — reload your UI
    }
    func hightouchMessagesSyncDidFail(_ error: Error) {}
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    // MUST be a strong reference. See the warning below.
    static let messagesHandler = MessagesHandler()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        var messagesConfig = HightouchMessagesConfig()
        messagesConfig.delegate = AppDelegate.messagesHandler

        var pushConfig = HightouchPushConfig(appId: "APP_ID")
        pushConfig.messages = messagesConfig          // nil (default) = feature off, no store opened

        // Must be synchronous and must happen here: iOS can launch the app straight into the
        // background to deliver a ghost push, and the fetch handler runs moments later.
        HightouchPush.initialize(
            configuration: Configuration(writeKey: "WRITE_KEY"),
            config: pushConfig
        )
        return true
    }

    // REQUIRED for ghost pushes. Already required for silent push — unchanged.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        HightouchAppIntegration.application(
            application, didReceiveRemoteNotification: userInfo,
            fetchCompletionHandler: completionHandler
        )
    }
}
```

Messages without push is also supported — `HightouchMessages.initialize(analytics:config:)` or `initialize(configuration:config:)` directly.

> **⚠️ The delegate is held weakly.** `HightouchMessagesConfig` stores it as a `weak var`, matching `HightouchPushConfig`. Assigning a freshly-created SwiftUI view model that nothing else retains gives you a silently-nil delegate and no callbacks — the single most common integration mistake here. Either hold it strongly for the app's lifetime, or observe the notification instead:

```swift
.onReceive(NotificationCenter.default.publisher(for: .hightouchMessagesDidChange)) { note in
    let change = note.userInfo?[HightouchMessages.changeUserInfoKey] as? HightouchMessagesChange
}
```

Both mechanisms are supported deliberately. The delegate matches the SDK's established shape; the notification needs no retained object. All callbacks and posts arrive on the **main queue**.

**Info.plist — the step most often missed:**

```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

Without it, iOS will not launch a terminated app for a background push and may not wake a suspended one. No new entitlements are needed; `aps-environment` already covers push.

### Configuration

| Field | Default | Notes |
|---|---|---|
| `delegate` | `nil` | **Weak.** See above. |
| `messagesHost` | `uninjured-thread-childcare.ngrok-free.dev` | Bare host, no scheme. **Currently a dev tunnel — see follow-up 4.** Not the events `apiHost`: messages are a separate service with no `/messages` route on the events host. |
| `messagesPath` | `/messages` | Path **prefix**; the identity is appended as a final segment. Leading slash, no trailing slash. |
| `syncOnForeground` | `true` | |
| `foregroundSyncCooldown` | `900` (15 min) | Clamped to a 60s minimum. |
| `maxStoredMessages` | `500` | Global LRU cap by insertion time, so a misbehaving server can't grow the store without bound. |
| `writeKeyOverride` | `nil` | Escape hatch; normally the write key comes from the `Analytics` instance. |

---

## 3. Querying

```swift
// Convenience
let banners = HightouchMessages.messages(locationId: "home_banner", limit: 3)
let variant = HightouchMessages.messages(variantSlug: "two-button")

// Full control
var query = HightouchMessageQuery(locationId: "home_banner", variantSlug: "two-button", limit: 5)
query.includeExpired = false               // default
query.sort = .priorityThenNewest           // default
let messages = HightouchMessages.messages(matching: query)

let one   = HightouchMessages.message(withId: "msg_abc")
let count = HightouchMessages.messageCount(matching: query)

// Off-thread variants
HightouchMessages.loadMessages(matching: query) { messages in /* on main */ }
let messages = await HightouchMessages.loadMessages(matching: query)

HightouchMessages.deleteMessage(withId: "msg_abc")   // local only, no network
```

> ### ⚠️ Reads consume
>
> `messages(...)`, `message(withId:)`, and `loadMessages(...)` **delete what they return** and record
> it so a later sync won't re-insert it. A second identical call returns nothing.
>
> `messageCount(matching:)` is the one read that does **not** consume — use it to check whether
> anything is pending without spending it.
>
> **This is not idempotent, and SwiftUI re-evaluates `body` freely.** Calling a consuming read
> directly in `body` returns the message on the first evaluation and `[]` on the next, so the view
> flickers to empty for reasons unrelated to state. Read once into `@State` or a view model and
> render from that:
>
> ```swift
> @State private var promo: HightouchMessage?
> // …
> .task { promo = HightouchMessages.messages(locationId: "home_promo", limit: 1).first }
> ```
>
> **Consumption is bounded.** Suppression lives in `MessageConsumptionLog` (`UserDefaults`, outside
> the Core Data store so a store rebuild can't lose it), capped at 500 ids per identity with
> oldest-first eviction. Past that cap the earliest reads are forgotten and the server may resurrect
> those messages. See follow-up 5.

**The synchronous form is the primary path.** It's a `SELECT` over an indexed table with `limit` pushed into SQL, so it's fine to call from `body` or `viewDidLoad` without a placeholder-then-reload render. `loadMessages` exists for large result sets or strict main-thread hygiene; it fetches on a background queue and delivers on main. The `async` variant suspends rather than blocking a cooperative thread.

**Sort order.** `.priorityThenNewest` (default), `.priorityThenOldest`, `.newestFirst`, `.oldestFirst`. Priority sorts on a locally-derived `Int32` rank, never on the raw string — lexicographically `"10" < "2"` and `"high" < "low"`, both wrong. Numeric priorities are taken at face value (lower first); the vocabulary `urgent`/`critical` → 0, `high` → 100, `normal`/`medium`/`default` → 200, `low` → 300; anything unrecognized, empty, or absent sorts **last**, so an unknown value never jumps ahead of one the SDK understands. Every sort appends `messageId ASC` as a final tiebreaker, so the order is **total** — repeated calls return the same sequence, which UI diffing depends on.

`HightouchMessage.priority` always carries the server's raw string, so if the priority semantics turn out inverted, correcting the mapping is a local recompute with no server round trip and no migration.

**Expiry** is enforced at query time, not by a timer — a message becomes invisible the instant `expiresAt` passes, whether or not any cleanup has run. Pruning is separate and reclaims disk space only.

### Messages are scoped to an identity

Every query is implicitly filtered to the identity the messages were fetched for. A message cached for user A is **invisible** to user B on the same device — there is no query path that omits the owner filter.

The identity is `userId` when one is available, otherwise `anonymousId`. **If both are empty, the SDK does not fetch and every query returns empty.** Note this differs from analytics events, which stamp both identifiers; a messages fetch is scoped to exactly one, so every cached row belongs unambiguously to one owner.

Logout does **not** clear the store. It doesn't need to: after logout the current identity changes, the previous owner's rows stop matching, and expiry reclaims them later. Rows also carry `ownerUserId`/`ownerAnonymousId` for provenance.

> `anonymousId` changes only on `Analytics.reset()`, `HightouchPush.logout()`, and `identify()` switching to a different user. Otherwise it survives launches, reboots, and app updates. That churn coincides exactly with when a message cache should stop being visible, which is why owner-scoping is sufficient.

---

## 4. The reconciliation model

**The server is the source of truth. A push is a cache-invalidation hint carrying no payload state.**

Reconciliation is **replace-from-server, scoped to the owner**: a sync response is authoritative for that identity, so any message the server stops returning is deleted locally. Sync runs on `initialize()`, on app foreground (cooldown-gated), on a ghost push, and on an explicit `HightouchMessages.sync()`.

The invariant that makes this safe:

> **Every push signal must be something the next foreground reconcile would have accomplished anyway.**

Hold that and a force-quit costs latency, not data. Break it — the moment a signal can do something the pull path can't — and the signal becomes load-bearing, at which point you own the force-quit problem for real. Check any new verb against this rule before adding it.

This is also why ghost-push hints (`messageIds`, `locationIds`, `syncToken`) are **advisory only**. They may be logged and attached to the `delivered` event, but they never determine what gets stored and are never used to skip a fetch. Background delivery is best-effort and budgeted, so the SDK can never know it has seen every push; a full idempotent refresh converges from any starting point, whereas a delta model would let one dropped push corrupt local state permanently with no self-healing path — and could never express a server-side revocation at all.

```swift
HightouchMessages.sync(force: true) { outcome in
    switch outcome {
    case .changed(let messageCount): break
    case .unchanged:                 break
    case .failed(let error):         break
    }
}
```

Requests are:

```
GET https://<messagesHost><messagesPath>/<identifier>
GET https://uninjured-thread-childcare.ngrok-free.dev/messages/alice     ← default
```

The final path segment is the resolved identity — `userId` when available, otherwise `anonymousId`. Exactly one is ever sent, percent-encoded so an identifier containing `/`, a space, or `?` stays a single segment rather than splitting into another route.

The path carries the identifier's **value, not its kind**, so the endpoint cannot tell a `userId` from an `anonymousId` by inspection and must be able to resolve either. That is not an edge case: `anonymousId` is always populated, so every pre-login device fetches this way.

There's no body, so two things travel as headers instead: `X-Ht-Write-Key` and `X-Ht-Platform: ios`. `sdkVersion` needs no header — `User-Agent: analytics-ios/<version>` already carries it. Headers rather than query parameters because query strings are recorded in full by CDN and proxy access logs and leak via `Referer`, and the write key is a credential. There is still no `Authorization` header anywhere in the SDK; `Configuration.requestFactory` is the hook if you need one.

> **⚠️ A `GET` is cacheable and the identity is now in the URL.** Both were deliberately avoided by the earlier `POST`-with-body shape. The SDK sends `.reloadIgnoringLocalCacheData`, but that only governs its own cache — anything fronting this endpoint must send `Cache-Control: no-store`, or a shared cache can serve one user's messages to another. Access logs will also now contain user identifiers, which is a data-retention question wherever they're shipped.

A `localhost` host uses `http://`. Both `{"messages": […]}` and a bare top-level array are accepted. One retry on 5xx and network errors, never on 4xx. Concurrent `sync()` calls coalesce into a single HTTP request.

---

## 5. Ghost push reference

A ghost push is a silent push whose only job is to tell the SDK to reconcile.

```json
{
  "aps": { "content-available": 1 },
  "hightouch": {
    "messageId": "01J8Z9K2QW3E4R5T6Y7U8I9O0P",
    "command": { "verb": "syncMessages", "reason": "campaign_send" },
    "messageContext": { "executionId": "…", "campaignId": "…", "campaignRunId": "…" }
  }
}
```

A purely local verb — no network at all:

```json
"command": { "verb": "deleteMessage", "messageId": "msg_abc" }
```

**`aps` must contain `content-available: 1` and no `alert`, `sound`, `title`, or `body`.** Any of those makes the push visible and changes its delivery semantics. `badge` is safe; iOS applies it without SDK involvement.

**APNs headers — mandatory, and the usual reason a ghost push "doesn't work":**

| Header | Value | Why |
|---|---|---|
| `apns-push-type` | `background` | Required on iOS 13+; a mismatch gets the push rejected or mis-delivered. |
| `apns-priority` | `5` | APNs **rejects** `background` with priority `10`. |
| `apns-topic` | app bundle id | |
| `apns-expiration` | `now + 3600` | Not `0`, which means discard immediately if undeliverable. |
| `apns-collapse-id` | e.g. `ht-cmd-syncMessages` | Coalesces a burst into one delivery — the cheapest mitigation for background throttling, and safe *precisely because* sync is an idempotent full refresh rather than a delta. |

| Verb | Effect |
|---|---|
| `syncMessages` | Forced reconcile against the server. |
| `deleteMessage` | Removes one cached message locally. **Zero network.** Satisfies the invariant because replace-from-server already drops anything the server stops returning — this only makes it happen sooner. A missing operand is a `.noData` no-op, not a failure. |

**Unrecognized verbs are ignored**, so a newer server can add verbs that older SDKs skip rather than misinterpret. A ghost push does not require `hightouch.messageId` — it's used only for analytics attribution when present.

Ghost pushes do not disturb existing silent-push handling. A push carrying `customData` still reaches `HightouchSilentPushDelegate` exactly as before. If a push carries both a command and `customData`, both run and the OS completion handler fires exactly once.

---

## 6. Delivery matrix — what iOS actually guarantees

| App state | What iOS does | What the SDK does |
|---|---|---|
| Foreground | Handler fires promptly, no budget applies | Runs the verb |
| Backgrounded / suspended in memory | Process resumed, ~30s budget, throttled | `beginBackgroundTask` → verb → `flush()` → complete |
| Terminated by the system, **not** force-quit | **Launches the app into the background**; `didFinishLaunching` runs, then the handler | Same — which is why `initialize()` and all delegates must be set synchronously in `didFinishLaunching` |
| **Force-quit by the user** | **Nothing. Ever.** | Unreachable by silent push. Covered by sync-on-`initialize()` at next launch |
| Locked / Low Power / Low Data | Delayed or dropped | Never treated as guaranteed |

**For `apns-push-type: background`, Apple guarantees nothing.** Delivery is throttled per app, de-prioritized for apps used infrequently, and coalesced. Treat it as an opportunistic freshness hint, not a delivery mechanism. That is exactly why reconciliation is server-authoritative and why sync-on-launch exists.

Internally the SDK imposes a **20-second self-deadline**, well under the OS limit. Overrunning doesn't merely truncate the fetch — iOS kills the process *and* reduces future background allowance, so a slow endpoint degrades the feature permanently rather than once. Results map to `.newData` when local state changed, `.noData` when it didn't (including an unknown verb, or messages not being configured — a no-op for a disabled feature is success, not failure), and `.failed` on network error, the deadline, or OS expiration.

The SDK flushes analytics before completing a background wake. This is necessary rather than defensive: a process launched *into* the background never posts `didEnterBackgroundNotification`, so the flush that normally rides that notification never runs and the `delivered` event would sit queued indefinitely. Note the honest limit — `Analytics.flush()` is fire-and-forget and the upload session is ephemeral, so an in-flight upload still dies on suspension. Flushing narrows the window; it does not close it.

### Deliberate non-goals

- **No App Group, no shared container, no Core Data writes from the Notification Service Extension.** The NSE stays content-only: attach media, build action categories, hand back modified content. Running a fetch there would require the push to be *visible* (an NSE never runs for a pure silent push), an entitlement, a second concurrent writer into Core Data, and a permanent "every campaign must be visible" product constraint — all to buy freshness during a window the user explicitly opted out of. Reserve that design for state the server genuinely cannot reconstruct, and build it narrowly for that state.
- **No `BGTaskScheduler`.** It isn't scheduled for a force-quit app either, so it doesn't solve the hard case; it can't be encapsulated (the host must declare identifiers and register before `didFinishLaunching` returns); and OS scheduling is discretionary and typically hours-scale — a worse freshness signal than "the user opened the app," which is already handled. If you already use it, call `HightouchMessages.sync()` from your own task.
- **No SDK-side UI**, and no Combine/`ObservableObject`. Rendering and observable state belong to the host.
- Not available on Linux, tvOS, or watchOS. The API exists everywhere and returns empty there, so call sites compile unchanged.

---

## 7. Actions

**Message actions use the exact same mechanism as push notification actions** — same `HightouchAction`, same delegates, same routing ladder. There is no separate action model and no reserved URL-scheme convention.

```swift
Button(element.text ?? "") {
    // Records the click, then hands the action back for you to perform.
    if let action = HightouchMessages.handleAction(
        element.action, messageId: message.messageId,
        elementId: element.id, elementTag: element.tag
    ) {
        switch action.type {
        case "openUrl": if let s = action.data, let url = URL(string: s) { openURL(url) }
        default:        route(action)
        }
    }
}
.onAppear { HightouchMessages.trackImpression(messageId: message.messageId) }
```

`handleAction` **resolves and records — it does not route.** That differs from push on purpose:

1. A push tap happens while the app is *not* in control; the OS delivered it and there's no host UI context, so the SDK must route. A message element tap happens inside your own view hierarchy during a normal touch event, where you already have a navigation stack and possibly an in-flight animation.
2. Ordering matters and only you know it — dismiss then navigate, or navigate then dismiss.
3. The action delegates are weak. For push, a nil `urlDelegate` degrades to `UIApplication.open`. For a message custom action, degrading to *nothing* is a bad failure mode; better to hand you a value you must consume.
4. The click event fires unconditionally, so analytics don't depend on whether you routed or whether a delegate happened to be alive.

If you have no ordering constraints, opt into routing:

```swift
HightouchMessages.performAction(element.action, messageId: message.messageId,
                                elementId: element.id, elementTag: element.tag)
```

That runs the same ladder as a push tap — `HightouchURLDelegate` first for `openUrl`; if it returns false, an `allowedProtocols` scheme check then `UIApplication.open`; any other type goes to `HightouchCustomActionDelegate`. Your delegates receive a `HightouchActionSource.message(messageId:elementId:elementTag:)` context.

Also available: `trackDismissed(messageId:)` and `trackClick(messageId:)`.

`trackClick` emits the same `clicked` event when the host owns the action entirely — a tapped element with no action, a body tap, navigation you already handle. It carries `message_id` only, with no `action` dict and no element identifiers, so the same event type arrives in two shapes. **Nothing dedupes them:** a tap that goes through `handleAction` *and* calls `trackClick` emits two `clicked` events. Pick one path per tap.

> **⚠️ Emit the object form.** A bare string is tolerated and treated as `{"type": "openUrl", "data": <string>}`, because a bare string can only be a URL in this model. That has a consequence worth stating plainly: **`"action": "hightouch://clicked"` resolves to `openUrl`.** It reaches `HightouchURLDelegate`, where you *can* handle it and return `true` — but if you decline, it is **dropped**, because `hightouch` is not `https` and won't be in `allowedProtocols`. It never reaches `HightouchCustomActionDelegate`. Use `{"type": "clicked", "data": …}` for anything that isn't a real URL.

> **⚠️ Source-breaking change.** `HightouchActionSource` gained a `.message` case. It's a public non-`@frozen` enum and SPM doesn't build with library evolution, so any exhaustive `switch` over it without a `default` will stop compiling. Add a `default:`.

---

## 8. Analytics

Message events reuse the existing `"CEP Engagement Events"` track name and are distinguished by a `channel_type` dimension — `"in_app"` with `_ht_cep_source: "in_app_sdk"`, versus `"push"`/`"push_sdk"`. Channel is a dimension, not a category; splitting the track name on it would duplicate the warehouse schema and break funnels that span push and in-app.

| `provider_event_type` | Channel | When |
|---|---|---|
| `delivered` | `push` | A ghost push was handled. Carries `sync_reason` and `message_count`. |
| `displayed` | `in_app` | `trackImpression(messageId:)` |
| `clicked` | `in_app` | `trackClick(messageId:)` (message-level), or `handleAction`/`performAction` (element-level: adds nested `action` plus `element_id`/`element_tag`). Calling both for one tap double-counts. |
| `dismissed` | `in_app` | `trackDismissed(messageId:)` |

`delivered` is the SDK's **first delivery signal** — previously only `registered`, `disabled`, and `opened` existed.

> **⚠️ For whoever owns the data model:** push uses `opened` (a notification opened the app); messages use `clicked` (an element tap, no app-open). These are **not** the same event and conflating them corrupts CTR math. The asymmetry is intentional.

There is deliberately no `synced` event — sync is diagnostic, not engagement, and would flood the stream. Its outcome rides on `delivered` instead.

---

## 9. Implementation notes

- **The Core Data model is built programmatically**, not from an `.xcdatamodeld`. `momc` ships only inside Xcode, so a model resource breaks `swift build` on Linux outright, and resource bundles inside XCFrameworks are a known crash source.
- **The whole message JSON is stored in one `payload` blob**; the typed columns are projections of it. That's what makes a new server field cost zero schema change, and adding an index later free (add the attribute, bump the model version, backfill by re-deriving from `payload`). Don't shred the blob into columns.
- **Uniqueness is composite — `(messageId, ownerKey)`.** `messageId` alone would be wrong: the same message can legitimately exist for two identities on a shared device.
- **Recovery is destroy-and-refetch.** On an incompatible model, migration failure, or corruption, the store is destroyed and rebuilt once. Messages are re-fetchable, so losing them always beats a permanently broken store. The model version is in the filename, so a deliberate breaking change is a rename rather than a migration.
- **Managed objects never cross a thread.** Reads map to `HightouchMessage` value types before leaving their context; the store never creates a main-queue context at all.
- The store lives at `<Application Support>/Hightouch/Messages/<safeWriteKey>/messages-v1.sqlite`, excluded from backup — it's a cache of server state, and restoring a stale copy onto a new device would be wrong.
- `swift test` on macOS executes **zero** `#if os(iOS)`-gated tests. Real coverage needs `xcodebuild test -scheme Hightouch-Package -destination 'platform=iOS Simulator,…'`.
