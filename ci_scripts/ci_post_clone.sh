#!/bin/sh
# Xcode Cloud, after cloning: writes Config/Secrets.xcconfig from the NPS_API_KEY secret
# environment variable (set it as a secret in the workflow; never commit the key).
# A Release or archive workflow without the key fails here, so a build that cannot show park
# alerts is never uploaded. Test workflows run without it (Nyx works fully without a key).
set -eu
cd "$(dirname "$0")/.."

if [ -n "${NPS_API_KEY:-}" ]; then
    printf 'NPS_API_KEY = %s\n' "$NPS_API_KEY" > Config/Secrets.xcconfig
    echo "Config/Secrets.xcconfig written from the NPS_API_KEY secret."
    exit 0
fi

case "${CI_XCODEBUILD_ACTION:-}:${CI_WORKFLOW:-}" in
    archive:*|*:*Release*|*:*release*)
        echo "error: NPS_API_KEY is empty. Add it as a secret environment variable to this workflow." >&2
        exit 1 ;;
    *)
        echo "No NPS_API_KEY: building without park alerts (fine for tests)." ;;
esac
