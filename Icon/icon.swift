// The app's icon, drawn rather than exported: Ant's mark — an ant seen from
// above — built from plain geometry, the same shape as Design.swift's
// `Logomark`, so it stays a crisp vector at every size. The icon puts it on
// a plate — a Dock icon has to be an opaque square whether the mark wants a
// background or not.

import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// The mark's canvas, 608 × 276, and the ant on it with y growing downward —
/// copied from `Logomark.ant`; keep the two alike.
let canvas = (width: 608.0, height: 276.0)
let ant: CGPath = {
    let mid: CGFloat = 138
    let body = CGMutablePath()
    body.addEllipse(in: CGRect(x: 40, y: mid - 86, width: 236, height: 172))
    body.addEllipse(in: CGRect(x: 292, y: mid - 44, width: 118, height: 88))
    body.addEllipse(in: CGRect(x: 424, y: mid - 54, width: 108, height: 108))
    body.addPath(CGPath(roundedRect: CGRect(x: 262, y: mid - 13, width: 44, height: 26), cornerWidth: 13, cornerHeight: 13, transform: nil))
    body.addPath(CGPath(roundedRect: CGRect(x: 400, y: mid - 11, width: 34, height: 22), cornerWidth: 11, cornerHeight: 11, transform: nil))
    let limbs = CGMutablePath()
    for side: CGFloat in [-1, 1] {
        func y(_ up: CGFloat) -> CGFloat { mid + side * up }
        limbs.move(to: CGPoint(x: 320, y: y(20))); limbs.addLine(to: CGPoint(x: 268, y: y(84))); limbs.addLine(to: CGPoint(x: 214, y: y(112)))
        limbs.move(to: CGPoint(x: 350, y: y(24))); limbs.addLine(to: CGPoint(x: 352, y: y(96))); limbs.addLine(to: CGPoint(x: 326, y: y(120)))
        limbs.move(to: CGPoint(x: 382, y: y(20))); limbs.addLine(to: CGPoint(x: 432, y: y(86))); limbs.addLine(to: CGPoint(x: 470, y: y(116)))
        limbs.move(to: CGPoint(x: 512, y: y(30))); limbs.addLine(to: CGPoint(x: 548, y: y(88))); limbs.addLine(to: CGPoint(x: 590, y: y(104)))
    }
        // One outline: overlapping parts, and strokes wound the other way,
    // would otherwise leave nicks where they cross.
    return body.union(limbs.copy(strokingWithWidth: 16, lineCap: .round, lineJoin: .round, miterLimit: 10))
}()

/// The mark, fit to `fraction` of `plate`'s width and centred on it, and
/// filled into the current context. Its y grows downward and AppKit's
/// upward, so it is flipped on the way in.
func fillMark(in plate: NSRect, fraction: CGFloat) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let scale = plate.width * fraction / canvas.width
    let ox = plate.midX - canvas.width * scale / 2
    let oy = plate.midY - canvas.height * scale / 2
    context.saveGState()
    context.translateBy(x: ox, y: oy + canvas.height * scale)
    context.scaleBy(x: scale, y: -scale)
    context.addPath(ant)
    context.fillPath(using: .winding)
    context.restoreGState()
}

func draw(_ size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    // Apple's grid: the shape takes 824 of 1024, and its corners are 22.37%.
    let s = size / 1024
    let plate = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let radius = 824 * 0.2237 * s
    let shape = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

    // A soft shadow under the plate, the way every icon on the Dock has one.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor.white.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // The mark, black on the plate, three quarters of its width.
    NSColor(red: 0.09, green: 0.09, blue: 0.09, alpha: 1).setFill()
    fillMark(in: plate, fraction: 0.754)
    return image
}

func write(_ image: NSImage, to url: URL, pixels: Int) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff)
    else { return }
    // The bitmap is asked for at the pixel size, whatever the screen thinks.
    let sized = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    sized.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sized)
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = sized.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: url)
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let image = draw(CGFloat(pixels))
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        write(image, to: out.appendingPathComponent(name), pixels: pixels)
    }
}
print("drew: \(out.path)")
