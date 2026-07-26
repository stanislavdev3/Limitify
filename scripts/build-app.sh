#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${CONFIGURATION:-release}
sign_identity=${SIGN_IDENTITY:--}
universal=${UNIVERSAL:-1}
dist_dir="$project_dir/dist"
app_bundle="$dist_dir/Limitify.app"
contents="$app_bundle/Contents"

cd "$project_dir"
rm -rf "$app_bundle"
mkdir -p "$contents/MacOS" "$contents/Resources"

if [ "$universal" = "1" ]; then
    arm_scratch="$project_dir/.build-arm64"
    intel_scratch="$project_dir/.build-x86_64"
    swift build -c "$configuration" --product Limitify \
        --triple arm64-apple-macosx14.0 \
        --scratch-path "$arm_scratch" ${SWIFT_BUILD_FLAGS:-}
    swift build -c "$configuration" --product Limitify \
        --triple x86_64-apple-macosx14.0 \
        --scratch-path "$intel_scratch" ${SWIFT_BUILD_FLAGS:-}
    arm_binary="$arm_scratch/arm64-apple-macosx/$configuration/Limitify"
    intel_binary="$intel_scratch/x86_64-apple-macosx/$configuration/Limitify"
    lipo -create "$arm_binary" "$intel_binary" -output "$contents/MacOS/Limitify"
else
    swift build -c "$configuration" --product Limitify ${SWIFT_BUILD_FLAGS:-}
    binary_dir=$(swift build -c "$configuration" --show-bin-path ${SWIFT_BUILD_FLAGS:-})
    cp "$binary_dir/Limitify" "$contents/MacOS/Limitify"
fi

cp "$project_dir/Resources/Info.plist" "$contents/Info.plist"
cp "$project_dir/Resources/Limitify.icns" "$contents/Resources/Limitify.icns"

codesign --force --sign "$sign_identity" --options runtime --timestamp=none "$app_bundle"
codesign --verify --deep --strict --verbose=2 "$app_bundle"

echo "$app_bundle"
