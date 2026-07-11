#!/usr/bin/env swift
import Cocoa
import CoreGraphics

let size: CGFloat = 1024
let center = CGPoint(x: size / 2, y: size / 2)
let arcRadius: CGFloat = 355
let arcLineWidth: CGFloat = 88

func toRad(_ deg: CGFloat) -> CGFloat { deg * .pi / 180 }

func cgColor(_ hex: String) -> CGColor {
    let v = UInt64(hex.dropFirst(), radix: 16)!
    return CGColor(red:   CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >>  8) & 0xFF) / 255,
                   blue:  CGFloat( v        & 0xFF) / 255,
                   alpha: 1)
}

func drawIcon(isDark: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // Background (full square — iOS applies the rounded mask at render time)
    ctx.setFillColor(isDark ? cgColor("#1C1C1E") : cgColor("#FFFFFF"))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // Convert a stroked arc into a filled CGPath so we can clip/fill with gradients.
    func arcPath(start: CGFloat, end: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.addArc(center: center, radius: arcRadius,
                 startAngle: toRad(start), endAngle: toRad(end), clockwise: true)
        return p.copy(strokingWithWidth: arcLineWidth,
                      lineCap: .round, lineJoin: .round, miterLimit: 10)
    }

    func drawSolid(start: CGFloat, end: CGFloat, hex: String) {
        ctx.setFillColor(cgColor(hex))
        ctx.addPath(arcPath(start: start, end: end))
        ctx.fillPath()
    }

    func drawGradient(start: CGFloat, end: CGFloat, hex1: String, hex2: String) {
        // Gradient runs from the geometric start point of the arc to its end point.
        let p1 = CGPoint(x: center.x + arcRadius * cos(toRad(start)),
                         y: center.y + arcRadius * sin(toRad(start)))
        let p2 = CGPoint(x: center.x + arcRadius * cos(toRad(end)),
                         y: center.y + arcRadius * sin(toRad(end)))
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [cgColor(hex1), cgColor(hex2)] as CFArray,
                              locations: [0, 1])!
        ctx.saveGState()
        ctx.addPath(arcPath(start: start, end: end))
        ctx.clip()
        ctx.drawLinearGradient(grad, start: p1, end: p2, options: [])
        ctx.restoreGState()
    }

    // Arc positions (macOS CG coords: Y↑, angles CCW from right = 0°, drawn CW)
    // Each arc spans 76°, gaps are 14°, centered at cardinal clock positions.
    drawSolid(start: 128, end: 52,  hex: "#6DD98F")           // Green  — 12 o'clock
    drawSolid(start: 38,  end: 322, hex: "#FFD166")           // Orange —  3 o'clock
    drawGradient(start: 308, end: 232,                         // Purple →  6 o'clock (gradient)
                 hex1: "#C47AE8", hex2: "#E8849E")
    drawSolid(start: 218, end: 142, hex: "#88B4F5")           // Blue   —  9 o'clock

    // ── Magnifying glass ──────────────────────────────────────────────────────
    let glassColor = isDark ? cgColor("#FFFFFF") : cgColor("#222225")
    // Center offset -15 x, +15 y (macOS Y↑) so the handle extends to lower-right visually.
    let gc = CGPoint(x: center.x - 15, y: center.y + 15)
    let lensR: CGFloat  = 130
    let strokeW: CGFloat = 50
    let angle = toRad(-45)  // -45° in Y↑ coords = down-right on screen

    ctx.setStrokeColor(glassColor)
    ctx.setLineWidth(strokeW)
    ctx.setLineCap(.round)

    // Lens
    ctx.addEllipse(in: CGRect(x: gc.x - lensR, y: gc.y - lensR,
                               width: lensR * 2, height: lensR * 2))
    ctx.strokePath()

    // Handle (starts at the lens edge, extends outward at -45°)
    let edgeDist = lensR + strokeW / 2 - 6
    let hStart = CGPoint(x: gc.x + edgeDist * cos(angle), y: gc.y + edgeDist * sin(angle))
    let hEnd   = CGPoint(x: hStart.x + 105 * cos(angle),  y: hStart.y + 105 * sin(angle))
    ctx.move(to: hStart)
    ctx.addLine(to: hEnd)
    ctx.strokePath()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff   = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png    = bitmap.representation(using: .png, properties: [:]) else {
        print("ERROR: could not encode PNG at \(path)")
        exit(1)
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("✓  \(path)")
    } catch {
        print("ERROR writing \(path): \(error)")
        exit(1)
    }
}

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let assetDir  = "\(scriptDir)/../Findly/Resources/Assets.xcassets/AppIcon.appiconset"

savePNG(drawIcon(isDark: false), to: "\(assetDir)/AppIcon_Light.png")
savePNG(drawIcon(isDark: true),  to: "\(assetDir)/AppIcon_Dark.png")
