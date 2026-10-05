# Events SDK Swift

## Installing the SDK

This SDK is available through [**Swift Package Manager (SPM)**](https://www.swift.org/package-manager/).

### [Option 1] Xcode

1. Xcode 12: **File > Swift Packages > Add Package Dependency**
2. Xcode 13: **File > Add Packages…**
3. Search for `git@github.com:ht-sdks/events-sdk-swift.git`
4. Click **Add Package**.

### [Option 2] Package.swift

Add `git@github.com:ht-sdks/events-sdk-swift.git` to your package.swift file

### Braze destination

Select the optional `HightouchBraze` product from this same package to forward
Hightouch events to the Braze SDK. In a Swift package target, add
`.product(name: "HightouchBraze", package: "events-sdk-swift")` alongside your
`Hightouch` dependency.

```swift
import Hightouch
import HightouchBraze

analytics.add(plugin: BrazeDestination(
    apiKey: "BRAZE_SDK_API_KEY",
    endpoint: "sdk.iad-03.braze.com"
))
```

The adapter supports iOS, tvOS, Mac Catalyst, and visionOS. BrazeKit is linked only
by the `HightouchBraze` target on those platforms; SwiftPM may still resolve and
download Braze dependencies for consumers of other products. Apps choose whether
to add `BrazeUI` for in-app message and Content Card presentation.

The package requires Swift tools 5.9 or later and tvOS 12 or later. Current Braze
18.x binaries require Xcode 26 or later; the supported Braze dependency range is
`12.0.0..<19.0.0`.

`HightouchBraze` is distributed as SwiftPM source and shares the SDK's release tags
and existing `release.sh` process. It does not require a separate repository or
publishing step, and is not included in the core SDK's XCFramework release assets.

## Example

For example, in a lifecycle method such as `didFinishLaunchingWithOptions` in iOS:

```swift
import Hightouch

// ...

  var analytics: Analytics? = nil

  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
          // Override point for customization after application launch.
          let configuration = Configuration(writeKey: "WRITE_KEY")
              .trackApplicationLifecycleEvents(true)
              .flushInterval(10)

          analytics = Analytics(configuration: configuration)
          analytics?.track(name:"test track event")
          analytics?.track(name: "track with traits", properties:[
            "key_1" : "value_1",
            "key_2" : "value_2"
          ])
          analytics?.screen(title: "home")
  }
```
