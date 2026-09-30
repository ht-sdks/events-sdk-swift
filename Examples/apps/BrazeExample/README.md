# BrazeExample

Manual test app for the HightouchBraze plugin.

## Setup

1. Open `BrazeExample.xcworkspace` (the workspace, not the project alone).
2. In `BrazeExample/AppDelegate.swift`, replace `BRAZE_API_KEY` and `HT_WRITE_KEY` with a Braze SDK API key and a Hightouch write key.
3. Run the BrazeExample scheme from Xcode.

`perOrder` at the top of `AppDelegate.swift` defaults to `false` (one Braze purchase per product). Set it to `true` and relaunch to log one purchase per order.

## Checking results

This sandbox has no Event User Log. Confirm attributes, custom events, and purchases on the Braze user profile, and watch the Xcode console.
