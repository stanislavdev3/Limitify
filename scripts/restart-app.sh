#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_bundle="$project_dir/dist/Limitify.app"

if [ ! -d "$app_bundle" ]; then
    echo "Missing $app_bundle; run make bundle first." >&2
    exit 1
fi

running_pids=$(pgrep -x Limitify 2>/dev/null || true)
if [ -n "$running_pids" ]; then
    for pid in $running_pids; do
        kill "$pid"
    done

    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        if ! pgrep -x Limitify >/dev/null 2>&1; then
            break
        fi
        sleep 0.2
    done

    if pgrep -x Limitify >/dev/null 2>&1; then
        echo "Limitify did not terminate in time." >&2
        exit 1
    fi
fi

open -n "$app_bundle"
echo "Restarted $app_bundle"
