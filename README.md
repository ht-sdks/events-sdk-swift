# Events SDK Swift

## Installing the SDK

This SDK is available through [**Swift Package Manager (SPM)**](https://www.swift.org/package-manager/).

### [Option 1] Xcode

1. Xcode 12: **File > Swift Packages > Add Package Dependency**
2. Xcode 13: **File > Add Packages…**
3. Search for `git@github.com:ht-sdks/events-sdk-swift.git`
4. In **Dependency Rule**, select **Up to Next Major Version**, and enter `1.0.0` as the value.
5. Click **Add Package**.

### [Option 2] Package.swift

Add `git@github.com:ht-sdks/events-sdk-swift.git` to your package.swift file

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
