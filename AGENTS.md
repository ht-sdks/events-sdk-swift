# Agent Instructions

This file provides instructions for AI agents working on this Swift SDK.

## Project Overview

- **Language**: Swift (swift-tools-version 5.7+)
- **Package Manager**: Swift Package Manager (SPM)
- **Testing**: XCTest
- **CI**: GitHub Actions (Xcode 15.4 on macOS 14, Swift 5.10.1 on Linux)
- **State Management**: [Sovran-Swift](https://github.com/segmentio/Sovran-Swift.git) (from 1.1.0)
- **Product**: `Hightouch` — the Hightouch Events SDK for Apple platforms and Linux

### Supported Platforms

| Platform | Minimum Version |
|----------|----------------|
| macOS    | 10.15          |
| iOS      | 13.0           |
| tvOS     | 11.0           |
| watchOS  | 7.1            |
| Linux    | (Swift 5.10.1) |

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

## CI/CD

### CI Workflow (`.github/workflows/swift.yml`)

Runs on push/PR to `main`. Jobs:

| Job | Runner | What it does |
|-----|--------|-------------|
| `build_and_test_spm_mac` | macOS 14, Xcode 15.4 | `swift build` + `swift test` |
| `build_and_test_spm_linux` | Ubuntu, Swift 5.10.1 | `swift build` + `swift test --enable-test-discovery` |
| `build_and_test_ios` | macOS 14, Xcode 15.4 | `xcodebuild test` on iPhone 15 simulator |
| `build_and_test_tvos` | macOS 14, Xcode 15.4 | `xcodebuild test` on Apple TV simulator |
| `build_and_test_watchos` | macOS 14, Xcode 15.4 | `xcodebuild test` on Apple Watch Series 9 simulator |
| `build_and_test_examples` | macOS 14, Xcode 15.4 | Builds BasicExample, ObjCExample, UIKitExample, WeatherWidget, Mac Catalyst |

### Release Workflow (`.github/workflows/xcframework-release.yml`)

Builds and uploads XCFramework zip assets on tag push (tags like `1.2.3`, no `v` prefix). Also supports manual `workflow_dispatch` with a `tag` input and optional `dry_run` (defaults to `true`).

| Trigger             | Upload behavior                              |
| ------------------- | -------------------------------------------- |
| Tag push            | Always uploads to release                    |
| `workflow_dispatch` | Uploads to release only when `dry_run=false` |

Runs on macOS 14 with Xcode 15.4.

### Slack Notification (`.github/workflows/tagged-release.yml`)

Triggered by tags matching `v[0-9]+.[0-9]+.[0-9]+`. Posts a notification to Slack.

---

## Releasing

Use `release.sh` to perform releases. The script:

1. Validates you are on the `main` branch
2. Validates the new version is greater than the current version
3. Updates `Sources/Hightouch/Version.swift` with the new version
4. Commits the change and pushes
5. Creates a GitHub Release with a changelog (commits since last tag)

XCFramework assets are **not** built locally. Pushing the release tag triggers [`.github/workflows/xcframework-release.yml`](.github/workflows/xcframework-release.yml), which builds and uploads `Hightouch.zip`, `Hightouch.sha256`, `Sovran.zip`, and `Sovran.sha256` (~15–30 min).

```bash
./release.sh 1.2.3
```

### Required Tools for Releasing

- `gh` (GitHub CLI): `brew install gh` — must be authenticated (`gh auth login`)

### XCFramework CI Workflow

- **Automatic:** tag push runs build + upload
- **Retry:** Re-run a failed workflow from Actions
- **Manual dispatch:** Mainly for testing/backfill. Actions → **XCFramework Release** → Run workflow with `tag` set; default `dry_run=true` skips GitHub Release upload

Do **not** run `scripts/build-xcframeworks.sh` locally — CI uses a pinned Xcode 15.4 environment.

### Version File

`Sources/Hightouch/Version.swift` is **auto-generated** by `release.sh`. Do NOT edit it by hand. It contains:

```swift
internal let __hightouch_version = "X.Y.Z"
```

This version string is used in:

- `Analytics.version()` — public API
- HTTP `User-Agent` header: `analytics-ios/<version>`
- Context payload: `library.version`

---

## Testing Patterns

- **`OutputReaderPlugin`**: An `.after` plugin that captures the last event for assertions. Defined in `Tests/Hightouch-Tests/Support/TestUtilities.swift`.
- **`waitUntilStarted(analytics:)`**: Spins the run loop until the `StartupQueue` reports `running == true`. Required before asserting on events.
- **`hardReset(doYouKnowHowToUseThis:)`**: Clears all stored events and user defaults for a given write key. Used in tests that need a clean slate.
- **Write key isolation**: Tests that interact with storage should use unique write keys to avoid collisions with other tests.
- **Linux test discovery**: Tests on Linux require `--enable-test-discovery` flag. `LinuxMain.swift` and `XCTestManifests.swift` exist but are ignored when test discovery is enabled.

Example test:

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

## Common Issues

### Linux Compatibility

- Linux requires `import FoundationNetworking` for `URLSession` and related types.
- ObjC interop (`@objc`, `NSObject`) is not available on Linux. All ObjC code is gated behind `#if !os(Linux)`.
- `UserDefaults` on Linux: setting a key's value to `nil` causes a deadlock — use `removeObject(forKey:)` instead.
- `XCTExpectFailure` is not available on Linux. Tests using it are gated with `#if !os(Linux)`.

### Test Isolation

Tests share the same `UserDefaults` suite (`com.hightouch.storage.<writeKey>`). If a test modifies state, either:

- Use a unique write key for that test
- Call `storage.hardReset(doYouKnowHowToUseThis: true)` to clear state
- Call `UserDefaults.standard.removePersistentDomain(forName:)` before the test

### Startup Timing

The SDK fetches settings asynchronously on startup. In tests, always call `waitUntilStarted(analytics:)` before making assertions to ensure the startup queue has drained. Without this, events may be queued rather than processed.
