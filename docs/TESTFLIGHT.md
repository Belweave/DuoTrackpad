# TestFlight releases

Duo Trackpad's iOS bundle identifier is `app.duotrackpad.ios`. The macOS receiver is a separate app (`app.duotrackpad.receiver`) distributed locally; its Accessibility event injection is not packaged as an iOS TestFlight companion.

Use the requested Xcode 27.1 RC (27A9275), a paid Apple Developer team, and an App Store Connect app record matching the iOS bundle identifier. The generated project uses the sole installed development identity's team, or `DUO_DEVELOPMENT_TEAM`. Version 1.0, build 1 is the first candidate. Check App Store Connect and increment `CURRENT_PROJECT_VERSION` for every later upload; preserve that value in `scripts/generate-project.py` when regenerating the project.

```sh
python3 scripts/generate-project.py
swift test -c release --jobs 2
xcodebuild -project DuoTrackpad.xcodeproj -scheme DuoTrackpad \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/TestFlight/DuoTrackpad-1.0-1.xcarchive \
  -derivedDataPath build/DerivedData -jobs 2 \
  OTHER_SWIFT_FLAGS='$(inherited) -j2' -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/TestFlight/DuoTrackpad-1.0-1.xcarchive \
  -exportOptionsPlist fastlane/ExportOptions.plist \
  -exportPath build/TestFlight/export -allowProvisioningUpdates
```

The export step uses App Store Connect distribution signing. A development-signed device build is not a TestFlight upload. Upload the archive through Xcode Organizer's Distribute App flow, or use installed fastlane `pilot` with authentication configured outside the repository. Check whether Apple already received a build before retrying an interrupted upload. After processing, enable it for an internal TestFlight group; external testing requires Beta App Review and additional metadata.

The archive includes the generated 1024-pixel icon and `PrivacyInfo.xcprivacy`. The manifest declares local settings (`CA92.1`) and elapsed-time/timer measurement (`35F9.1`), no tracking, and no collected analytics data. Touch sample timestamps remain on the sender; heartbeat packets transmit elapsed connection intervals, not system boot-relative timestamps. Input and pairing data go directly to the paired Mac on the local network.

Encryption uses Apple's CryptoKit and Security frameworks. `ITSAppUsesNonExemptEncryption` is false under Apple's exemption for encryption provided by its operating system; revisit this declaration if cryptographic implementations or distribution requirements change. See [Apple's export-compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/).

Keep all signing credentials, local authentication files, archives, `.ipa` files, and distribution logs outside Git. Repository ignore rules exclude them. Upload success, processing completion, and tester availability are separate states; record the actual state rather than treating a local archive as a release.
