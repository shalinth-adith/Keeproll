// Generates JPEG fixtures that exercise the similarity scan on the simulator:
//   burst-*    : 3 bursts of 3–4 near-identical shots taken seconds apart
//   dup-*      : the same scene saved twice, months apart, at different JPEG quality
//   blurry-*   : out-of-focus shots (rendered small, scaled up)
//   unique-*   : unrelated scenes
// Capture dates are written to EXIF DateTimeOriginal, which Photos uses on import.
// Usage: swift scripts/make_photo_fixtures.swift KeeprollTests/Fixtures/Photos
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "KeeprollTests/Fixtures/Photos")
let W = 1600, H = 1200
let space = CGColorSpaceCreateDeviceRGB()
let exifFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy:MM:dd HH:mm:ss"; return f }()

struct Scene {
    var sky: (CGFloat, CGFloat, CGFloat)
    var ground: (CGFloat, CGFloat, CGFloat)
    var sun: CGPoint
    var hills: [CGFloat]
}

func render(_ s: Scene, shift: CGFloat = 0, zoom: CGFloat = 1, blur: Bool = false) -> CGImage {
    let scale: CGFloat = blur ? 0.04 : 1
    let w = Int(CGFloat(W) * scale), h = Int(CGFloat(H) * scale)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale * zoom, y: scale * zoom)
    ctx.translateBy(x: shift - CGFloat(W) * (zoom - 1) / 2, y: -CGFloat(H) * (zoom - 1) / 2)
    let sky = CGGradient(colorsSpace: space, colors: [
        CGColor(red: s.sky.0, green: s.sky.1, blue: s.sky.2, alpha: 1),
        CGColor(red: s.sky.0 * 0.6 + 0.4, green: s.sky.1 * 0.6 + 0.4, blue: s.sky.2 * 0.6 + 0.4, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: CGFloat(H)), end: CGPoint(x: 0, y: CGFloat(H) * 0.4), options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
    ctx.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.6, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: s.sun.x, y: s.sun.y, width: 180, height: 180))
    for (i, peak) in s.hills.enumerated() {
        let shade = CGFloat(i) * 0.12
        ctx.setFillColor(CGColor(red: s.ground.0 - shade, green: s.ground.1 - shade, blue: s.ground.2 - shade, alpha: 1))
        ctx.move(to: CGPoint(x: -200, y: 0))
        ctx.addLine(to: CGPoint(x: CGFloat(i) * 500 - 100, y: peak))
        ctx.addLine(to: CGPoint(x: CGFloat(i) * 500 + 700, y: 0))
        ctx.fillPath()
    }
    // Texture so the images compress like photos, not flat art.
    var seed: UInt64 = 1
    for _ in 0..<2500 {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let x = CGFloat(seed % UInt64(W)), y = CGFloat((seed >> 20) % UInt64(H / 2))
        ctx.setFillColor(CGColor(gray: CGFloat((seed >> 40) % 100) / 100, alpha: 0.18))
        ctx.fill(CGRect(x: x, y: y, width: 6, height: 6))
    }
    let image = ctx.makeImage()!
    guard blur else { return image }
    // Scale the tiny render back up: soft everywhere, like missed focus.
    let up = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    up.interpolationQuality = .high
    up.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))
    return up.makeImage()!
}

func save(_ image: CGImage, _ name: String, date: Date, quality: Double = 0.85) {
    let url = outDir.appendingPathComponent(name + ".jpg")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    let props: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: quality,
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: exifFormat.string(from: date)],
    ]
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    CGImageDestinationFinalize(dest)
}

let base = Date(timeIntervalSinceNow: -60 * 86_400)
let scenes = [
    Scene(sky: (0.25, 0.5, 0.9), ground: (0.3, 0.6, 0.3), sun: CGPoint(x: 1100, y: 850), hills: [520, 380, 460]),
    Scene(sky: (0.9, 0.45, 0.3), ground: (0.45, 0.35, 0.3), sun: CGPoint(x: 300, y: 700), hills: [300, 560, 420]),
    Scene(sky: (0.35, 0.3, 0.6), ground: (0.2, 0.4, 0.5), sun: CGPoint(x: 700, y: 900), hills: [640, 300, 500]),
    Scene(sky: (0.6, 0.8, 0.95), ground: (0.7, 0.65, 0.4), sun: CGPoint(x: 150, y: 950), hills: [250, 450, 350]),
    Scene(sky: (0.15, 0.2, 0.35), ground: (0.25, 0.25, 0.3), sun: CGPoint(x: 1300, y: 1000), hills: [700, 650, 300]),
    Scene(sky: (0.95, 0.75, 0.5), ground: (0.5, 0.55, 0.2), sun: CGPoint(x: 900, y: 600), hills: [420, 420, 620]),
]

// Bursts: tiny camera moves / zooms, 2 s apart.
for (b, scene) in scenes.prefix(3).enumerated() {
    let start = base.addingTimeInterval(Double(b) * 7 * 86_400)
    let shots = b == 1 ? 4 : 3
    for i in 0..<shots {
        save(render(scene, shift: CGFloat(i) * 14, zoom: 1 + CGFloat(i) * 0.015), "burst-\(b)-\(i)",
             date: start.addingTimeInterval(Double(i) * 2))
    }
}
// Exact duplicates: same scene, re-saved at lower quality 90 days later.
save(render(scenes[3]), "dup-original", date: base.addingTimeInterval(-40 * 86_400), quality: 0.9)
save(render(scenes[3]), "dup-copy", date: base.addingTimeInterval(50 * 86_400), quality: 0.6)
// Blurry: isolated in time.
save(render(scenes[4], blur: true), "blurry-0", date: base.addingTimeInterval(3 * 86_400))
save(render(scenes[5], blur: true), "blurry-1", date: base.addingTimeInterval(11 * 86_400))
// Unique scenes.
save(render(scenes[4], shift: -300), "unique-0", date: base.addingTimeInterval(20 * 86_400))
save(render(scenes[5], shift: 250), "unique-1", date: base.addingTimeInterval(25 * 86_400))
print("Wrote photo fixtures to \(outDir.path)")
