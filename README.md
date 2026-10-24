# Duo Trackpad

A native, full-screen iPhone trackpad and Apple Silicon Mac companion. Unfold iPhone Duo, place it beside your keyboard, and use its entire available touch surface to control your Mac.

The silver surface has no tappable chrome or dedicated button zones. The connection pill, center mark, and gesture hints pass touches through. The center mark and hints fade during use. System home/edge gestures and active hardware occlusions remain under iOS control.

## Run

Requires **Xcode 27.1 RC, build 27A9275**, with the iOS 27.1 SDK. Both targets are in `DuoTrackpad.xcodeproj`, with shared schemes. No external dependencies or accounts.

1. Open `DuoTrackpad.xcodeproj`. Select **DuoReceiver → My Mac**, then Run.
2. In the receiver, choose **Open Accessibility Settings**. Enable **Duo Receiver** in Privacy & Security → Accessibility. This is required by macOS to post mouse events.
3. Select **DuoTrackpad → iPhone Duo** and Run. For a physical iPhone, select your signing team in the iOS target first.
4. Keep both devices on the same LAN. Allow Local Network access when iOS/macOS asks.
5. Tap anywhere on the phone, select your Mac, and enter its eight-digit pairing code. The phone reports if the Mac still needs Accessibility access.
6. Unfold the phone in Device Hub using **Open**. The same app also works closed and partially open.

If Bonjour discovery is unavailable, expand **Connect by IP address** on the phone and enter the address shown in the receiver. The receiver listens on TCP port **48571**. A firewall must permit incoming connections to the receiver; guest Wi-Fi/client isolation may prevent devices from talking.

For an iOS simulator running on the same Mac, use **127.0.0.1** in the direct-address field. This environment's simulator paired successfully over loopback; its connection to the Mac's LAN address stalled, and Bonjour did not list the receiver. Physical-device LAN discovery and routing still need verification.

To build both apps locally with bounded concurrency and disk-backed storage:

```sh
./scripts/build.sh
open build/DerivedData/Build/Products/Debug/DuoReceiver.app
```

The simulator app is at `build/DerivedData/Build/Products/Debug-iphonesimulator/DuoTrackpad.app`. The build script checks the requested Xcode build and runs the targets sequentially with two jobs. Logs live in `build/`. Update the toolchain guard deliberately when moving to a newer stable Xcode.

The Mac receiver requires an installed **Apple Development** signing identity (or set `DUO_CODE_SIGN_IDENTITY` to an appropriate distribution identity). Project generation detects the team when exactly one development identity is installed; otherwise set `DUO_DEVELOPMENT_TEAM` or select a team in Xcode. The build checks its signature before launch. Do not use `CODE_SIGN_IDENTITY=-`: ad-hoc signatures change the app's privacy identity on each rebuild, leaving an enabled-looking Accessibility entry that macOS no longer accepts. If you previously granted access to an ad-hoc build, remove that stale DuoReceiver entry and add the certificate-signed build once; subsequent builds with the same identity retain the permission. On macOS 27 this Settings page is called **Device Control and Data Access**.

## Gestures

| Gesture | Result |
| --- | --- |
| Slide / tap one finger | Pointer / click, including double-click |
| Double-tap and hold, or hold 0.38 seconds | Drag; lift to release |
| Tap two fingers | Secondary click (280 ms recognition window for double-tap) |
| Slide two fingers | Phased horizontal/vertical pixel scrolling with momentum |
| Pinch two fingers | App zoom shortcuts (Command + / −) |
| Double-tap two fingers | Reset zoom (Command 0), an equivalent rather than native Smart Zoom |
| Rotate two fingers | App Rotate Left/Right menu commands, when exposed; discrete rotation |
| Tap three fingers | Look up (Control Command D) |
| Swipe three or four fingers up / down | Mission Control / App Exposé |
| Swipe three or four fingers sideways | Switch desktop/full-screen Space |
| Spread / pinch four fingers | Show Desktop / Apps |
| Swipe left with two fingers from right edge | Notification Center via its accessible menu-bar control |
| Tap four fingers | Connection, feel settings, and Mac controls |

Enable **Three-finger drag** to replace three-finger swipe/lookup behavior with dragging. Four-finger controls and swipes remain available. Settings include pointer speed, smooth pointer acceleration, scroll speed, natural scrolling, and click haptics. A VoiceOver custom action opens settings. Mac controls also have explicit buttons in the connection sheet.

