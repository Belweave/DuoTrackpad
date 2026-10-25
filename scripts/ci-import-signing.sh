#!/bin/bash
set -euo pipefail
umask 077
: "${RUNNER_TEMP:?GitHub runner required}"
: "${GITHUB_ENV:?GitHub runner required}"
for DUO_SECRET in DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD ASC_PRIVATE_KEY_BASE64 ASC_KEY_ID ASC_ISSUER_ID; do
    [[ -n "${!DUO_SECRET:-}" ]] || { echo "Missing release secret: $DUO_SECRET" >&2; exit 1; }
done
DUO_SECRETS="$RUNNER_TEMP/duo-receiver-signing"
mkdir -m 700 "$DUO_SECRETS"
DUO_KEYCHAIN="$DUO_SECRETS/release.keychain-db"
DUO_KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
echo "::add-mask::$DUO_KEYCHAIN_PASSWORD"
security list-keychains -d user > "$DUO_SECRETS/previous-keychains.txt"
printf '%s' "$DEVELOPER_ID_P12_BASE64" | base64 --decode > "$DUO_SECRETS/developer-id.p12"
printf '%s' "$ASC_PRIVATE_KEY_BASE64" | base64 --decode > "$DUO_SECRETS/notary.p8"
security create-keychain -p "$DUO_KEYCHAIN_PASSWORD" "$DUO_KEYCHAIN"
security set-keychain-settings -lut 3600 "$DUO_KEYCHAIN"
security unlock-keychain -p "$DUO_KEYCHAIN_PASSWORD" "$DUO_KEYCHAIN"
security import "$DUO_SECRETS/developer-id.p12" -P "$DEVELOPER_ID_P12_PASSWORD" \
    -k "$DUO_KEYCHAIN" -T /usr/bin/codesign -T /usr/bin/security > /dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$DUO_KEYCHAIN_PASSWORD" "$DUO_KEYCHAIN" > /dev/null
python3 - "$DUO_SECRETS/previous-keychains.txt" "$DUO_KEYCHAIN" <<'PY'
import shlex,subprocess,sys
previous=shlex.split(open(sys.argv[1]).read())
subprocess.run(['security','list-keychains','-d','user','-s',sys.argv[2],*previous],check=True)
PY
DUO_IDENTITY="$(security find-identity -v -p codesigning "$DUO_KEYCHAIN" | awk '/Developer ID Application:/ {print $2}')"
[[ "$DUO_IDENTITY" =~ ^[A-Fa-f0-9]{40}$ ]] || { echo 'Expected exactly one Developer ID Application identity.' >&2; exit 1; }
{
    echo "DUO_CODE_SIGN_IDENTITY=$DUO_IDENTITY"
    echo "ASC_PRIVATE_KEY_PATH=$DUO_SECRETS/notary.p8"
    echo "ASC_KEY_ID=$ASC_KEY_ID"
    echo "ASC_ISSUER_ID=$ASC_ISSUER_ID"
} >> "$GITHUB_ENV"
