#!/bin/bash
# Builds build/Foci-<version>.dmg and .zip for a GitHub release: a universal (arm64 + x86_64) Foci.app, signed with
# the self-signed "Foci Release" certificate (scripts/make-signing-cert.sh "Foci Release"). Every release has the
# same signing requirement, so macOS keeps the Accessibility permission across updates. The certificate means
# nothing to Gatekeeper: not notarized, users remove the quarantine attribute once (see README).
# There is no ad hoc fallback: it would make the next update ask for the permission again.
set -euo pipefail
cd "$(dirname "$0")/.."

identity="${FOCI_RELEASE_IDENTITY:-Foci Release}"
security find-certificate -c "$identity" >/dev/null 2>&1 \
    || { echo "no '$identity' certificate: run scripts/make-signing-cert.sh \"$identity\"" >&2; exit 1; }

version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
swift build -c release --arch arm64 --arch x86_64
bin=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

app=build/release/Foci.app
rm -rf build/release
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp "$bin/foci" "$app/Contents/MacOS/foci"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign "$identity" --identifier dev.foci.Foci "$app"

zip=build/Foci-$version.zip
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

# The disk image: Foci.app next to a link to /Applications, to drag it onto.
dmg=build/Foci-$version.dmg
stage=build/release/dmg
mkdir -p "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -quiet -volname "Foci $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"

lipo -archs "$app/Contents/MacOS/foci"
shasum -a 256 "$dmg" "$zip"
