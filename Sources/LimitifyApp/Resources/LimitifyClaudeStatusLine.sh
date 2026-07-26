#!/bin/sh
set -u

cache_path=${1:-}
previous_command_base64=${2:-}
input_file=$(mktemp "${TMPDIR:-/tmp}/limitify-claude-input.XXXXXX") || exit 0

cleanup() {
    rm -f "$input_file"
}
trap cleanup EXIT INT TERM

cat >"$input_file"

if [ -n "$cache_path" ]; then
    cache_directory=$(dirname "$cache_path")
    mkdir -p "$cache_directory"
    cache_temp=$(mktemp "$cache_directory/.claude-usage.XXXXXX")
    if /usr/bin/plutil -extract rate_limits json -o "$cache_temp" "$input_file" 2>/dev/null; then
        mv -f "$cache_temp" "$cache_path"
    else
        rm -f "$cache_temp"
    fi
fi

if [ -n "$previous_command_base64" ]; then
    previous_command=$(printf '%s' "$previous_command_base64" | /usr/bin/base64 -D 2>/dev/null)
    if [ -n "$previous_command" ]; then
        /bin/zsh -lc "$previous_command" <"$input_file"
    fi
fi

exit 0
