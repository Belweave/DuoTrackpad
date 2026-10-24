# Verification — 2026-10-24

Toolchain checked before building: `/Applications/Xcode.app/Contents/Developer`, Xcode **27.1**, build **27A9275**. iOS Simulator SDK **27.1**, macOS SDK **27.0**. Local, sequential app builds used two jobs and `build/DerivedData`; no RAM-backed build storage.

## Passed

- iOS app builds for the arm64 iPhone Duo simulator; Apple Silicon macOS companion builds with ad-hoc signing.
- Duo lint scans all five iOS/shared Swift files: **zero findings**.
- **Eight tests pass**: fragmented/multiple frames, oversize rejection, every input kind, malformed/non-finite input, key agreement and directional encryption, replay/tamper/wrong-code rejection, real TCP input ordering/aggregation/heartbeat, and failed authentication over a real socket.
- The actual iOS app pairs with the actual Mac receiver via **127.0.0.1:48571**. Both apps show the established session; authenticated ping/pong updates round-trip latency. This is simulator loopback, not Wi-Fi or hardware latency.
- The phone receives and displays the Mac's missing Accessibility permission. The session stays connected while that permission is absent; the receiver suppresses mouse injection until permission exists.
- Failed socket attempts rotate the displayed pairing code. The selectable code text explicitly gets a new SwiftUI identity when the code changes, avoiding a stale displayed code.
- Device Hub's Closed, Partially Open, and Open controls were used on a dedicated **Duo Trackpad QA** simulator, without taking over the other active project's simulator.
- Closed portrait/landscape and open layouts render edge to edge. A safe-area strip was removed. Overlays pass touches through to the input surface.
- In the partially open pose, the informational cluster and hints move to the side of the active division region. The connection survives close/open and rotation transitions.
- Connection settings are reachable through the trackpad's VoiceOver custom action. Address and code fields, keyboard dismissal, connect state, handshake timeout, and automatic sheet dismissal after pairing were exercised.

Saved runtime captures are in [screenshots](screenshots/). They include permission instructions because Accessibility has not been enabled for this development build.

## Remaining hardware/release checks

- **Actual macOS cursor movement, click delivery, drag release, multi-monitor crossing, and scroll feel have not been verified through the OS.** The build still needs the user's Accessibility grant. Event injection is implemented with Core Graphics; real socket delivery is tested separately.
- Physical Duo touch latency, haptics, Wi-Fi discovery/routing, battery use, long-session reliability, and palm rejection need hardware testing. There is no claimed end-to-end latency measurement.
- Bonjour discovery did not list the receiver in this simulator environment. The Mac's LAN-address socket stalled before reaching the listener. Loopback worked. Repeat Bonjour and direct-address pairing on a physical phone and the intended LAN.
- Split View on both sides, pinned PiP, every partial-fold angle, right-to-left localization, and the full Dynamic Type/accessibility matrix remain untested.
- Pinch/zoom, inertial scrolling, workspace gestures, Force Touch, and Bluetooth HID emulation are not implemented. Windows/Linux receivers are documented extension points.
- Production distribution requires signing/notarization, a reviewed pairing design (see README), and device testing.

## Tooling notes

T3's Device panel was opened for the dedicated simulator. The agent-device fold command could not verify the hinge angle with this installed CoreDevice toolchain: `CoreDevice reported no hinge angle sample: Unknown option '--device'`. Pose checks therefore used the installed **Device Hub** buttons, as prescribed by the Duo skill. Device-panel screenshots also failed for the additional simulator; evidence was captured with `simctl io ... screenshot --display=1/3` after observing the active display in Device Hub.

SwiftPM's native build system was used with `--jobs 2 --no-parallel`; Xcode 27.1 emits a deprecation warning for that selection. App builds emit the expected "Metadata extraction skipped, no AppIntents.framework dependency found" message; the apps do not use App Intents.

## 2026-10-24 pairing, gesture, and performance revision

- Xcode 27.1 RC 27A9275 verified; Apple Development signature retained for receiver. Local Xcode builds use two build jobs and Swift `-j2`.
- Keychain identity/peer records survive store recreation; forgetting removes trust while preserving the local identity. Test service uses a unique UUID and deletes only its own fixture records.
- Real localhost sockets prove initial code pairing, resumed pairing after rotating the host code, and rejection of revoked/unrecognized saved peers. Wrong-code, replay, tampering, framing, and ordering coverage remains.
- Gesture regressions cover immediate pointer motion, phase ordering, release on cancellation, scroll finger-lift suppression, small scroll versus secondary click, pinch versus scroll, three-finger commands/drag, and sequential four-finger controls. Pointer tuning tests verify precision and linear mode.
- Native receiver screenshots showed an upright code before and after local socket-disconnect rotation. The replaced SwiftUI selectable-text path is now an AppKit NSTextField without implicit animations. The user's original intermittent glyph flip was not reproduced in the old binary during this run.
- Duo lint reports zero findings. Physical iPhone Duo product iPhone19,4 / V68AP was verified with localNetwork transport; the 13 Pro Max was not targeted.
- No simulator devices were available in the app-owned device catalog; opening the stale Duo simulator ID returned an explicit “No device … on host local” error. Platform tools were used for physical builds and deployment.
- Local CPU benchmarks are documented in PERFORMANCE.md. No physical touch-to-display or congested Wi-Fi latency measurement was performed. Native hardware Force Click, continuous OS magnify/rotate events, and true Smart Zoom remain outside supported event synthesis; app-command equivalents are labeled in the UI and README.
- The older build stored no identity, so this upgrade requires one initial code pairing. Physical repeated-launch auto-reconnect and subjective gesture feel need confirmation after that pairing; secure resumption itself is covered by socket and persistence tests.

Final validation: Debug and Release suites each report 40 tests, zero failures, one opt-in benchmark skipped (39 executed successfully). Both Debug and optimized Release device/receiver builds succeed. Certificate signature verification succeeds. Optimized Release builds were installed on the physical Duo via localNetwork and launched; the Release receiver is running and visibly retains Accessibility access. The generated home-screen icon remains included. Deployment records: build/duo-fixes-install.json and build/duo-fixes-launch.json.
