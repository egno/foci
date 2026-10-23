#!/bin/bash
# Builds the Probe fixture and bundles it three times into $E2E_DIR/apps:
#   Probe A (dev.foci.probe.a), Probe B (dev.foci.probe.b), Probe C (dev.foci.probe.c).
# Ad hoc signed; Probe needs no Accessibility permission.
set -euo pipefail
cd "$(dirname "$0")"
: "${E2E_DIR:?E2E_DIR is not set}"

swift build -c release >&2
bin="$(swift build -c release --show-bin-path)/Probe"
mkdir -p "$E2E_DIR/apps"

for kind in a b c; do
    upper=$(echo "$kind" | tr a-z A-Z)
    app="$E2E_DIR/apps/Probe $upper.app"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS"
    cp "$bin" "$app/Contents/MacOS/Probe"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.foci.probe.$kind</string>
    <key>CFBundleName</key><string>Probe $upper</string>
    <key>CFBundleExecutable</key><string>Probe</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
    codesign --force --sign - --identifier "dev.foci.probe.$kind" "$app" >&2
done
echo "built Probe A, B, C in $E2E_DIR/apps"
