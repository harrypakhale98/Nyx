#!/bin/sh
# Xcode Cloud, before each xcodebuild action. An archive must carry the NPS key: checked again
# here because CI_XCODEBUILD_ACTION is always known at this point.
set -eu
cd "$(dirname "$0")/.."

if [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ]; then
    if ! grep -Eq '^[[:space:]]*NPS_API_KEY[[:space:]]*=[[:space:]]*[A-Za-z0-9]+' Config/Secrets.xcconfig 2>/dev/null; then
        echo "error: archiving without an NPS key. Set the NPS_API_KEY secret for this workflow." >&2
        exit 1
    fi
fi
