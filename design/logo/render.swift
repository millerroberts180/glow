// Renders the Glow logo SVGs to PNG. Run from the repository root after generate.py:
//   swift design/logo/render.swift
// Uses only AppKit's SVG support and ImageIO, so the PNGs are drawn from the SVGs themselves and can't drift
// from them. No third-party tools or browser needed.

import AppKit
import ImageIO
import UniformTypeIdentifiers

let logo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("design/logo")
let out = logo.appendingPathComponent("png")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// Draws an SVG into a transparent sRGB bitmap `width` pixels wide (height follows the artwork's aspect).
func png(_ svg: String, width: Int, as name: String) {
    let url = logo.appendingPathComponent(svg)
    guard let image = NSImage(contentsOf: url) else { fatalError("cannot read \(url.path)") }
    let height = Int((CGFloat(width) * image.size.height / image.size.width).rounded())
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("no bitmap context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    let dest = CGImageDestinationCreateWithURL(out.appendingPathComponent(name) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(dest), "cannot write \(name)")
}

png("glow-concept-board.svg", width: 1600, as: "glow-concept-board.png")
png("glow-app-icon.svg", width: 1024, as: "glow-app-icon-1024.png")
png("glow-app-icon.svg", width: 512, as: "glow-app-icon-512.png")
// The shipping 16 and 32 px icons use the small cut, as Hum's, Pulse's and Tuck's icon sets do.
png("glow-app-icon-small.svg", width: 32, as: "glow-app-icon-32.png")
png("glow-app-icon-small.svg", width: 16, as: "glow-app-icon-16.png")
for colour in ["orange", "black", "white"] {
    png("glow-symbol-\(colour).svg", width: 512, as: "glow-symbol-\(colour)-512.png")
}
print("wrote PNGs to \(out.path)")
