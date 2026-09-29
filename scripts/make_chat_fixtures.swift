// Generates fixture images for the "Saved from chats" scanner.
// - 4 chat-style JPEGs: 1600×1200, no EXIF, WhatsApp / Telegram / random names.
// - 2 camera-style JPEGs: 4032×3024 with TIFF Make/Model and EXIF exposure tags.
// Usage: swift scripts/make_chat_fixtures.swift <outDir>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "KeeprollTests/Fixtures/Chats")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let space = CGColorSpaceCreateDeviceRGB()

func render(width: Int, height: Int, hue: CGFloat, text: Bool) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.95, green: 0.85 - 0.3 * hue, blue: 0.5 + 0.4 * hue, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.3 + 0.4 * hue, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
    if text { // "meme" bar
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
        ctx.fill(CGRect(x: 0, y: height - height / 6, width: width, height: height / 6))
    }
    return ctx.makeImage()!
}

func write(_ image: CGImage, to name: String, properties: [CFString: Any]) {
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    var props = properties
    props[kCGImageDestinationLossyCompressionQuality] = 0.8
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    CGImageDestinationFinalize(dest)
}

let chatNames = ["IMG-20260301-WA0007.jpg", "IMG-20260302-WA0019.jpg", "photo_2026-03-12_10-41-07.jpg", "UYNZ3K2P.jpg"]
for (i, name) in chatNames.enumerated() {
    let long = name.hasPrefix("photo_") ? 1280 : 1600
    write(render(width: long, height: long * 3 / 4, hue: CGFloat(i) / 4, text: true), to: name, properties: [:]) // no EXIF at all
}
for i in 0..<2 {
    let props: [CFString: Any] = [
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 15"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifExposureTime: 0.008, kCGImagePropertyExifFNumber: 1.6,
                                         kCGImagePropertyExifLensModel: "iPhone 15 back camera 5.1mm f/1.6"],
    ]
    write(render(width: 4032, height: 3024, hue: 0.9, text: false), to: String(format: "IMG_%04d.JPG", 7000 + i), properties: props)
}
print("Wrote \(chatNames.count) chat + 2 camera fixtures to \(outDir.path)")
