// Draws the black & white Islander app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
//
// Design: black rounded square, white island pill with sound bars at the top,
// and the pouch mascot below it. Drawn in a 1024 pt grid (y grows downward).

import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
let output = root.appendingPathComponent("Resources/AppIcon.icns")

func drawIcon(in context: CGContext) {
    let white = NSColor.white
    let black = NSColor.black

    // Body: macOS icon grid uses an 824 pt rounded square centered in 1024.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    black.setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Thin white rim so the icon reads on dark Docks.
    white.withAlphaComponent(0.55).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: 182, yRadius: 182)
    rim.lineWidth = 3
    rim.stroke()

    // Island pill at the top.
    let pill = NSRect(x: 512 - 230, y: 200, width: 460, height: 124)
    white.setFill()
    NSBezierPath(roundedRect: pill, xRadius: 62, yRadius: 62).fill()

    // Sound bars inside the pill.
    black.setFill()
    let heights: [CGFloat] = [34, 64, 88, 52, 76, 40]
    let barWidth: CGFloat = 20
    let gap: CGFloat = 16
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = pill.midX - totalWidth / 2
    for height in heights {
        let bar = NSRect(x: x, y: pill.midY - height / 2, width: barWidth, height: height)
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        x += barWidth + gap
    }

    // Mascot: the white pouch from Sources/Islander/Mascot/MascotView.swift, drawn in
    // black & white. Unit coordinates (0...1) are mapped into a 520 pt box.
    let box = NSRect(x: 512 - 285, y: 335, width: 570, height: 570)
    func u(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: box.minX + x * box.width, y: box.minY + y * box.height) }
    let outline: CGFloat = 0.014 * box.width

    func outlined(_ path: NSBezierPath) {
        white.setFill()
        path.fill()
        black.setStroke()
        path.lineWidth = outline
        path.stroke()
    }

    // Cards peeking out, back to front, slightly fanned.
    for (index, tilt) in [(0, -4.0), (1, 3.0), (2, 0.0)] {
        let i = CGFloat(index)
        let rect = NSRect(
            x: box.minX + (0.22 + i * 0.015) * box.width,
            y: box.minY + (0.11 + i * 0.05) * box.height,
            width: (0.56 - i * 0.03) * box.width,
            height: 0.24 * box.height
        )
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.maxY)
        context.rotate(by: CGFloat(tilt * .pi / 180))
        context.translateBy(x: -rect.midX, y: -rect.maxY)
        outlined(NSBezierPath(roundedRect: rect, xRadius: 0.06 * box.width, yRadius: 0.06 * box.width))
        context.restoreGState()
    }

    // Back panel, then the front flap: a rounded, upside-down triangle.
    outlined(NSBezierPath(
        roundedRect: NSRect(x: u(0.1, 0).x, y: u(0, 0.27).y, width: 0.8 * box.width, height: 0.17 * box.height),
        xRadius: 0.085 * box.width, yRadius: 0.085 * box.width
    ))
    func roundedTriangle(_ a: NSPoint, _ b: NSPoint, _ c: NSPoint, radius: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
        path.appendArc(from: b, to: c, radius: radius)
        path.appendArc(from: c, to: a, radius: radius * 1.3)
        path.appendArc(from: a, to: b, radius: radius)
        path.close()
        return path
    }
    outlined(roundedTriangle(u(0.08, 0.33), u(0.92, 0.33), u(0.5, 0.96), radius: 0.09 * box.width))

    // Dashed stitching.
    let stitch = roundedTriangle(u(0.155, 0.375), u(0.845, 0.375), u(0.5, 0.895), radius: 0.06 * box.width)
    stitch.lineWidth = 0.011 * box.width
    stitch.lineCapStyle = .round
    stitch.setLineDash([0.026 * box.width, 0.022 * box.width], count: 2, phase: 0)
    black.setStroke()
    stitch.stroke()

    // Clasp strap with a snap button.
    outlined(NSBezierPath(
        roundedRect: NSRect(x: u(0.66, 0).x, y: u(0, 0.5).y, width: 0.27 * box.width, height: 0.15 * box.height),
        xRadius: 0.075 * box.width, yRadius: 0.075 * box.width
    ))
    let button = NSBezierPath(ovalIn: NSRect(x: u(0.735, 0).x, y: u(0, 0.53).y, width: 0.09 * box.width, height: 0.09 * box.width))
    outlined(button)

    // Tall pill eyes with a glint.
    for side in [-1.0, 1.0] as [CGFloat] {
        let center = u(0.44 + side * 0.09, 0.55)
        let width = 0.078 * box.width
        let height = 0.175 * box.width
        let eye = NSRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        black.setFill()
        NSBezierPath(roundedRect: eye, xRadius: width / 2, yRadius: width / 2).fill()
        let glint = NSRect(x: eye.minX + width * 0.22, y: eye.minY + height * 0.1, width: width * 0.36, height: height * 0.28)
        white.setFill()
        NSBezierPath(roundedRect: glint, xRadius: width * 0.18, yRadius: width * 0.18).fill()
    }

    // Two music notes.
    let noteFont = NSFont.systemFont(ofSize: 120, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [.font: noteFont, .foregroundColor: white]
    ("♪" as NSString).draw(at: NSPoint(x: 185, y: 380), withAttributes: attributes)
    ("♫" as NSString).draw(at: NSPoint(x: 735, y: 360), withAttributes: attributes)
}

func renderPNG(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    // Flip to a top-left origin and scale the 1024 grid to the target size.
    let scale = CGFloat(pixels) / 1024
    context.translateBy(x: 0, y: CGFloat(pixels))
    context.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    drawIcon(in: context)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try renderPNG(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try renderPNG(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try renderPNG(pixels: 1024).write(to: root.appendingPathComponent("Resources/AppIcon.png"))
print("Wrote \(output.path)")
