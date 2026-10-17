// Frames raw simulator captures (1320 × 2868) into App Store screenshots of the same
// size: a caption on the warm canvas, the capture below with rounded corners.
// Usage: swift scripts/make_store_screenshots.swift [rawDir] [outDir]
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let rawDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "store/screenshots/raw")
let outDir = URL(fileURLWithPath: args.count > 2 ? args[2] : "store/screenshots/6.9")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let width = 1320, height = 2868
let canvas = CGColor(red: 0xF6 / 255, green: 0xF5 / 255, blue: 0xF1 / 255, alpha: 1)
let ink = CGColor(red: 0x13 / 255, green: 0x18 / 255, blue: 0x1B / 255, alpha: 1)
let inkSecondary = CGColor(red: 0x5B / 255, green: 0x67 / 255, blue: 0x70 / 255, alpha: 1)
let accent = CGColor(red: 0x0B / 255, green: 0x7A / 255, blue: 0x6F / 255, alpha: 1)

// (raw file, headline, subline)
let plan: [(String, String, String)] = [
    ("01-home.png", "See what's filling your iPhone", "One scan. Every category, on the device."),
    ("02-results.png", "Every suggestion, one tap", "Nothing is pre-selected. You choose."),
    ("03-similar.png", "The sharpest shot is kept", "Bursts and duplicates, with Best marked."),
    ("04-chats.png", "Know what came from WhatsApp", "Forwards told apart from your own photos."),
    ("05-expired.png", "Codes and passes past their date", "Read on your iPhone. Never stored."),
    ("06-review.png", "Nothing goes until you say so", "Review every item. Photos go to Recently Deleted."),
    ("07-live.png", "Keep the still, drop the clip", "Live Photos to stills, same date and place."),
    ("08-onboarding.png", "Private. On your iPhone only.", "No account. No network. No analytics."),
]

func draw(_ text: String, size: CGFloat, weight: String, color: CGColor, at y: CGFloat, in ctx: CGContext) {
    // The system font by role, then the bold trait: named "SFPro-*" faces aren't resolvable from a script.
    let base = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    let font = weight == "bold"
        ? (CTFontCreateCopyWithSymbolicTraits(base, size, nil, .boldTrait, .boldTrait) ?? base)
        : base
    let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!)
    let bounds = CTLineGetBoundsWithOptions(line, [])
    ctx.textPosition = CGPoint(x: (CGFloat(width) - bounds.width) / 2, y: y)
    CTLineDraw(line, ctx)
}

for (index, (file, headline, subline)) in plan.enumerated() {
    let url = rawDir.appendingPathComponent(file)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let shot = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("missing \(file)"); continue }
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(canvas)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // Captions (CoreGraphics y is bottom-up).
    draw(headline, size: 78, weight: "bold", color: ink, at: CGFloat(height) - 250, in: ctx)
    draw(subline, size: 42, weight: "regular", color: inkSecondary, at: CGFloat(height) - 330, in: ctx)

    // The capture, scaled to 84 % width, rounded, with a soft shadow, bleeding off the bottom.
    let scale: CGFloat = 0.88
    let w = CGFloat(width) * scale, h = w * CGFloat(shot.height) / CGFloat(shot.width)
    let frame = CGRect(x: (CGFloat(width) - w) / 2, y: -h * 0.06, width: w, height: h)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 60, color: CGColor(gray: 0, alpha: 0.18))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.addPath(CGPath(roundedRect: frame, cornerWidth: 90, cornerHeight: 90, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: frame, cornerWidth: 90, cornerHeight: 90, transform: nil))
    ctx.clip()
    ctx.draw(shot, in: frame)
    ctx.restoreGState()
    // Thin accent hairline around the device for definition.
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.08))
    ctx.setLineWidth(3)
    ctx.addPath(CGPath(roundedRect: frame.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 90, cornerHeight: 90, transform: nil))
    ctx.strokePath()

    let out = outDir.appendingPathComponent(String(format: "%02d-%@", index + 1, file.replacingOccurrences(of: #"^\d+-"#, with: "", options: .regularExpression)))
    let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(out.lastPathComponent)")
}
