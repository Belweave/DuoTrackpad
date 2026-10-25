# Duo Trackpad

Use your iPhone as a full-screen trackpad for your Mac. Built for iPhone Duo, with pointer control, scrolling, dragging, and shortcuts for everyday Mac gestures.

**Early beta · Apple Silicon · macOS 14+ · iPhone app required**

## Get started

1. Download **DuoReceiver-0.1.0-arm64.dmg** from [Releases](https://github.com/Belweave/DuoTrackpad/releases).
2. Open the DMG. Drag **Duo Receiver** into **Applications**, then open it.
3. Allow **Accessibility** and **Local Network** access when asked.
4. Open Duo Trackpad on your iPhone. Keep both devices on the same Wi-Fi network.
5. Select your Mac and enter the pairing code shown by Duo Receiver.

Pair once. The apps remember each other and reconnect on later launches. The iPhone app is currently an invitation-only TestFlight beta; downloading the Mac receiver alone is not enough.

[Setup and troubleshooting →](docs/SETUP.md)

## Everyday gestures

| Gesture | Action |
| --- | --- |
| Move one finger / tap | Move the pointer / click |
| Hold, or double-tap and hold | Drag |
| Two-finger tap / slide | Right-click / scroll |
| Two-finger pinch | Zoom using the app’s keyboard shortcuts |
| Three- or four-finger swipe | Mission Control, App Exposé, or switch desktop |
| Four-finger tap | Open connection settings and Mac controls |

Adjust pointer speed, acceleration, scrolling, and haptics in the iPhone settings sheet. [Full gesture guide →](docs/GESTURES.md)

## What to expect

- The whole available iPhone screen is the trackpad, open or closed. iOS still handles its edge gestures and hardware occlusions.
- Input travels directly over your local network. No account, cloud relay, or analytics service is required.
- This is an early beta. Gestures use mouse events and app shortcuts; Force Click and every native Magic Trackpad gesture are not supported.
- Pair only on a trusted local network. The custom pairing protocol has not had an independent security audit. [Security and privacy →](SECURITY.md)

## Build or contribute

The apps use Swift, SwiftUI, and Apple’s frameworks, with no third-party runtime dependencies. Use **Xcode 27.1 (27A9275)** and the iOS 27.1 SDK.

```sh
./scripts/build.sh
swift test -c release --jobs 2
```

[Development](docs/DEVELOPMENT.md) · [Releases](docs/RELEASING.md) · [iPhone TestFlight](docs/TESTFLIGHT.md) · [Protocol](docs/PROTOCOL.md) · [Performance](docs/PERFORMANCE.md) · [Verification](docs/VERIFICATION.md)

[Changelog](CHANGELOG.md) · [MIT license](LICENSE). An independent project by Belweave; not affiliated with Apple.
