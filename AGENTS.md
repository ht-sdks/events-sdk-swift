# Agent Instructions

This file provides instructions for AI agents working on this Swift SDK.

## Project Overview

- **Language**: Swift (swift-tools-version 5.7+)
- **Package Manager**: Swift Package Manager (SPM)
- **Testing**: XCTest
- **CI**: GitHub Actions (Xcode 15.2 on macOS 14, Swift 5.7.2+ on Linux)
- **State Management**: [Sovran-Swift](https://github.com/segmentio/Sovran-Swift.git) (from 1.1.0)
- **Product**: `Hightouch` — the Hightouch Events SDK for Apple platforms and Linux

### Supported Platforms

| Platform | Minimum Version |
|----------|----------------|
| macOS    | 10.15          |
| iOS      | 13.0           |
| tvOS     | 11.0           |
| watchOS  | 7.1            |
| Linux    | (Swift 5.7.2+) |

### Project Structure

```
Sources/
  Hightouch/
    Analytics.swift               # Core Analytics class (entry point)
    Configuration.swift           # Configuration builder (fluent API)
    Events.swift                  # track/identify/screen/group/alias event methods
    Types.swift                   # RawEvent protocol, TrackEvent, IdentifyEvent, etc.
    Plugins.swift                 # Plugin/EventPlugin/DestinationPlugin protocols
    Timeline.swift                # Event processing pipeline (before → enrichment → destination → after)
    Settings.swift                # Remote settings model + integration settings
    Startup.swift                 # Platform startup, lifecycle setup, settings check
    State.swift                   # Sovran state: System and UserInfo
    Version.swift                 # Auto-generated version string (DO NOT EDIT BY HAND)
    Errors.swift                  # AnalyticsError enum
    Deprecations.swift            # Deprecated API stubs
    Plugins/
      Context.swift               # Enrichment plugin adding device/os/app context
      SegmentDestination.swift    # Built-in destination that sends events to Hightouch API
      StartupQueue.swift          # Queues events until SDK is running
      DeviceToken.swift           # Push notification device token handling
      DestinationMetadataPlugin.swift  # Adds bundled/unbundled metadata
      Platforms/
        iOS/                      # iOS lifecycle monitor + events
        Mac/                      # macOS lifecycle monitor + events
        watchOS/                  # watchOS lifecycle monitor + events
        Linux/                    # Linux lifecycle monitor (placeholder)
        Vendors/                  # VendorSystem abstraction (Apple vs Linux)
    ObjC/                         # Objective-C compatibility wrappers (HTAnalytics, etc.)
    Utilities/
      HTTPClient.swift            # Networking: batch upload + settings fetch
      Storage.swift               # File-based event storage + UserDefaults persistence
      JSON.swift                  # Custom JSON type for Codable interop
      KeyPath.swift               # Dictionary keypath utilities
      Atomic.swift                # Thread-safe property wrapper
      QueueTimer.swift            # Timer utility for flush intervals
      OutputFileStream.swift      # File writing stream for event batches
      Logging.swift               # Internal logging
      iso8601.swift               # Date formatting
      Utils.swift                 # Misc utilities
      Policies/
        FlushPolicy.swift         # FlushPolicy protocol
        CountBasedFlushPolicy.swift   # Flush after N events (default: 20)
        IntervalBasedFlushPolicy.swift # Flush on time interval (default: 30s)
    Resources/
      PrivacyInfo.xcprivacy       # Apple privacy manifest

Tests/
  Hightouch-Tests/
    Analytics_Tests.swift         # Core analytics tests (24 tests)
    HTTPClient_Tests.swift        # HTTP client tests
    JSON_Tests.swift              # JSON utility tests (10 tests)
    KeyPath_Tests.swift           # KeyPath tests (5 tests)
    Storage_Tests.swift           # Storage tests (4 tests)
    FlushPolicy_Tests.swift       # Flush policy tests (5 tests)
    Timeline_Tests.swift          # Timeline/plugin chain tests (3 tests)
    iOSLifecycle_Tests.swift      # iOS lifecycle tests
    MemoryLeak_Tests.swift        # Memory leak detection tests (2 tests)
    StressTests.swift             # Concurrency stress tests
    ObjC_Tests.swift              # Objective-C compatibility tests
    Support/
      TestUtilities.swift         # Shared test helpers, mock plugins
    XCTestManifests.swift         # Linux test manifest
  LinuxMain.swift                 # Linux test entry point

Examples/
  destination_plugins/            # Example destination plugin implementations
  other_plugins/                  # Example enrichment/utility plugins
  tasks/                          # Example tasks (custom flush policies, multi-instance)
  apps/                           # Example Xcode projects (iOS, macOS, watchOS, SwiftUI, UIKit, ObjC, widgets)
```

### Key Dependencies

| Dependency | Purpose |
|------------|---------|
| [Sovran-Swift](https://github.com/segmentio/Sovran-Swift.git) (>=1.1.0) | Lightweight state management (Store, State, Action, Subscriber) |

No other external dependencies. The SDK is intentionally lightweight.

---

## Updating Dependencies

### 1. Pre-flight Checks

```bash
# Check Swift version (minimum 5.7 required, see Package.swift swift-tools-version)
swift --version

# Ensure you're at the repository root
pwd  # Should be: /path/to/events-sdk-swift
```

**On Linux**, if Swift is not installed, download and install it:

```bash
# Download Swift for your Ubuntu version (example for Ubuntu 24.04)
curl -sL -o /tmp/swift.tar.gz \
  "https://download.swift.org/swift-5.10.1-release/ubuntu2404/swift-5.10.1-RELEASE/swift-5.10.1-RELEASE-ubuntu24.04.tar.gz"

# Extract to a local directory
mkdir -p ~/swift-toolchain
tar -xzf /tmp/swift.tar.gz -C ~/swift-toolchain

# Add to PATH
export PATH="$HOME/swift-toolchain/swift-5.10.1-RELEASE-ubuntu24.04/usr/bin:$PATH"

# Install required system libraries if missing
sudo apt-get install -y libncurses6 libcurl4 libxml2

# Verify
swift --version
```

### 2. Establish Test Baseline

```bash
# Resolve and fetch dependencies
swift package resolve

# Build the package
swift build

# Run all tests
swift test

# On Linux, use test discovery:
swift test --enable-test-discovery
```

Record the number of passing tests before making any changes. As of the current codebase, the Linux test suite runs **53 tests with 0 failures**. This ensures you can verify nothing broke after upgrading.

### 3. Check Current Dependency Versions

```bash
# Show the dependency tree and resolved versions
swift package show-dependencies
```

This currently shows:

```
.
└── sovran-swift<https://github.com/segmentio/Sovran-Swift.git@1.1.0>
```

### 4. Check for Available Updates

```bash
# Dry-run update to see what would change without actually updating
swift package update --dry-run
```

This shows which dependencies have newer versions available within their semver constraints. Example output:

```
1 dependency has changed:
~ sovran-swift 1.1.0 -> sovran-swift 1.1.2
```

### 5. Upgrade Dependencies

#### Option A: Safe Updates (within semver range)

```bash
# Update all dependencies to latest within their semver constraints
swift package update
```

This modifies `Package.resolved` but not `Package.swift`. The update is bounded by the version requirement in `Package.swift` (currently `from: "1.1.0"` for Sovran-Swift, meaning any `1.x.y >= 1.1.0`).

#### Option B: Major/Breaking Version Updates

For updates beyond the current semver range, edit `Package.swift` directly:

```swift
// Change the version requirement
.package(url: "https://github.com/segmentio/Sovran-Swift.git", from: "2.0.0")
```

Then re-resolve:

```bash
# Clean and re-resolve
swift package reset
swift package resolve
```

#### Option C: Pin to a Specific Version

```bash
# Resolve a specific package to an exact version
swift package resolve sovran-swift --version 1.1.2
```

### 6. Rebuild and Test

```bash
# Clean build artifacts (recommended after dependency changes)
swift package clean

# Rebuild
swift build

# Run all tests
swift test                           # macOS
swift test --enable-test-discovery   # Linux

# Run a specific test class
swift test --filter Analytics_Tests

# Run a specific test method
swift test --filter Analytics_Tests/testTrack
```

Compare test results to baseline (**53 tests, 0 failures** on Linux). Fix any failures before proceeding.

### 7. Verify CI Would Pass

The CI runs on two platforms. To replicate locally:

**macOS (via SPM):**

```bash
swift build
swift test
```

**macOS (via xcodebuild for specific simulators):**

```bash
# iOS Simulator
xcodebuild -scheme Hightouch test -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# tvOS Simulator
xcodebuild -scheme Hightouch test -sdk appletvsimulator \
  -destination 'platform=tvOS Simulator,name=Apple TV'

# watchOS Simulator
xcodebuild -scheme Hightouch test -sdk watchsimulator \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)'
```

**Linux:**

```bash
swift build
swift test --enable-test-discovery
```

### 8. Commit the Update

After verifying all tests pass:

```bash
# Package.resolved is gitignored in this repo, so there is nothing
# extra to commit unless you changed Package.swift itself.
# If you edited Package.swift:
git add Package.swift
git commit -m "Update Sovran-Swift dependency to X.Y.Z"
```

---

## Architecture

### Event Pipeline

Events flow through the `Timeline` in this order:

```
before → enrichment → destination → after
```

Each stage contains a `Mediator` that runs registered `Plugin` instances sequentially. The `DestinationPlugin` has its own sub-timeline for destination-specific enrichments.

### State Management

Uses Sovran for two state objects:

- **`System`**: holds `Configuration`, `Settings`, `running` flag, and `enabled` flag
- **`UserInfo`**: holds `anonymousId`, `userId`, `traits`, and `referrer`

State changes are dispatched via `Action` structs and persisted to `UserDefaults` + file storage via `Storage`.

### Plugin System

```
Plugin (base protocol)
  ├── EventPlugin (has typed event methods: track, identify, screen, group, alias)
  │     ├── DestinationPlugin (has its own sub-timeline + key for settings lookup)
  │     └── UtilityPlugin (marker protocol)
  └── PlatformPlugin (internal, platform-specific)
```

### Storage

- **Events**: Written as JSON to files on disk (`{ "batch": [...], "sentAt": "...", "writeKey": "..." }`), rotated at 475KB max. Files get a `.temp` extension once finalized for upload.
- **User data**: Stored in `UserDefaults` under the suite `com.hightouch.storage.<writeKey>`.

---

## Building and Testing

### Prerequisites

- **macOS**: Xcode 15.2+ (for full platform testing)
- **Linux**: Swift 5.7+ (5.10.1 recommended; see Pre-flight Checks above for install instructions)
- **Linux system libraries**: `libncurses6`, `libcurl4`, `libxml2`

### Build

```bash
swift build
```

### Run Tests

```bash
# macOS / Linux
swift test

# Linux (with test discovery)
swift test --enable-test-discovery
```

### Run Tests for Specific Platform Simulators (macOS only)

```bash
# iOS Simulator
xcodebuild -scheme Hightouch test -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# tvOS Simulator
xcodebuild -scheme Hightouch test -sdk appletvsimulator \
  -destination 'platform=tvOS Simulator,name=Apple TV'

# watchOS Simulator
xcodebuild -scheme Hightouch test -sdk watchsimulator \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)'
```

### Build Example Apps (macOS only)

```bash
cd Examples/apps/BasicExample
xcodebuild -workspace "BasicExample.xcworkspace" -scheme "BasicExample" -sdk iphonesimulator

cd Examples/apps/ObjCExample
xcodebuild -workspace "ObjCExample.xcworkspace" -scheme "ObjCExample" -sdk iphonesimulator

cd Examples/apps/SegmentUIKitExample
xcodebuild -workspace "SegmentUIKitExample.xcworkspace" -scheme "SegmentUIKitExample" -sdk iphonesimulator

cd Examples/apps/SegmentWeatherWidget
xcodebuild -workspace "SegmentWeatherWidget.xcworkspace" -scheme "SegmentWeatherWidget" -sdk iphonesimulator

# Mac Catalyst
cd Examples/apps/SegmentUIKitExample
xcodebuild -workspace "SegmentUIKitExample.xcworkspace" -scheme "SegmentUIKitExample" \
  -destination 'platform=macOS,variant=Mac Catalyst'
```

### Run a Single Test

```bash
# Run a specific test class
swift test --filter Analytics_Tests

# Run a specific test method
swift test --filter Analytics_Tests/testTrack

# Run tests matching a pattern
swift test --filter testFlush
```

---

## CI/CD

### CI Workflow (`.github/workflows/swift.yml`)

Runs on push/PR to `main`. Jobs:

| Job | Runner | What it does |
|-----|--------|-------------|
| `build_and_test_spm_mac` | macOS 14, Xcode 15.2 | `swift build` + `swift test` |
| `build_and_test_spm_linux` | Ubuntu, Swift 5.7.2 | `swift build` + `swift test --enable-test-discovery` |
| `build_and_test_ios` | macOS 14, Xcode 15.2 | `xcodebuild test` on iPhone 15 simulator |
| `build_and_test_tvos` | macOS 14, Xcode 15.2 | `xcodebuild test` on Apple TV simulator |
| `build_and_test_watchos` | macOS 14, Xcode 15.2 | `xcodebuild test` on Apple Watch Series 9 simulator |
| `build_and_test_examples` | macOS 14, Xcode 15.2 | Builds BasicExample, ObjCExample, UIKitExample, WeatherWidget, Mac Catalyst |

### Known CI Issues

**Linux job (`build_and_test_spm_linux`)**: The CI uses `sersoft-gmbh/swifty-linux-action@v3` to install Swift 5.7.2. When GitHub Actions updates its `ubuntu-latest` runner to a newer Ubuntu version (e.g., 24.04), Swift 5.7.2 may not have a release for that platform, causing a 404 download error. The fix is to update the `release-version` in `.github/workflows/swift.yml` to a Swift version that supports the current Ubuntu runner (e.g., 5.10.1 for Ubuntu 24.04).

**iOS job (`build_and_test_ios`)**: Occasionally fails with `Failed to create a bundle instance` errors. This is typically an Xcode/simulator infrastructure flake in CI, not a code issue.

### Release Workflow (`.github/workflows/tagged-release.yml`)

Triggered by tags matching `v[0-9]+.[0-9]+.[0-9]+`. Posts a notification to Slack.

---

## Releasing

Use `release.sh` to perform releases. The script:

1. Validates you are on the `main` branch
2. Validates the new version is greater than the current version
3. Updates `Sources/Hightouch/Version.swift` with the new version
4. Commits the change and pushes
5. Creates a GitHub Release with a changelog (commits since last tag)
6. Runs `build.sh` to produce XCFramework zips
7. Uploads `Hightouch.zip`, `Hightouch.sha256`, `Sovran.zip`, `Sovran.sha256` to the release

```bash
./release.sh 1.2.3
```

### Required Tools for Releasing

- `gh` (GitHub CLI): `brew install gh` — must be authenticated (`gh auth login`)
- `swift-create-xcframework`: `brew install mint && mint install unsignedapps/swift-create-xcframework`

### Version File

`Sources/Hightouch/Version.swift` is **auto-generated** by `release.sh`. Do NOT edit it by hand. It contains:

```swift
internal let __hightouch_version = "X.Y.Z"
```

This version string is used in:
- `Analytics.version()` — public API
- HTTP `User-Agent` header: `analytics-ios/<version>`
- Context payload: `library.version`

### Semantic Versioning

- **PATCH** (0.0.6 → 0.0.7): Bug fixes, dependency updates, no new features
- **MINOR** (0.0.6 → 0.1.0): New backwards-compatible features
- **MAJOR** (0.0.6 → 1.0.0): Breaking API changes

The version follows `BREAKING.FEATURE.FIX` format as noted in `Version.swift`.

---

## Key Patterns and Conventions

### Fluent Configuration API

`Configuration` uses a builder pattern with `@discardableResult` methods that return `self`:

```swift
let config = Configuration(writeKey: "YOUR_KEY")
    .trackApplicationLifecycleEvents(true)
    .flushInterval(10)
    .flushAt(20)
    .apiHost("us-east-1.hightouch-events.com/v1")
```

### Typed and Untyped Event Methods

Most event methods have two variants:
- **Typed** (`Codable`): `track(name:properties:)` where properties conforms to `Codable`
- **Untyped** (`[String: Any]`): `track(name:properties:)` with a dictionary

Both are defined in `Events.swift`.

### Objective-C Compatibility

ObjC wrappers live in `Sources/Hightouch/ObjC/`. The main class is `HTAnalytics` (mapped from `ObjCAnalytics`). ObjC support is excluded on Linux (`#if !os(Linux)`).

### Platform Conditionals

The codebase uses extensive `#if os(...)` conditionals:
- `#if os(iOS) || os(tvOS)` — UIKit lifecycle
- `#if os(watchOS)` — WatchKit lifecycle
- `#if os(macOS)` — AppKit lifecycle
- `#if os(Linux)` — `FoundationNetworking` import, no lifecycle events yet
- `#if !os(Linux)` — ObjC compatibility, URL protocol mocks in tests

### Default API Hosts

```swift
// Both API and CDN default to the same host:
"us-east-1.hightouch-events.com/v1"
```

Configurable via `Configuration.apiHost(_:)` and `Configuration.cdnHost(_:)`.

### Testing Patterns

- **`OutputReaderPlugin`**: An `.after` plugin that captures the last event for assertions. Defined in `Tests/Hightouch-Tests/Support/TestUtilities.swift`.
- **`waitUntilStarted(analytics:)`**: Spins the run loop until the `StartupQueue` reports `running == true`. Required before asserting on events.
- **`hardReset(doYouKnowHowToUseThis:)`**: Clears all stored events and user defaults for a given write key. Used in tests that need a clean slate.
- **Write key isolation**: Tests that interact with storage should use unique write keys to avoid collisions with other tests.
- **Linux test discovery**: Tests on Linux require `--enable-test-discovery` flag. `LinuxMain.swift` and `XCTestManifests.swift` exist but are ignored when test discovery is enabled.

---

## Common Tasks

### Adding a New Plugin

1. Create a new Swift file under `Sources/Hightouch/Plugins/`
2. Implement the `Plugin`, `EventPlugin`, or `DestinationPlugin` protocol
3. Choose the appropriate `PluginType` (`.before`, `.enrichment`, `.destination`, `.after`, `.utility`)
4. Register it via `analytics.add(plugin: myPlugin)`

Example:

```swift
class MyPlugin: EventPlugin {
    let type: PluginType = .enrichment
    var analytics: Analytics?

    func track(event: TrackEvent) -> TrackEvent? {
        var modified = TrackEvent(existing: event)
        // modify the event...
        return modified
    }
}
```

### Adding a New Flush Policy

1. Implement the `FlushPolicy` protocol
2. Register via `Configuration.flushPolicies([...])` or `analytics.add(flushPolicy:)`

### Adding a New Event Type Property

Event types are structs in `Types.swift` conforming to `RawEvent`. To add a field:
1. Add the property to the relevant struct (e.g., `TrackEvent`)
2. Ensure it's included in the `init(existing:)` copy constructor
3. Update any test assertions

### Writing Tests

```swift
func testMyFeature() {
    let analytics = Analytics(configuration: Configuration(writeKey: "test"))
    let outputReader = OutputReaderPlugin()
    analytics.add(plugin: outputReader)

    waitUntilStarted(analytics: analytics)

    analytics.track(name: "my event")

    let event: TrackEvent? = outputReader.lastEvent as? TrackEvent
    XCTAssertEqual(event?.event, "my event")
}
```

---

## Important Files Reference

| File | Purpose |
|------|---------|
| `Package.swift` | SPM package manifest (targets, dependencies, platforms) |
| `Sources/Hightouch/Version.swift` | SDK version string (auto-generated, do not edit) |
| `Sources/Hightouch/Analytics.swift` | Core `Analytics` class |
| `Sources/Hightouch/Configuration.swift` | SDK configuration with fluent builder API |
| `Sources/Hightouch/Events.swift` | Public event methods (track, identify, screen, group, alias) |
| `Sources/Hightouch/Plugins.swift` | Plugin protocols and Analytics plugin management |
| `Sources/Hightouch/Plugins/SegmentDestination.swift` | Built-in destination that uploads events to Hightouch |
| `Sources/Hightouch/Utilities/HTTPClient.swift` | HTTP networking (batch upload, settings fetch) |
| `Sources/Hightouch/Utilities/Storage.swift` | Persistence layer (file events + UserDefaults) |
| `Tests/Hightouch-Tests/Support/TestUtilities.swift` | Test helpers: mock plugins, `waitUntilStarted`, `OutputReaderPlugin` |
| `.github/workflows/swift.yml` | CI workflow |
| `release.sh` | Release automation script |
| `build.sh` | XCFramework build script |

---

## Quick Reference

| Task | Command |
|------|---------|
| Build | `swift build` |
| Test (macOS) | `swift test` |
| Test (Linux) | `swift test --enable-test-discovery` |
| Test specific class | `swift test --filter Analytics_Tests` |
| Test specific method | `swift test --filter Analytics_Tests/testTrack` |
| Show dependencies | `swift package show-dependencies` |
| Check for updates | `swift package update --dry-run` |
| Update dependencies | `swift package update` |
| Clean build | `swift package clean` |
| Full clean + reset | `swift package reset` |
| Resolve dependencies | `swift package resolve` |
| iOS simulator test | `xcodebuild -scheme Hightouch test -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15'` |

---

## Common Issues

### Linux Compatibility

- Linux requires `import FoundationNetworking` for `URLSession` and related types.
- ObjC interop (`@objc`, `NSObject`) is not available on Linux. All ObjC code is gated behind `#if !os(Linux)`.
- `UserDefaults` on Linux: setting a key's value to `nil` causes a deadlock — use `removeObject(forKey:)` instead.
- `XCTExpectFailure` is not available on Linux. Tests using it are gated with `#if !os(Linux)`.

### Installing Swift on Linux

Swift is not bundled with most Linux distributions. To install:

```bash
# Check your Ubuntu version
lsb_release -sir

# Download the appropriate Swift release (match Ubuntu version)
# For Ubuntu 24.04:
curl -sL -o /tmp/swift.tar.gz \
  "https://download.swift.org/swift-5.10.1-release/ubuntu2404/swift-5.10.1-RELEASE/swift-5.10.1-RELEASE-ubuntu24.04.tar.gz"

# For Ubuntu 22.04:
curl -sL -o /tmp/swift.tar.gz \
  "https://download.swift.org/swift-5.10.1-release/ubuntu2204/swift-5.10.1-RELEASE/swift-5.10.1-RELEASE-ubuntu22.04.tar.gz"

# Extract and add to PATH
mkdir -p ~/swift-toolchain
tar -xzf /tmp/swift.tar.gz -C ~/swift-toolchain
export PATH="$HOME/swift-toolchain/swift-5.10.1-RELEASE-ubuntu$(lsb_release -sr)/usr/bin:$PATH"

# Install required system libraries
sudo apt-get install -y libncurses6 libcurl4 libxml2
```

### CI Linux Failure: Swift Version Not Available for Ubuntu

The CI uses `sersoft-gmbh/swifty-linux-action@v3` with `release-version: "5.7.2"`. When GitHub upgrades the `ubuntu-latest` runner, Swift 5.7.2 may not have a build for the new Ubuntu version (e.g., Swift 5.7.2 was never released for Ubuntu 24.04). Fix by updating `.github/workflows/swift.yml`:

```yaml
- uses: sersoft-gmbh/swifty-linux-action@v3
  with:
    release-version: "5.10.1"   # Use a version that supports the current ubuntu-latest
```

### CI iOS Failure: Bundle Instance Error

The iOS test job may fail with `Failed to create a bundle instance`. This is typically a simulator infrastructure flake, not a code issue. Re-running the job usually resolves it.

### Test Isolation

Tests share the same `UserDefaults` suite (`com.hightouch.storage.<writeKey>`). If a test modifies state, either:
- Use a unique write key for that test
- Call `storage.hardReset(doYouKnowHowToUseThis: true)` to clear state
- Call `UserDefaults.standard.removePersistentDomain(forName:)` before the test

### Startup Timing

The SDK fetches settings asynchronously on startup. In tests, always call `waitUntilStarted(analytics:)` before making assertions to ensure the startup queue has drained. Without this, events may be queued rather than processed.

### Event File Handling

Event files are written incrementally as JSON arrays. A file is "finished" (gets `.temp` extension) when:
- It exceeds 475KB
- `flush()` is called
- The event file list is enumerated

Only `.temp` files are eligible for upload. In-progress files without the `.temp` extension are not sent.
