#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/check-toolchain.sh
mkdir -p build
python3 -m unittest discover -s tests-release -v
swift test -c release --jobs 2
DUO_DEVELOPMENT_TEAM=6D56G8D849 python3 scripts/generate-project.py
xcodebuild -project DuoTrackpad.xcodeproj -scheme DuoReceiver -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath build/CIDerivedData \
    -jobs 2 CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -j2' build > build/ci-receiver.log 2>&1
xcodebuild -project DuoTrackpad.xcodeproj -scheme DuoTrackpad -configuration Release \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath build/CIDerivedData \
    -jobs 2 CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='$(inherited) -j2' build > build/ci-ios.log 2>&1
printf '%s\n' 'Core tests, release checks, and both app builds passed.'
