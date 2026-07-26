#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_png="$project_dir/Resources/AppIconSource.png"
output_icns="$project_dir/Resources/Limitify.icns"
icon_work_dir=$(mktemp -d "${TMPDIR:-/tmp}/limitify-icon.XXXXXX")
png_dir="$icon_work_dir/png"
builder="$icon_work_dir/icns-builder"

cleanup() {
    rm -rf "$icon_work_dir"
}
trap cleanup EXIT INT TERM

mkdir -p "$png_dir"

make_size() {
    pixels=$1
    sips -z "$pixels" "$pixels" "$source_png" --out "$png_dir/$pixels.png" >/dev/null
}

make_size 16
make_size 32
make_size 64
make_size 128
make_size 256
make_size 512
make_size 1024

swiftc "$project_dir/scripts/ICNSBuilder.swift" -o "$builder"
"$builder" "$png_dir" "$output_icns"
echo "$output_icns"