This app sends mouse events and app/system commands, not a virtual Apple multitouch HID device. Keyboard equivalents follow the Mac's configured shortcuts. Zoom/rotation depend on the foreground app; rotation uses exposed English Rotate Left/Right menu titles. Notification Center depends on its accessible menu-bar control. Hardware pressure, Force Click, universal native magnify/rotate events, native Smart Zoom, and physical-trackpad haptics are not reproduced. See Apple's [gesture list](https://support.apple.com/en-la/102482) and documented [CGEvent constructors](https://developer.apple.com/documentation/coregraphics/cgevent) for the distinction.

## Responsiveness

A bounded ingress mailbox and a fixed 64-slot transport FIFO preserve button/gesture ordering and coalesce adjacent movement. Enqueue/pop are O(1) with uniquely owned storage. Input never waits for SwiftUI rendering or a display timer. TCP disables Nagle; crypto and event injection run on the interactive transport queue. The streaming parser retains one incomplete frame and does linear work in the received bytes, which cannot be O(1) for arbitrary input sizes.

The receiver caches permission and display topology, avoiding permission IPC and display enumeration for every mouse sample. Touch rings reuse layers and a precomputed path. The receiver generates momentum at 120 Hz only while scrolling is coasting; a new touch, pause, or disconnect cancels it. Pointer acceleration preserves precision at slow speeds and increases travel at higher finger velocities; turn it off for a linear response.

The connection sheet and receiver show authenticated **network round-trip latency**, not touch-to-display latency. Local release CPU benchmarks reduced input decode from 61.0 to 10.1 ns, encode from 119.1 to 50.8 ns, and 64-slot queue operations from 25.1 to 5.8 ns. These are component benchmarks, not physical Wi-Fi results. [Performance methodology](docs/PERFORMANCE.md) covers the limits. Instruments signposts `EncryptAndSubmit` and `ApplyInput` support further profiling.

## Layout on Duo

The viewport follows live container bounds. The surface extends to every edge, including the safe area, as required for full-screen input. Informational overlays use per-side safe areas and the live `UIView.reservedRegions(kind:)` API to avoid active fold/camera regions; touches in those reserved regions do not send pointer motion. No hard-coded Duo dimensions, orientation-driven layout, or `UIScreen.main` checks are used. Settings use a native navigation sheet with system bars.

Apple references: [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo), [Preparing your app](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo).

## Implementation and other hosts

- `iOS/`: full-screen UIKit touch surface, SwiftUI connection settings, Bonjour discovery.
- `Shared/`: platform-neutral input vocabulary, length framing, session cipher, Apple Network transport.
- `macOS/`: Bonjour listener, pairing/permission status, menu-bar UI, Core Graphics event injection.
- `Tests/`: framing/crypto validation and real localhost socket integration tests.
- `scripts/`: reproducible Xcode project and app icon generation; local build helper.

A Windows/Linux receiver can reuse the documented [wire protocol](docs/PROTOCOL.md) and implement its own mouse-event sink. Those platforms are extension points, not working receivers yet. The iOS app sends relative motion, scroll, and button operations rather than macOS-specific commands.

## Pairing

Pair once using the eight-digit code. Both apps save their long-lived X25519 private identity and authenticated peer identities in local, device-only Keychain storage. Future launches rediscover the remembered Bonjour service (or saved manual address) and reconnect automatically. Backgrounding releases input and closes the socket; returning to the foreground reconnects. Network failures retry with bounded backoff. An explicit Disconnect stops retries until Reconnect or another foreground session with connection desired. Forget on either device revokes trust and requires pairing again.

Initial pairing binds both identities and ephemeral public keys into a code-authenticated HKDF transcript. Resumption combines fresh ephemeral X25519 and the saved identity agreement; the displayed code is no longer required. The client pins the remembered Mac identity and the receiver accepts resumption only from remembered identities. Every connection gets fresh directional ChaCha20-Poly1305 keys and replay counters. Codes rotate after disconnect and expire after five idle minutes. Five failed attempts per minute temporarily block pairing. One client is accepted at a time.

**Upgrade:** the earlier build did not store identities. Pair once after installing this update to establish remembered trust. The handshake is version 2; both app builds must be updated together.

The initial short-code handshake is still a custom LAN prototype, not an audited PAKE. An active attacker can attempt offline code guesses against a handshake they establish. Production distribution needs an audited PAKE or high-entropy QR flow. Do not expose the listener to the internet.

## Verification

```sh
swift test --build-system native --jobs 2 --no-parallel
bash scripts/verify-signing.sh build/DerivedData/Build/Products/Debug/DuoReceiver.app
python3 /Users/preetham/.agents/skills/iphone-duo-design/scripts/duo-lint iOS Shared
```

See [verification notes](docs/VERIFICATION.md) for the tested scope and outstanding physical-device checks. `--build-system native` currently keeps SwiftPM compilation bounded; Xcode 27.1 reports a deprecation warning for it.

## Distribution

See [TestFlight releases](docs/TESTFLIGHT.md) for archiving, App Store signing, privacy declarations, and upload verification. The iOS beta needs the separately running macOS receiver. This prototype has no production App Store listing yet.
