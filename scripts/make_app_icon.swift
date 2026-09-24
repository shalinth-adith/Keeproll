// Renders the Sift app icon (1024×1024) in light, dark and tinted variants.
// Same geometry as `SiftMark` in the app. Usage:
//   swift scripts/make_app_icon.swift Sift/Resources/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "Sift/Resources/Assets.xcassets/AppIcon.appiconset")
let S: CGFloat = 1024
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Draws one card of the stack, centred at (cx, cy), rotated by `angle` degrees.
func card(_ ctx: CGContext, w: CGFloat, h: CGFloat, cx: CGFloat, cy: CGFloat, angle: CGFloat,
          fill: CGColor, shadow: Bool = false) {
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.rotate(by: angle * .pi / 180)
    if shadow { ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.03), blur: S * 0.06, color: rgb(0x000000, 0.22)) }
    ctx.setFillColor(fill)
    ctx.addPath(roundedPath(CGRect(x: -w / 2, y: -h / 2, width: w, height: h), radius: S * 0.10))
    ctx.fillPath()
    ctx.restoreGState()
}

func checkmark(_ ctx: CGContext, at origin: CGPoint, size: CGFloat, color: CGColor) {
    ctx.saveGState()
    ctx.setStrokeColor(color)
    ctx.setLineWidth(size * 0.22)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: origin.x, y: origin.y + size * 0.45))
    ctx.addLine(to: CGPoint(x: origin.x + size * 0.36, y: origin.y + size * 0.10))
    ctx.addLine(to: CGPoint(x: origin.x + size * 1.0, y: origin.y + size * 0.85))
    ctx.strokePath()
    ctx.restoreGState()
}

/// The stack, in the icon's coordinate space (origin bottom-left).
func drawMark(_ ctx: CGContext, ink: CGColor, inkMid: CGColor, inkBack: CGColor, check: CGColor) {
    let cx = S / 2
    card(ctx, w: S * 0.56, h: S * 0.38, cx: cx, cy: S * 0.31, angle: 0, fill: inkBack)
    card(ctx, w: S * 0.62, h: S * 0.42, cx: cx, cy: S * 0.42, angle: 0, fill: inkMid)
    card(ctx, w: S * 0.68, h: S * 0.46, cx: cx + S * 0.02, cy: S * 0.59, angle: 7, fill: ink, shadow: true)
    // Check sits in the top card's bottom-right corner, rotated with it.
    ctx.saveGState()
    ctx.translateBy(x: cx + S * 0.02, y: S * 0.59)
    ctx.rotate(by: 7 * .pi / 180)
    checkmark(ctx, at: CGPoint(x: S * 0.12, y: -S * 0.17), size: S * 0.15, color: check)
    ctx.restoreGState()
}

func render(_ name: String, draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.lastPathComponent)")
}

let full = CGRect(x: 0, y: 0, width: S, height: S)

// Light: teal gradient tile, white stack, teal check.
render("icon-light.png") { ctx in
    let gradient = CGGradient(colorsSpace: space, colors: [rgb(0x0E8C7F), rgb(0x0B6A60)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
    // Soft highlight in the top-left so the tile doesn't look flat.
    let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S * 0.25, y: S * 0.85), startRadius: 0,
                           endCenter: CGPoint(x: S * 0.25, y: S * 0.85), endRadius: S * 0.9, options: [])
    drawMark(ctx, ink: rgb(0xFFFFFF), inkMid: rgb(0xFFFFFF, 0.58), inkBack: rgb(0xFFFFFF, 0.32), check: rgb(0x0B7A6F))
}

// Dark: near-black tile, teal stack, dark check.
render("icon-dark.png") { ctx in
    ctx.setFillColor(rgb(0x0E1113))
    ctx.fill(full)
    drawMark(ctx, ink: rgb(0x3CC7B5), inkMid: rgb(0x3CC7B5, 0.55), inkBack: rgb(0x3CC7B5, 0.30), check: rgb(0x0E1113))
}

// Tinted: grayscale glyph on transparent; iOS applies the user's tint.
render("icon-tinted.png") { ctx in
    ctx.clear(full)
    drawMark(ctx, ink: rgb(0xFFFFFF), inkMid: rgb(0xFFFFFF, 0.58), inkBack: rgb(0xFFFFFF, 0.32), check: rgb(0x000000, 0.9))
}
