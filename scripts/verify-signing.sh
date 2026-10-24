#!/bin/bash
# Fail before launching a receiver whose privacy permissions would be tied to one build.
set -euo pipefail
DUO_APP_PATH="${1:?Usage: verify-signing.sh /path/to/DuoReceiver.app}"
DUO_SIGNATURE="$(codesign --display --verbose=2 "$DUO_APP_PATH" 2>&1)"
if [[ "$DUO_SIGNATURE" == *"Signature=adhoc"* || "$DUO_SIGNATURE" == *"TeamIdentifier=not set"* ]]; then
    printf '%s\n' 'Receiver signing check failed: an Apple Development or Developer ID identity is required.' \
        'Ad-hoc signing changes the permission identity on every rebuild, even while Settings shows access enabled.' >&2
    exit 1
fi
DUO_REQUIREMENT="$(codesign --display --requirements - "$DUO_APP_PATH" 2>&1)"
if [[ "$DUO_REQUIREMENT" != *"anchor apple generic"* || "$DUO_REQUIREMENT" != *'identifier "app.duotrackpad.receiver"'* || "$DUO_REQUIREMENT" == *"cdhash H"* ]]; then
    printf '%s\n' 'Receiver signing check failed: expected a certificate-based designated requirement for Duo Receiver.' >&2
    exit 1
fi
codesign --verify --strict "$DUO_APP_PATH"
printf '%s\n' 'Receiver signature verified: certificate-based identity survives rebuilds.'
