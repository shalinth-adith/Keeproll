import CoreGraphics
import Foundation
@testable import Keeproll

/// Deterministic pseudo-random numbers for reproducible tests.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum TestImages {
    /// A grayscale image drawn by `shade(x, y)` (0…255).
    static func make(width: Int = 128, height: Int = 128, shade: (Int, Int) -> UInt8) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height { for x in 0..<width { pixels[y * width + x] = shade(x, y) } }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// A diagonal gradient with some blocks: structure for dHash to latch onto.
    static func scene(offset: Int = 0, brightness: Int = 0) -> CGImage {
        make { x, y in
            let base = (x + y + offset) % 256
            let block = ((x / 32 + y / 32) % 2 == 0) ? 60 : 0
            return UInt8(clamping: base / 2 + block + brightness)
        }
    }

    /// The same scene squeezed into a narrower brightness range (0…1 of full contrast).
    static func scene(scale: Double) -> CGImage {
        make { x, y in
            let base = (x + y) % 256
            let block = ((x / 32 + y / 32) % 2 == 0) ? 60 : 0
            let v = Double(base / 2 + block)
            return UInt8(clamping: Int(128 + (v - 94) * scale))
        }
    }

    /// Out-of-focus version: shrink to 1/16 and scale back up with smoothing.
    static func blurred(_ image: CGImage) -> CGImage {
        func draw(_ img: CGImage, _ w: Int, _ h: Int) -> CGImage {
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return ctx.makeImage()!
        }
        return draw(draw(image, image.width / 16, image.height / 16), image.width, image.height)
    }

    static func checkerboard(cell: Int = 4) -> CGImage {
        make { x, y in ((x / cell + y / cell) % 2 == 0) ? 255 : 0 }
    }

    static func flat(_ value: UInt8 = 128) -> CGImage { make { _, _ in value } }
}

func features(_ id: String, at seconds: TimeInterval?, hash: UInt64, print: [Float]? = nil,
              sharpness: Float = 100, favorite: Bool = false) -> AssetFeatures {
    AssetFeatures(id: id, date: seconds.map { Date(timeIntervalSinceReferenceDate: $0) }, dHash: hash,
                  sharpness: sharpness, print: print, isFavorite: favorite, pixelCount: 12_000_000)
}

/// Unit vector at `angle` radians in the first two dimensions of a 4-D print.
func unitPrint(_ angle: Float) -> [Float] { [cos(angle), sin(angle), 0, 0] }
