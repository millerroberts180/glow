// Draws the README's images in docs/images from a `--snapshot-ui` folder, so they always show the current app:
//   swift run Glow --snapshot-ui /tmp/glow-ui
//   swift scripts/readme-images.swift /tmp/glow-ui
// Most images are snapshots copied as they are; a few are cropped or scaled, and the hero sets the Displays
// window and Glow Desk on a soft backdrop. Uses only AppKit and ImageIO.

import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write("usage: swift scripts/readme-images.swift <snapshot folder>\n".data(using: .utf8)!)
    exit(64)
}
let snapshots = URL(fileURLWithPath: args[1])
let images = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/images")
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func load(_ path: String) -> CGImage {
    let url = snapshots.appendingPathComponent(path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("cannot read \(url.path)") }
    return image
}

func save(_ image: CGImage, as name: String) {
    let url = images.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "cannot write \(url.path)")
}

func canvas(_ width: Int, _ height: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
}

/// The top-left `width` × `height` pixels from `x` across, as the README shows them.
func crop(_ image: CGImage, x: Int = 0, width: Int, height: Int) -> CGImage {
    image.cropping(to: CGRect(x: x, y: 0, width: width, height: height))!
}

func scaled(_ image: CGImage, width: Int) -> CGImage {
    let height = Int((Double(image.height) * Double(width) / Double(image.width)).rounded())
    return canvas(width, height) { $0.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)) }
}

/// Places `image` with its top-left at (x, y) from the canvas's top, scaled to `width`, with rounded corners and a soft shadow.
func place(_ image: CGImage, in ctx: CGContext, x: CGFloat, y: CGFloat, width: CGFloat, radius: CGFloat, dark: Bool) {
    let height = width * CGFloat(image.height) / CGFloat(image.width)
    let rect = CGRect(x: x, y: CGFloat(ctx.height) - y - height, width: width, height: height)
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 60,
                  color: CGColor(gray: 0, alpha: dark ? 0.55 : 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(gray: dark ? 0.12 : 0.93, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.draw(image, in: rect)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.setStrokeColor(CGColor(gray: dark ? 1 : 0, alpha: dark ? 0.16 : 0.12))
    ctx.setLineWidth(2)
    ctx.strokePath()
    ctx.restoreGState()
}

/// 820 × 500 points at 2×: the Displays window with Glow Desk beside it, drawn as someone's own desk, on the overlay
/// snapshots' backdrop.
func hero(_ appearance: String) -> CGImage {
    let dark = appearance == "dark"
    return canvas(1640, 1000) { ctx in
        let stops: [(CGFloat, CGFloat, CGFloat)] = dark
            ? [(0.20, 0.19, 0.38), (0.13, 0.24, 0.29), (0.33, 0.23, 0.16)]
            : [(0.61, 0.61, 0.88), (0.66, 0.79, 0.83), (0.92, 0.75, 0.55)]
        let gradient = CGGradient(colorsSpace: sRGB, colors: stops.map { CGColor(srgbRed: $0.0, green: $0.1, blue: $0.2, alpha: 1) } as CFArray,
                                  locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1000), end: CGPoint(x: 1640, y: 0), options: [])
        place(crop(load("window-displays-\(appearance).png"), width: 1520, height: 1218), in: ctx,
              x: 80, y: 64, width: 1000, radius: 22, dark: dark)
        place(load("popover/hero-\(appearance).png"), in: ctx, x: 1066, y: 112, width: 500, radius: 20, dark: dark)
    }
}

for appearance in ["light", "dark"] {
    save(hero(appearance), as: "hero-\(appearance).png")
    save(load("popover/boxes-\(appearance).png"), as: "glow-desk-\(appearance).png")
    save(crop(load("settings-displays-full-\(appearance).png"), x: 336, width: 1184, height: 1424), as: "displays-\(appearance).png")
    save(crop(load("keys/hud-boxes-\(appearance).png"), width: 1392, height: 496), as: "overlay-\(appearance).png")
    save(load("match/calibration-quick-compare-\(appearance).png"), as: "brightness-match-\(appearance).png")
    save(load("pane-scenes-partial-\(appearance).png"), as: "scenes-\(appearance).png")
    save(scaled(load("setup/setup-1-displays-own-\(appearance).png"), width: 640), as: "setup-\(appearance).png")
}
print("wrote the README images to \(images.path)")
