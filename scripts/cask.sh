#!/bin/bash
# Writes Casks/foci.rb in the Homebrew tap (github.com/egno/homebrew-tap) for the version in Info.plist and the
# DMG built by `make release`. Publish the GitHub release first, then commit and push the tap.
#   make cask TAP=~/proj/homebrew-tap
set -euo pipefail
cd "$(dirname "$0")/.."

tap="${TAP:-../homebrew-tap}"
tap="${tap/#\~/$HOME}"  # make passes ~ unexpanded
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
dmg=build/Foci-$version.dmg
[ -f "$dmg" ] || { echo "no $dmg: run make release" >&2; exit 1; }
sha=$(shasum -a 256 "$dmg" | cut -d' ' -f1)

mkdir -p "$tap/Casks"
cat >"$tap/Casks/foci.rb" <<CASK
cask "foci" do
  version "$version"
  sha256 "$sha"

  url "https://github.com/egno/foci/releases/download/v#{version}/Foci-#{version}.dmg"
  name "Foci"
  desc "Keyboard-first window manager for working on one project at a time"
  homepage "https://github.com/egno/foci"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Foci.app"
  binary "#{appdir}/Foci.app/Contents/MacOS/foci"

  # Not notarized: clear the quarantine flag so macOS opens it.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Foci.app"]
  end

  # Foci puts every parked window back on screen when it quits.
  uninstall quit: "dev.foci.Foci"

  zap trash: [
    "~/.config/foci",
    "~/Library/Application Support/Foci",
  ]

  caveats <<~EOS
    Foci needs the Accessibility permission (it asks on first start). Release builds are signed ad hoc,
    so after an upgrade macOS may ask again: remove Foci from System Settings → Privacy & Security →
    Accessibility and add it back.
  EOS
end
CASK
echo "wrote $tap/Casks/foci.rb ($version, $sha)"
