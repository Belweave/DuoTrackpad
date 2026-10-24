#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DUO_TOOLCHAIN="$(xcodebuild -version)"
if [[ "$DUO_TOOLCHAIN" != *"Xcode 27.1"* || "$DUO_TOOLCHAIN" != *"27A9275"* ]]; then
    printf '%s\n' "This checkout currently requires Xcode 27.1 RC (27A9275)." "$DUO_TOOLCHAIN" "Select the requested toolchain explicitly; no older-beta fallback is allowed."
    exit 1
fi
DUO_JOBS="${DUO_BUILD_JOBS:-2}"
if ! [[ "$DUO_JOBS" =~ ^[1-4]$ ]]; then
    printf '%s\n' 'DUO_BUILD_JOBS must be between 1 and 4.'
    exit 1
fi
mkdir -p build
python3 scripts/generate-project.py
xcodebuild -project DuoTrackpad.xcodeproj -scheme DuoTrackpad \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
    -jobs "$DUO_JOBS" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build > build/ios-build.log 2>&1
printf '%s\n' 'iPhone simulator app built.'
xcodebuild -project DuoTrackpad.xcodeproj -scheme DuoReceiver \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData \
    -jobs "$DUO_JOBS" CODE_SIGN_IDENTITY="${DUO_CODE_SIGN_IDENTITY:-Apple Development}" build > build/macos-build.log 2>&1
bash scripts/verify-signing.sh build/DerivedData/Build/Products/Debug/DuoReceiver.app
printf '%s\n' 'Mac receiver built.'
printf '%s\n' 'Open build/DerivedData/Build/Products/Debug/DuoReceiver.app to pair.'
