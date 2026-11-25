#!/bin/bash
# Renders Resources/AppIcon.svg to Resources/AppIcon.icns (committed, so builds don't need this).
# Needs only macOS: AppKit draws the SVG, iconutil packs the sizes.
set -euo pipefail
cd "$(dirname "$0")/.."

set=$(mktemp -d)/AppIcon.iconset
mkdir -p "$set"
swift - Resources/AppIcon.svg "$set" <<'SWIFT'
import AppKit

let args = CommandLine.arguments
guard let svg = NSImage(contentsOfFile: args[1]) else { fatalError("can't read \(args[1])") }
// name: pixel size. The @2x files are the next size up.
let sizes: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
    ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024),
]
for (name, px) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: px, height: px).fill(using: .copy)
    svg.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(args[2])/icon_\(name).png"))
}
SWIFT
iconutil -c icns "$set" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns"
