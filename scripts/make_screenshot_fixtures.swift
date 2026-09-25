// Generates fake screenshots (flat colour + stripes) tagged with EXIF UserComment
// "Screenshot" so Photos files them under the Screenshots smart album.
// Usage: swift scripts/make_screenshot_fixtures.swift <outDir> <count>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "KeeprollTests/Fixtures/Screenshots")
let count = args.count > 2 ? Int(args[2]) ?? 12 : 12
let width = 1179, height = 2556
let space = CGColorSpaceCreateDeviceRGB()

for i in 0..<count {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let hue = CGFloat(i) / CGFloat(max(count, 1))
    ctx.setFillColor(CGColor(red: 0.3 + 0.6 * hue, green: 0.55, blue: 0.9 - 0.6 * hue, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.85))
    for row in 0..<(8 + i % 5) {
        ctx.fill(CGRect(x: 80, y: height - 300 - row * 180, width: width - 160 - (row * 97 % 400), height: 90))
    }
    let image = ctx.makeImage()!
    let url = outDir.appendingPathComponent(String(format: "fixture-screenshot-%02d.png", i))
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    let date = Date().addingTimeInterval(-Double(i) * 6 * 86_400) // spread over ~2 months
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    let props: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifUserComment: "Screenshot",
            kCGImagePropertyExifDateTimeOriginal: formatter.string(from: date),
        ],
    ]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    CGImageDestinationFinalize(dest)
}
print("Wrote \(count) fixtures to \(outDir.path)")
