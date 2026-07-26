#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_bundle="$project_dir/dist/Limitify.app"
dmg_path="$project_dir/dist/Limitify-0.1.0.dmg"
sign_identity=${SIGN_IDENTITY:--}
dmg_root=$(mktemp -d "${TMPDIR:-/tmp}/limitify-dmg.XXXXXX")

cleanup() {
    rm -rf "$dmg_root"
}
trap cleanup EXIT INT TERM

if [ ! -d "$app_bundle" ]; then
    echo "Missing $app_bundle; run make bundle first." >&2
    exit 1
fi

cp -R "$app_bundle" "$dmg_root/Limitify.app"
ln -s /Applications "$dmg_root/Applications"
rm -f "$dmg_path"

hdiutil create \
    -volname Limitify \
    -srcfolder "$dmg_root" \
    -ov \
    -format UDZO \
    "$dmg_path" >/dev/null

if [ "$sign_identity" != "-" ]; then
    codesign --force --sign "$sign_identity" --timestamp "$dmg_path"
fi

echo "$dmg_path"
