#!/bin/bash
set -euo pipefail
DUO_VERSION="${1:?Pass the release version}"
DUO_SHA="${2:?Pass the built commit SHA}"
[[ "$DUO_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || exit 1
DUO_REFS="$(git ls-remote --tags origin "refs/tags/v$DUO_VERSION" "refs/tags/v$DUO_VERSION^{}")"
DUO_TAG_SHA="$(printf '%s\n' "$DUO_REFS" | awk 'NF {value=$1} END {print value}')"
if [[ -n "$DUO_TAG_SHA" && "$DUO_TAG_SHA" != "$DUO_SHA" ]]; then
    echo "Release v$DUO_VERSION already points to $DUO_TAG_SHA; refusing binaries from $DUO_SHA." >&2
    exit 1
fi
