#!/bin/bash
# Build and verify a complete Developer ID distribution. Never publishes a preview.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/check-toolchain.sh
DUO_MODE="${1:-release}"
[[ "$DUO_MODE" == release || "$DUO_MODE" == preview ]] || { echo 'Usage: release-macos.sh [release|preview]' >&2; exit 1; }
DUO_VERSION="$(python3 -c 'import json; print(json.load(open("release/receiver.json"))["version"])')"
DUO_TEAM="$(python3 -c 'import json; print(json.load(open("release/receiver.json"))["teamId"])')"
DUO_JOBS="${DUO_BUILD_JOBS:-2}"
[[ "$DUO_JOBS" =~ ^[1-4]$ ]] || { echo 'DUO_BUILD_JOBS must be between 1 and 4.' >&2; exit 1; }
DUO_OUTPUT="${DUO_RELEASE_DIR:-$PWD/build/receiver-$DUO_VERSION-$DUO_MODE}"
mkdir -p "$DUO_OUTPUT"
DUO_OUTPUT="$(cd "$DUO_OUTPUT" && pwd)"
DUO_PYTHON="${DUO_RELEASE_PYTHON:-$PWD/build/release-venv/bin/python3}"
"$DUO_PYTHON" -c 'import dmgbuild'
DUO_SIGNING=()
if [[ "$DUO_MODE" == release ]]; then
    : "${DUO_CODE_SIGN_IDENTITY:?Set a Developer ID Application identity or its certificate SHA-1.}"
    if [[ -z "${DUO_NOTARY_PROFILE:-}" ]]; then
        : "${ASC_PRIVATE_KEY_PATH:?App Store Connect private key path is required.}"
        : "${ASC_KEY_ID:?App Store Connect key ID is required.}"
        : "${ASC_ISSUER_ID:?App Store Connect issuer ID is required.}"
    fi
    DUO_SIGNING=("CODE_SIGN_IDENTITY=$DUO_CODE_SIGN_IDENTITY" "DEVELOPMENT_TEAM=$DUO_TEAM" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS=--timestamp)
else
    DUO_SIGNING=(CODE_SIGNING_ALLOWED=NO)
fi
DUO_DEVELOPMENT_TEAM="$DUO_TEAM" python3 scripts/generate-project.py
python3 scripts/release-candidate.py "$DUO_OUTPUT" "$DUO_MODE"
DUO_APP="$DUO_OUTPUT/Duo Receiver.app"
DUO_ZIP="$DUO_OUTPUT/DuoReceiver-$DUO_VERSION-arm64.zip"
if [[ ! -d "$DUO_APP" && -f "$DUO_ZIP" ]]; then ditto -x -k "$DUO_ZIP" "$DUO_OUTPUT"; fi
if [[ ! -d "$DUO_APP" ]]; then
if ! xcodebuild -project DuoTrackpad.xcodeproj -scheme DuoReceiver -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DUO_OUTPUT/DerivedData" \
    -jobs "$DUO_JOBS" OTHER_SWIFT_FLAGS='$(inherited) -j2' \
    "${DUO_SIGNING[@]}" build > "$DUO_OUTPUT/build.log" 2>&1; then
    tail -60 "$DUO_OUTPUT/build.log" >&2; exit 1
fi
    ditto "$DUO_OUTPUT/DerivedData/Build/Products/Release/DuoReceiver.app" "$DUO_APP"
fi
python3 scripts/verify-release.py app "$DUO_APP" "$DUO_MODE"
mkdir -p "$DUO_OUTPUT/art"
xcrun swift release/dmg/background.swift "$DUO_OUTPUT/art"
tiffutil -cathidpicheck "$DUO_OUTPUT/art/background.png" "$DUO_OUTPUT/art/background@2x.png" -out "$DUO_OUTPUT/art/background.tiff"
if [[ "$DUO_MODE" == release ]]; then
    # Staple the app before packaging: drag-copy installs retain the ticket offline.
    if [[ ! -f "$DUO_ZIP" ]]; then ditto -c -k --keepParent "$DUO_APP" "$DUO_ZIP"; fi
    python3 scripts/notarize.py "$DUO_ZIP" --state-dir "$DUO_OUTPUT/notary"
    xcrun stapler staple "$DUO_APP"
    xcrun stapler validate "$DUO_APP"
fi
DUO_SUFFIX=''
[[ "$DUO_MODE" == release ]] || DUO_SUFFIX='-preview'
DUO_DMG="$DUO_OUTPUT/DuoReceiver-$DUO_VERSION-arm64$DUO_SUFFIX.dmg"
if [[ ! -f "$DUO_DMG" ]]; then
    DUO_DMG_STAGE="$DUO_OUTPUT/.DuoReceiver-$DUO_VERSION-arm64$DUO_SUFFIX.pending.dmg"
    # A failed image creation is disposable; final artifacts are never overwritten.
    rm -f "$DUO_DMG_STAGE"
    "$DUO_PYTHON" -m dmgbuild -s release/dmg/settings.py \
        -D "app=$DUO_APP" -D "background=$DUO_OUTPUT/art/background.tiff" \
        "Duo Receiver $DUO_VERSION" "$DUO_DMG_STAGE"
    if [[ "$DUO_MODE" == release ]]; then
        codesign --force --sign "$DUO_CODE_SIGN_IDENTITY" --timestamp "$DUO_DMG_STAGE"
        codesign --verify --strict "$DUO_DMG_STAGE"
    fi
    mv "$DUO_DMG_STAGE" "$DUO_DMG"
fi
if [[ "$DUO_MODE" == release ]]; then
    codesign --verify --strict "$DUO_DMG"
    if ! xcrun stapler validate "$DUO_DMG" > /dev/null 2>&1; then
        python3 scripts/notarize.py "$DUO_DMG" --state-dir "$DUO_OUTPUT/notary"
        xcrun stapler staple "$DUO_DMG"
    fi
    xcrun stapler validate "$DUO_DMG"
    spctl --assess --type execute --verbose=2 "$DUO_APP"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DUO_DMG"
fi
hdiutil verify "$DUO_DMG"
python3 scripts/verify-release.py dmg "$DUO_DMG" "$DUO_MODE"
(cd "$DUO_OUTPUT" && shasum -a 256 "$(basename "$DUO_DMG")" > SHA256SUMS)
printf '%s\n' "Built: $DUO_DMG"
