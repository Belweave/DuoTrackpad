# Build Duo Trackpad

## Requirements

- macOS with **Xcode 27.1 (27A9275)** selected by `xcode-select`.
- The iOS 27.1 SDK for the iPhone Duo layout.
- Python 3.11+ and an Apple Development signing identity for a runnable receiver.

No third-party runtime dependencies. The Xcode project is generated with Python.

## Build and run

```sh
./scripts/build.sh
open build/DerivedData/Build/Products/Debug/DuoReceiver.app
```

The script builds the iPhone simulator app, then the receiver, with two jobs and disk-backed storage. Logs are in `build/`. `DUO_BUILD_JOBS` accepts 1–4.

Or open `DuoTrackpad.xcodeproj` and run **DuoReceiver → My Mac** and **DuoTrackpad → iPhone Duo**. Select your signing team for a physical iPhone.

Project generation detects the team when exactly one Apple Development identity is installed. Set `DUO_DEVELOPMENT_TEAM` otherwise. `DUO_CODE_SIGN_IDENTITY` chooses the receiver identity for `scripts/build.sh`.

Do not use ad-hoc signing for everyday receiver installs. macOS ties Accessibility to signing identity; changing it can leave a stale enabled-looking entry.

## Check changes

```sh
swift test -c release --jobs 2
python3 -m unittest discover -s tests-release -v
bash scripts/ci.sh
```

CI runs core tests, release-tool tests, and unsigned Release builds of both apps. Pull requests get no signing credentials. The microbenchmark is opt-in; see [performance](PERFORMANCE.md).

If installed, the [iPhone Duo skill](https://github.com/Belweave/iphone-duo-design) provides optional linting: `python3 <skill-folder>/scripts/duo-lint iOS Shared`. It is not a build dependency.

## Project map

| Folder | Purpose |
| --- | --- |
| `iOS/` | Full-screen touch surface, connection UI, discovery |
| `macOS/` | Receiver, permissions, menu bar, event injection |
| `Shared/` | Gestures, framing, encrypted pairing, transport |
| `Tests/` | Swift unit and localhost integration tests |
| `scripts/` | Build, packaging, notarization, verification |
| `release/` | Version, DMG artwork, settings, release notes |

## Versions and other hosts

`release/receiver.json` owns the receiver version and build. The first distribution is **0.1.0 (1)**. The uploaded iPhone beta remains **1.0 (1)**. These are independent version streams; never reset an uploaded iPhone build number. Regenerate the project after changing metadata.

Windows/Linux receivers are not implemented. A new host must implement the [wire protocol](PROTOCOL.md), pointer/scroll/button input, MacAction equivalents, and zoom/rotation mappings or explicit unsupported responses.
