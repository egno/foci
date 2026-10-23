#!/bin/bash
# Builds build/Foci.app. Signs with the "Foci Dev" identity if present (see make-signing-cert.sh),
# otherwise ad hoc. Ad hoc signatures change on every build, so macOS forgets the Accessibility
# permission after each rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
app=build/Foci.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/foci" "$app/Contents/MacOS/foci"
cp Resources/Info.plist "$app/Contents/Info.plist"

identity="${FOCI_SIGN_IDENTITY:-Foci Dev}"
if security find-certificate -c "$identity" >/dev/null 2>&1; then
    codesign --force --sign "$identity" --identifier dev.foci.Foci "$app"
else
    echo "warning: no '$identity' certificate, signing ad hoc (run scripts/make-signing-cert.sh)" >&2
    codesign --force --sign - --identifier dev.foci.Foci "$app"
fi
echo "built $app"
