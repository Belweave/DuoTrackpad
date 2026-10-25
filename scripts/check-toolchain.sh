#!/bin/bash
set -euo pipefail
DUO_TOOLCHAIN="$(xcodebuild -version)"
if [[ "$DUO_TOOLCHAIN" != $'Xcode 27.1\nBuild version 27A9275' ]]; then
    printf '%s\n' 'Select Xcode 27.1 (27A9275). No silent toolchain fallback.' "$DUO_TOOLCHAIN" >&2
    exit 1
fi
printf '%s\n' "$DUO_TOOLCHAIN"
