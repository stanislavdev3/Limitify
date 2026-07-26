#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dmg_path="$project_dir/dist/Limitify-0.1.0.dmg"

if [ -z "${NOTARY_PROFILE:-}" ]; then
    echo "Set NOTARY_PROFILE to an xcrun notarytool keychain profile." >&2
    exit 1
fi

xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
